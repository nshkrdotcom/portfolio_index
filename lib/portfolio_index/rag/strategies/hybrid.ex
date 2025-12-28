defmodule PortfolioIndex.RAG.Strategies.Hybrid do
  @moduledoc """
  Hybrid retrieval strategy combining vector and keyword search.

  Uses Reciprocal Rank Fusion (RRF) to merge results from multiple
  retrieval methods.

  ## Strategy

  1. Generate query embedding
  2. Perform vector similarity search
  3. Perform keyword search (if available)
  4. Merge results using RRF
  5. Return top-k results

  ## Configuration

      context = %{
        index_id: "my_index",
        filters: %{type: "documentation"}
      }

      opts = [k: 10, rrf_k: 60]

      {:ok, result} = Hybrid.retrieve("What is Elixir?", context, opts)
  """

  @behaviour PortfolioIndex.RAG.Strategy

  # Suppress dialyzer warnings for adapter calls that may not be fully typed
  @dialyzer [
    {:nowarn_function, retrieve: 3},
    {:nowarn_function, format_results: 1},
    {:nowarn_function, emit_telemetry: 2}
  ]

  alias PortfolioCore.VectorStore.RRF
  alias PortfolioIndex.Adapters.Embedder.Gemini, as: DefaultEmbedder
  alias PortfolioIndex.Adapters.VectorStore.Pgvector, as: DefaultVectorStore
  alias PortfolioIndex.RAG.AdapterResolver

  require Logger

  @impl true
  def name, do: :hybrid

  @impl true
  def required_adapters, do: [:vector_store, :embedder]

  @impl true
  def retrieve(query, context, opts) do
    start_time = System.monotonic_time(:millisecond)
    k = Keyword.get(opts, :k, 10)
    rrf_k = Keyword.get(opts, :rrf_k, 60)
    index_id = context[:index_id] || "default"
    filter = context[:filters]

    {embedder, embedder_opts} = AdapterResolver.resolve(context, :embedder, DefaultEmbedder)

    {vector_store, vector_opts} =
      AdapterResolver.resolve(context, :vector_store, DefaultVectorStore)

    vector_opts = maybe_add_filter(vector_opts, filter)
    keyword_opts = Keyword.put(vector_opts, :mode, :keyword)
    fulltext_opts = Keyword.delete(vector_opts, :mode)

    with {:ok, %{vector: query_vector, token_count: tokens}} <-
           embedder.embed(query, embedder_opts),
         {:ok, vector_results} <-
           vector_store.search(index_id, query_vector, k * 2, vector_opts) do
      keyword_results =
        fetch_keyword_results(vector_store, index_id, query, k * 2, fulltext_opts, keyword_opts)

      merged = RRF.calculate_rrf_score(vector_results, keyword_results, k: rrf_k)

      final = Enum.take(merged, k)

      duration = System.monotonic_time(:millisecond) - start_time

      emit_telemetry(
        %{
          duration_ms: duration,
          items_returned: length(final),
          tokens_used: tokens
        },
        %{strategy: :hybrid, index_id: index_id}
      )

      {:ok,
       %{
         items: format_results(final),
         query: query,
         answer: nil,
         strategy: :hybrid,
         timing_ms: duration,
         tokens_used: tokens
       }}
    else
      {:error, reason} ->
        Logger.error("Hybrid retrieval failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Perform Reciprocal Rank Fusion on multiple ranked lists.

  RRF score = sum(1 / (k + rank)) across all lists

  ## Parameters

  - `ranked_lists` - List of `{source, results}` tuples
  - `opts` - Options including `:k` (default 60)
  """
  def reciprocal_rank_fusion(ranked_lists, opts) do
    lists = Enum.map(ranked_lists, fn {_source, items} -> ensure_vector_key(items) end)
    k = Keyword.get(opts, :k, 60)

    case lists do
      [] ->
        []

      [items] ->
        RRF.calculate_rrf_score(items, [], k: k)

      [items_a, items_b | rest] ->
        Enum.reduce(rest, RRF.calculate_rrf_score(items_a, items_b, k: k), fn items, acc ->
          RRF.calculate_rrf_score(acc, ensure_vector_key(items), k: k)
        end)
    end
  end

  # Private functions

  defp format_results(results) do
    Enum.map(results, fn result ->
      metadata = result[:metadata] || result.metadata || %{}

      %{
        content:
          result[:content] ||
            metadata[:content] ||
            metadata["content"] ||
            "",
        score: result.score,
        source:
          metadata[:source] ||
            metadata["source"] ||
            result[:source] ||
            "",
        metadata: metadata
      }
    end)
  end

  defp maybe_add_filter(vector_opts, nil), do: vector_opts
  defp maybe_add_filter(vector_opts, filter), do: Keyword.put(vector_opts, :filter, filter)

  defp ensure_vector_key(items) do
    Enum.map(items, &Map.put_new(&1, :vector, nil))
  end

  defp fetch_keyword_results(vector_store, index_id, query, limit, fulltext_opts, keyword_opts) do
    if function_exported?(vector_store, :fulltext_search, 4) do
      case vector_store.fulltext_search(index_id, query, limit, fulltext_opts) do
        {:ok, results} ->
          results

        {:error, reason} ->
          Logger.info("Fulltext search unavailable: #{inspect(reason)}")
          []
      end
    else
      case vector_store.search(index_id, query, limit, keyword_opts) do
        {:ok, results} ->
          results

        {:error, reason} ->
          Logger.info("Keyword search unavailable: #{inspect(reason)}")
          []
      end
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
