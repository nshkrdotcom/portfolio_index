defmodule PortfolioIndex.RAG.Strategies.SelfRAG do
  @moduledoc """
  Self-RAG strategy with retrieval assessment and self-critique.

  Implements a reflective RAG approach that:
  1. Assesses whether retrieval is needed
  2. Retrieves relevant documents
  3. Generates an answer with self-critique
  4. Refines the answer if critique scores are low

  ## Strategy

  1. Determine if retrieval is needed (for factual queries)
  2. If needed, retrieve using Hybrid strategy
  3. Generate answer with embedded critique
  4. If critique scores are low, refine the answer
  5. Return final answer with critique metadata

  ## Configuration

      context = %{index_id: "my_index"}
      opts = [k: 5, min_critique_score: 3]

      {:ok, result} = SelfRAG.retrieve("What is GenServer?", context, opts)
  """

  @behaviour PortfolioIndex.RAG.Strategy

  # Suppress dialyzer warnings for adapter calls that may not be fully typed
  @dialyzer {:nowarn_function, retrieve: 3}

  alias PortfolioIndex.Adapters.LLM.Gemini, as: LLM
  alias PortfolioIndex.RAG.Strategies.Hybrid

  require Logger

  @impl true
  def name, do: :self_rag

  @impl true
  def required_adapters, do: [:vector_store, :embedder, :llm]

  @impl true
  def retrieve(query, context, opts) do
    start_time = System.monotonic_time(:millisecond)
    _k = Keyword.get(opts, :k, 5)
    min_critique = Keyword.get(opts, :min_critique_score, 3)

    with {:ok, needs_retrieval} <- assess_retrieval_need(query),
         {:ok, retrieved} <- maybe_retrieve(query, context, opts, needs_retrieval),
         {:ok, answer, critique, tokens1} <- generate_with_critique(query, retrieved),
         {:ok, final_answer, tokens2} <-
           maybe_refine(query, answer, critique, retrieved, min_critique) do
      duration = System.monotonic_time(:millisecond) - start_time
      total_tokens = tokens1 + tokens2

      emit_telemetry(
        %{
          duration_ms: duration,
          items_returned: length(retrieved.items),
          tokens_used: total_tokens
        },
        %{strategy: :self_rag}
      )

      {:ok,
       %{
         items: retrieved.items,
         query: query,
         answer: final_answer,
         strategy: :self_rag,
         timing_ms: duration,
         tokens_used: total_tokens,
         critique: critique,
         retrieval_used: needs_retrieval
       }}
    else
      {:error, reason} ->
        Logger.error("Self-RAG failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp assess_retrieval_need(query) do
    messages = [
      %{
        role: :system,
        content: """
        Determine if external knowledge retrieval is needed to answer this query.
        Consider:
        - Factual questions need retrieval
        - Opinion or creative tasks may not
        - Questions about specific topics/code need retrieval

        Respond with exactly YES or NO.
        """
      },
      %{role: :user, content: query}
    ]

    case LLM.complete(messages, max_tokens: 10) do
      {:ok, %{content: response}} ->
        needs = String.contains?(String.upcase(response), "YES")
        {:ok, needs}

      {:error, reason} ->
        Logger.warning("Retrieval assessment failed: #{inspect(reason)}, defaulting to YES")
        {:ok, true}
    end
  end

  defp maybe_retrieve(query, context, opts, true) do
    Hybrid.retrieve(query, context, opts)
  end

  defp maybe_retrieve(_query, _context, _opts, false) do
    {:ok, %{items: [], query: "", timing_ms: 0, tokens_used: 0}}
  end

  defp generate_with_critique(query, retrieved) do
    context_text = Enum.map_join(retrieved.items, "\n\n---\n\n", & &1.content)

    messages = [
      %{
        role: :system,
        content: """
        Answer the question using the provided context.

        After your answer, provide a self-critique on a scale of 1-5:
        - Relevance: How relevant is your answer to the question?
        - Support: How well is your answer supported by the context?
        - Completeness: How complete is your answer?

        Format your response EXACTLY as:
        ANSWER: [your detailed answer here]

        CRITIQUE:
        - Relevance: [1-5]
        - Support: [1-5]
        - Completeness: [1-5]
        """
      },
      %{
        role: :user,
        content: """
        Context:
        #{context_text}

        Question: #{query}
        """
      }
    ]

    case LLM.complete(messages, max_tokens: 2000) do
      {:ok, %{content: response, usage: usage}} ->
        {answer, critique} = parse_critique(response)
        tokens = (usage[:input_tokens] || 0) + (usage[:output_tokens] || 0)
        {:ok, answer, critique, tokens}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_critique(response) do
    case String.split(response, "CRITIQUE:", parts: 2) do
      [answer_part, critique_text] ->
        answer =
          answer_part
          |> String.replace("ANSWER:", "")
          |> String.trim()

        critique = %{
          relevance: extract_score(critique_text, "Relevance"),
          support: extract_score(critique_text, "Support"),
          completeness: extract_score(critique_text, "Completeness")
        }

        {answer, critique}

      _ ->
        # No critique found, assume good scores
        {response, %{relevance: 4, support: 4, completeness: 4}}
    end
  end

  defp extract_score(text, metric) do
    case Regex.run(~r/#{metric}:\s*(\d)/, text) do
      [_, score] -> String.to_integer(score)
      nil -> 3
    end
  end

  defp maybe_refine(query, answer, critique, retrieved, min_score) do
    min_critique = Enum.min([critique.relevance, critique.support, critique.completeness])

    if min_critique < min_score do
      refine_answer(query, answer, critique, retrieved)
    else
      {:ok, answer, 0}
    end
  end

  defp refine_answer(query, previous_answer, critique, retrieved) do
    context_text = Enum.map_join(retrieved.items, "\n\n---\n\n", & &1.content)

    messages = [
      %{
        role: :system,
        content: """
        The previous answer received low scores. Please provide an improved answer.

        Previous critique scores:
        - Relevance: #{critique.relevance}/5
        - Support: #{critique.support}/5
        - Completeness: #{critique.completeness}/5

        Focus on improving the areas with low scores.
        """
      },
      %{
        role: :user,
        content: """
        Context:
        #{context_text}

        Question: #{query}

        Previous answer:
        #{previous_answer}

        Please provide an improved, more complete answer:
        """
      }
    ]

    case LLM.complete(messages, max_tokens: 2000) do
      {:ok, %{content: response, usage: usage}} ->
        tokens = (usage[:input_tokens] || 0) + (usage[:output_tokens] || 0)
        {:ok, response, tokens}

      {:error, reason} ->
        # If refinement fails, return original answer
        Logger.warning("Answer refinement failed: #{inspect(reason)}")
        {:ok, previous_answer, 0}
    end
  end

  defp emit_telemetry(measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :rag, :retrieve],
      measurements,
      metadata
    )
  end
end
