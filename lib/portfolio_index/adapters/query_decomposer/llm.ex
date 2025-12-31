defmodule PortfolioIndex.Adapters.QueryDecomposer.LLM do
  @moduledoc """
  LLM-based query decomposer that breaks complex questions into simpler sub-questions.
  Returns JSON with sub_questions array.

  Implements the `PortfolioCore.Ports.QueryDecomposer` behaviour.

  ## Usage

      # With AdapterResolver context
      opts = [context: %{adapters: %{llm: MyLLM}}]
      {:ok, result} = LLM.decompose("Compare Elixir and Go", opts)
      result.sub_questions
      # => ["What are Elixir's features?", "What are Go's features?", "How do they compare?"]

      # With custom prompt
      custom_prompt = fn query -> "Decompose: \#{query}" end
      {:ok, result} = LLM.decompose(query, prompt: custom_prompt, context: ctx)

  ## Decomposition Strategy

  The LLM identifies:
  - Comparison questions ("Compare X and Y")
  - Multi-part questions ("What is X and how does it work?")
  - Multi-hop reasoning needs
  - Simple questions that don't need decomposition
  """

  @behaviour PortfolioCore.Ports.QueryDecomposer

  require Logger

  alias PortfolioIndex.RAG.AdapterResolver

  @default_prompt """
  You are an AI assistant that breaks down complex questions into simpler sub-questions for a search system.

  Rules:
  - Generate 2-4 sub-questions that can be answered independently
  - Each sub-question should retrieve different information from the knowledge base
  - Do NOT rephrase acronyms or technical terms you don't recognize
  - If the question is already simple, return it unchanged

  Example:
  Question: "How does Phoenix LiveView compare to React for real-time features?"
  {"sub_questions": ["How does Phoenix LiveView handle real-time updates?", "How does React handle real-time updates?", "What are the performance characteristics of Phoenix LiveView?"]}

  Example:
  Question: "What is pattern matching?"
  {"sub_questions": ["What is pattern matching?"]}

  Now decompose this question:
  "{query}"

  Return JSON only: {"sub_questions": ["q1", "q2", ...]}
  """

  @impl true
  @spec decompose(String.t(), keyword()) ::
          {:ok, PortfolioCore.Ports.QueryDecomposer.decomposition_result()} | {:error, term()}
  def decompose(query, opts \\ []) do
    {llm, llm_opts} = resolve_llm(opts)
    prompt_fn = Keyword.get(opts, :prompt)

    prompt = build_prompt(query, prompt_fn)
    messages = [%{role: :user, content: prompt}]

    case llm.complete(messages, llm_opts) do
      {:ok, %{content: response}} ->
        case parse_response(response, query) do
          {:ok, sub_questions} ->
            is_complex = length(sub_questions) > 1

            emit_telemetry(:decompose, %{sub_question_count: length(sub_questions)}, %{})

            {:ok,
             %{
               original: query,
               sub_questions: sub_questions,
               is_complex: is_complex
             }}

          {:error, _reason} ->
            # Fallback: return original as single sub-question
            {:ok,
             %{
               original: query,
               sub_questions: [query],
               is_complex: false
             }}
        end

      {:error, reason} = error ->
        Logger.warning("Query decomposition failed: #{inspect(reason)}")
        error
    end
  end

  @spec resolve_llm(keyword()) :: {module(), keyword()}
  defp resolve_llm(opts) do
    context = Keyword.get(opts, :context, %{})
    default_llm = PortfolioIndex.Adapters.LLM.Gemini
    AdapterResolver.resolve(context, :llm, default_llm)
  end

  @spec build_prompt(String.t(), (String.t() -> String.t()) | nil) :: String.t()
  defp build_prompt(query, nil) do
    String.replace(@default_prompt, "{query}", query)
  end

  defp build_prompt(query, prompt_fn) when is_function(prompt_fn, 1) do
    prompt_fn.(query)
  end

  @spec parse_response(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  defp parse_response(response, fallback_query) do
    json_string = extract_json(response)

    case Jason.decode(json_string) do
      {:ok, %{"sub_questions" => [_ | _] = questions}} ->
        {:ok, questions}

      {:ok, %{"subquestions" => [_ | _] = questions}} ->
        {:ok, questions}

      {:ok, %{"questions" => [_ | _] = questions}} ->
        {:ok, questions}

      {:ok, %{"sub_questions" => []}} ->
        {:ok, [fallback_query]}

      {:ok, _} ->
        {:error, :invalid_structure}

      {:error, _} ->
        {:error, :json_parse_failed}
    end
  end

  @spec extract_json(String.t()) :: String.t()
  defp extract_json(response) do
    # Try to find JSON object in the response
    case Regex.run(
           ~r/\{[^{}]*"(?:sub_questions|subquestions|questions)"[^{}]*\}/s,
           response
         ) do
      [json] -> json
      _ -> response
    end
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :query_decomposer, :llm, event],
      measurements,
      metadata
    )
  end
end
