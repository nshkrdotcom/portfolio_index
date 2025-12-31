defmodule PortfolioIndex.RAG.SelfCorrectingAnswer do
  @moduledoc """
  Answer generation with grounding evaluation and correction loop.

  ## Flow

  1. Generate initial answer from context
  2. Evaluate if answer is grounded in the provided context
  3. If not grounded:
     a. Identify ungrounded claims
     b. Generate corrected answer
     c. Repeat until grounded or max iterations
  4. Return answer with correction history

  ## Usage

      ctx = %Context{
        question: "What is Elixir?",
        results: [%{content: "Elixir is a functional language..."}]
      }

      opts = [llm: &MyLLM.complete/2, max_corrections: 2]

      result_ctx = SelfCorrectingAnswer.answer(ctx, opts)

      result_ctx.answer           # Final answer
      result_ctx.correction_count # Number of corrections made
      result_ctx.corrections      # History of {answer, feedback} tuples

  ## Options

    - `:llm` - LLM function `fn messages, opts -> {:ok, %{content: ...}} end`
    - `:max_corrections` - Maximum correction attempts (default: 2)
    - `:grounding_threshold` - Minimum grounding score (default: 0.7)
    - `:grounding_prompt` - Custom grounding evaluation prompt
    - `:correction_prompt` - Custom correction prompt
  """

  alias PortfolioIndex.RAG.Pipeline.Context

  @type answer_opts :: [
          max_corrections: pos_integer(),
          grounding_threshold: float(),
          grounding_prompt: String.t() | (String.t(), String.t(), [map()] -> String.t()),
          correction_prompt: String.t() | (String.t(), String.t(), String.t() -> String.t()),
          llm: (list(map()), keyword() -> {:ok, map()} | {:error, term()})
        ]

  @type grounding_result :: %{
          grounded: boolean(),
          score: float(),
          ungrounded_claims: [String.t()],
          feedback: String.t()
        }

  @default_answer_prompt """
  Answer the following question using ONLY the provided context.
  Be accurate and concise. If the context doesn't contain enough information,
  say so rather than making up information.

  Context:
  {context}

  Question: {question}

  Answer:
  """

  @default_grounding_prompt """
  Evaluate if the following answer is well-grounded in the provided context.

  Context:
  {context}

  Question: {question}

  Answer to evaluate:
  {answer}

  Analyze the answer and return JSON:
  {
    "grounded": true/false,
    "score": 0.0-1.0 (how well grounded),
    "ungrounded_claims": ["list of claims not supported by context"],
    "feedback": "explanation of issues if not grounded"
  }

  Return ONLY the JSON.
  """

  @default_correction_prompt """
  The previous answer was not well-grounded in the context. Please provide
  a corrected answer that is fully supported by the context.

  Context:
  {context}

  Question: {question}

  Previous answer:
  {previous_answer}

  Issues identified:
  {feedback}

  Ungrounded claims to fix:
  {ungrounded_claims}

  Provide a corrected answer that addresses these issues and is fully grounded in the context:
  """

  @doc """
  Generate answer with self-correction.
  """
  @spec answer(Context.t(), answer_opts()) :: Context.t()
  def answer(%Context{halted?: true} = ctx, _opts), do: ctx
  def answer(%Context{error: error} = ctx, _opts) when not is_nil(error), do: ctx

  def answer(%Context{} = ctx, opts) do
    max_corrections = Keyword.get(opts, :max_corrections, 2)
    grounding_threshold = Keyword.get(opts, :grounding_threshold, 0.7)
    chunks = ctx.results || []

    case generate_answer(ctx.question, chunks, opts) do
      {:ok, initial_answer} ->
        do_correction_loop(
          ctx,
          initial_answer,
          chunks,
          opts,
          grounding_threshold,
          max_corrections,
          0,
          []
        )

      {:error, reason} ->
        Context.halt(ctx, reason)
    end
  end

  defp do_correction_loop(ctx, answer, chunks, _opts, _threshold, max_corrections, count, history)
       when count >= max_corrections do
    %{
      ctx
      | answer: answer,
        context_used: chunks,
        correction_count: count,
        corrections: Enum.reverse(history)
    }
  end

  defp do_correction_loop(ctx, answer, chunks, opts, threshold, max_corrections, count, history) do
    case evaluate_grounding(ctx.question, answer, chunks, opts) do
      {:ok, %{grounded: true}} ->
        %{
          ctx
          | answer: answer,
            context_used: chunks,
            correction_count: count,
            corrections: Enum.reverse(history)
        }

      {:ok, %{grounded: false, score: score} = grounding_result} when score < threshold ->
        feedback = grounding_result[:feedback] || "Answer needs improvement"

        case correct_answer(ctx.question, answer, grounding_result, chunks, opts) do
          {:ok, corrected_answer} ->
            new_history = [{answer, feedback} | history]

            do_correction_loop(
              ctx,
              corrected_answer,
              chunks,
              opts,
              threshold,
              max_corrections,
              count + 1,
              new_history
            )

          {:error, _reason} ->
            # Correction failed, return what we have
            %{
              ctx
              | answer: answer,
                context_used: chunks,
                correction_count: count,
                corrections: Enum.reverse(history)
            }
        end

      {:ok, _} ->
        # Score above threshold, accept answer
        %{
          ctx
          | answer: answer,
            context_used: chunks,
            correction_count: count,
            corrections: Enum.reverse(history)
        }

      {:error, _reason} ->
        # Evaluation failed, accept current answer
        %{
          ctx
          | answer: answer,
            context_used: chunks,
            correction_count: count,
            corrections: Enum.reverse(history)
        }
    end
  end

  @doc """
  Generate initial answer from context.
  """
  @spec generate_answer(String.t(), [map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_answer(question, context_chunks, opts) do
    llm = Keyword.fetch!(opts, :llm)
    custom_prompt = Keyword.get(opts, :answer_prompt)

    context_text = format_context(context_chunks)

    prompt =
      case custom_prompt do
        nil ->
          @default_answer_prompt
          |> String.replace("{context}", context_text)
          |> String.replace("{question}", question)

        custom_fn when is_function(custom_fn, 2) ->
          custom_fn.(question, context_chunks)
      end

    messages = [%{role: :user, content: prompt}]

    case llm.(messages, opts) do
      {:ok, %{content: answer}} ->
        {:ok, String.trim(answer)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Evaluate if answer is grounded in context.
  """
  @spec evaluate_grounding(String.t(), String.t(), [map()], keyword()) ::
          {:ok, grounding_result()} | {:error, term()}
  def evaluate_grounding(question, answer, context_chunks, opts) do
    llm = Keyword.fetch!(opts, :llm)
    custom_prompt = Keyword.get(opts, :grounding_prompt)

    context_text = format_context(context_chunks)

    prompt =
      case custom_prompt do
        nil ->
          @default_grounding_prompt
          |> String.replace("{context}", context_text)
          |> String.replace("{question}", question)
          |> String.replace("{answer}", answer)

        custom_fn when is_function(custom_fn, 3) ->
          custom_fn.(question, answer, context_chunks)
      end

    messages = [%{role: :user, content: prompt}]

    case llm.(messages, opts) do
      {:ok, %{content: response}} ->
        parse_grounding_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate corrected answer based on grounding feedback.
  """
  @spec correct_answer(String.t(), String.t(), grounding_result(), [map()], keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def correct_answer(question, original_answer, grounding_result, context_chunks, opts) do
    llm = Keyword.fetch!(opts, :llm)
    custom_prompt = Keyword.get(opts, :correction_prompt)

    context_text = format_context(context_chunks)
    feedback = grounding_result[:feedback] || ""
    ungrounded_claims = grounding_result[:ungrounded_claims] || []
    claims_text = Enum.join(ungrounded_claims, "\n- ")

    prompt =
      case custom_prompt do
        nil ->
          @default_correction_prompt
          |> String.replace("{context}", context_text)
          |> String.replace("{question}", question)
          |> String.replace("{previous_answer}", original_answer)
          |> String.replace("{feedback}", feedback)
          |> String.replace("{ungrounded_claims}", claims_text)

        custom_fn when is_function(custom_fn, 4) ->
          custom_fn.(question, original_answer, grounding_result, context_chunks)
      end

    messages = [%{role: :user, content: prompt}]

    case llm.(messages, opts) do
      {:ok, %{content: corrected}} ->
        {:ok, String.trim(corrected)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp format_context([]), do: "No context provided."

  defp format_context(chunks) do
    chunks
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {chunk, idx} ->
      content = chunk[:content] || chunk["content"] || ""
      "[#{idx}] #{content}"
    end)
  end

  defp parse_grounding_response(response) do
    case extract_json(response) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, parsed} ->
            result = %{
              grounded: Map.get(parsed, "grounded", true),
              score: Map.get(parsed, "score", 1.0),
              ungrounded_claims: Map.get(parsed, "ungrounded_claims", []),
              feedback: Map.get(parsed, "feedback", "")
            }

            {:ok, result}

          {:error, _} ->
            # Default to grounded on parse failure
            {:ok, %{grounded: true, score: 1.0, ungrounded_claims: [], feedback: ""}}
        end

      :error ->
        # Default to grounded on extraction failure
        {:ok, %{grounded: true, score: 1.0, ungrounded_claims: [], feedback: ""}}
    end
  end

  defp extract_json(content) do
    trimmed = String.trim(content)

    if String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") do
      {:ok, trimmed}
    else
      case Regex.run(~r/\{[\s\S]*\}/, content) do
        [json] -> {:ok, json}
        nil -> :error
      end
    end
  end
end
