defmodule PortfolioIndex.Adapters.CollectionSelector.LLM do
  @moduledoc """
  LLM-based collection selector that routes queries to relevant collections.
  Uses collection descriptions to determine relevance.

  ## Usage

      collections = [
        %{name: "api_docs", description: "REST API reference"},
        %{name: "tutorials", description: "Getting started guides"},
        %{name: "faq", description: "Frequently asked questions"}
      ]

      opts = [context: %{adapters: %{llm: MyLLM}}]
      {:ok, result} = LLM.select("How do I authenticate?", collections, opts)

      result.selected
      # => ["api_docs", "tutorials"]

  ## Custom Prompt

  Provide a custom prompt via the `:prompt` option:

      opts = [
        prompt: fn query, collections -> "Custom prompt..." end,
        context: %{adapters: %{llm: MyLLM}}
      ]
  """

  @behaviour PortfolioCore.Ports.CollectionSelector

  alias PortfolioIndex.RAG.AdapterResolver

  @default_prompt """
  You are a query router. Given a user query and available document collections,
  select the most relevant collections to search.

  User query: {query}

  Available collections:
  {collections}

  Return a JSON object with:
  - "collections": array of collection names to search (1-3 collections)
  - "reasoning": brief explanation of why these collections were selected

  Return ONLY the JSON, nothing else.
  """

  @impl true
  @spec select(String.t(), [map()], keyword()) ::
          {:ok, PortfolioCore.Ports.CollectionSelector.selection_result()} | {:error, term()}
  def select(query, available_collections, opts \\ [])

  def select(_query, [], _opts) do
    {:ok, %{selected: [], reasoning: nil, confidence: nil}}
  end

  def select(query, available_collections, opts) do
    max_collections = Keyword.get(opts, :max_collections, 3)
    prompt_fn = Keyword.get(opts, :prompt)

    {llm, llm_opts} = resolve_llm(opts)

    prompt =
      case prompt_fn do
        nil -> default_prompt(query, available_collections)
        custom_fn when is_function(custom_fn, 2) -> custom_fn.(query, available_collections)
      end

    messages = [%{role: :user, content: prompt}]

    case llm.complete(messages, llm_opts) do
      {:ok, %{content: response}} ->
        parse_response(response, available_collections, max_collections)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Format collection info for prompt.

  ## Examples

      format_collections([
        %{name: "docs", description: "Documentation", document_count: 100}
      ])
      # => "- docs: Documentation (100 docs)"
  """
  @spec format_collections([map()]) :: String.t()
  def format_collections(collections) do
    Enum.map_join(collections, "\n", fn collection ->
      name = collection.name
      description = collection[:description]
      doc_count = collection[:document_count]

      base =
        case description do
          nil -> "- #{name}"
          "" -> "- #{name}"
          desc -> "- #{name}: #{desc}"
        end

      case doc_count do
        nil -> base
        count -> "#{base} (#{count} docs)"
      end
    end)
  end

  # Private functions

  @spec resolve_llm(keyword()) :: {module(), keyword()}
  defp resolve_llm(opts) do
    context = Keyword.get(opts, :context, %{})
    default_llm = PortfolioIndex.Adapters.LLM.Gemini
    AdapterResolver.resolve(context, :llm, default_llm)
  end

  @spec default_prompt(String.t(), [map()]) :: String.t()
  defp default_prompt(query, collections) do
    collections_text = format_collections(collections)

    @default_prompt
    |> String.replace("{query}", query)
    |> String.replace("{collections}", collections_text)
  end

  @spec parse_response(String.t(), [map()], non_neg_integer()) ::
          {:ok, PortfolioCore.Ports.CollectionSelector.selection_result()}
  defp parse_response(response, available_collections, max_collections) do
    fallback_names = Enum.map(available_collections, & &1.name)

    case extract_json(response) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, %{"collections" => cols, "reasoning" => reason}} when is_list(cols) ->
            selected = filter_valid_collections(cols, fallback_names, max_collections)
            {:ok, %{selected: selected, reasoning: reason, confidence: nil}}

          {:ok, %{"collections" => cols}} when is_list(cols) ->
            selected = filter_valid_collections(cols, fallback_names, max_collections)
            {:ok, %{selected: selected, reasoning: nil, confidence: nil}}

          _ ->
            {:ok, %{selected: fallback_names, reasoning: nil, confidence: nil}}
        end

      :error ->
        {:ok, %{selected: fallback_names, reasoning: nil, confidence: nil}}
    end
  end

  @spec extract_json(String.t()) :: {:ok, String.t()} | :error
  defp extract_json(content) do
    trimmed = String.trim(content)

    if String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") do
      {:ok, trimmed}
    else
      case Regex.run(~r/\{[^{}]*\}/, content) do
        [json] -> {:ok, json}
        nil -> :error
      end
    end
  end

  @spec filter_valid_collections([String.t()], [String.t()], non_neg_integer()) :: [String.t()]
  defp filter_valid_collections(selected, available, max_collections) do
    selected
    |> Enum.filter(&(&1 in available))
    |> Enum.take(max_collections)
  end
end
