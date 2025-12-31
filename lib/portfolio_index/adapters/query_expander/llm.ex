defmodule PortfolioIndex.Adapters.QueryExpander.LLM do
  @moduledoc """
  LLM-based query expander that adds synonyms and related terms.
  Improves recall by including alternative phrasings.

  Implements the `PortfolioCore.Ports.QueryExpander` behaviour.

  ## Usage

      # With AdapterResolver context
      opts = [context: %{adapters: %{llm: MyLLM}}]
      {:ok, result} = LLM.expand("ML models", opts)
      result.expanded
      # => "ML machine learning models neural networks deep learning"

      # With custom prompt
      custom_prompt = fn query -> "Expand this: \#{query}" end
      {:ok, result} = LLM.expand(query, prompt: custom_prompt, context: ctx)

  ## Expansion Strategy

  The LLM expands queries by adding:
  - Synonyms (ML -> machine learning)
  - Abbreviation expansions (API -> application programming interface)
  - Related technical terms (GenServer -> OTP, process)
  - Alternative phrasings for better embedding coverage
  """

  @behaviour PortfolioCore.Ports.QueryExpander

  require Logger

  alias PortfolioIndex.RAG.AdapterResolver

  @default_prompt """
  You are a search query expansion assistant. Your task is to expand the user's query with synonyms and related terms to improve document retrieval.

  Rules:
  - Keep ALL original terms from the query
  - Add synonyms and related terms that convey the same meaning
  - Expand abbreviations and acronyms (e.g., "ML" -> "ML machine learning")
  - Do NOT remove or replace technical terms you don't recognize
  - Return a single expanded query string, nothing else

  Examples:
  Query: "ML models for NLP"
  Expanded: "ML machine learning models for NLP natural language processing text analysis"

  Query: "remote work productivity"
  Expanded: "remote work telecommuting working from home productivity efficiency performance"

  Query: "Phoenix LiveView real-time"
  Expanded: "Phoenix LiveView real-time live updates websocket server-rendered interactive"

  Query: "GenServer state management"
  Expanded: "GenServer gen_server OTP server state management process Elixir"

  Now expand this query:
  "{query}"
  """

  @impl true
  @spec expand(String.t(), keyword()) ::
          {:ok, PortfolioCore.Ports.QueryExpander.expansion_result()} | {:error, term()}
  def expand(query, opts \\ []) do
    {llm, llm_opts} = resolve_llm(opts)
    prompt_fn = Keyword.get(opts, :prompt)

    prompt = build_prompt(query, prompt_fn)
    messages = [%{role: :user, content: prompt}]

    case llm.complete(messages, llm_opts) do
      {:ok, %{content: expanded}} ->
        expanded_clean = String.trim(expanded)

        # Fall back to original if LLM returns empty
        final_expanded = if expanded_clean == "", do: query, else: expanded_clean
        added_terms = extract_added_terms(query, final_expanded)

        emit_telemetry(:expand, %{added_term_count: length(added_terms)}, %{})

        {:ok,
         %{
           original: query,
           expanded: final_expanded,
           added_terms: added_terms
         }}

      {:error, reason} = error ->
        Logger.warning("Query expansion failed: #{inspect(reason)}")
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

  @spec extract_added_terms(String.t(), String.t()) :: [String.t()]
  defp extract_added_terms(original, expanded) do
    original_terms =
      original
      |> String.downcase()
      |> String.split(~r/\s+/)
      |> MapSet.new()

    expanded
    |> String.split(~r/\s+/)
    |> Enum.reject(fn term ->
      MapSet.member?(original_terms, String.downcase(term))
    end)
    |> Enum.uniq()
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :query_expander, :llm, event],
      measurements,
      metadata
    )
  end
end
