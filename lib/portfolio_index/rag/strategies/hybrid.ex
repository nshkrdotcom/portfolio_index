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

    with {:ok, %{vector: query_vector, token_count: tokens}} <-
           embedder.embed(query, embedder_opts),
         {:ok, vector_results} <-
           vector_store.search(index_id, query_vector, k * 2, vector_opts) do
      keyword_results =
        case vector_store.search(index_id, query, k * 2, keyword_opts) do
          {:ok, results} ->
            results

          {:error, reason} ->
            Logger.info("Keyword search unavailable: #{inspect(reason)}")
            []
        end

      merged =
        reciprocal_rank_fusion(
          [
            {:vector, vector_results},
            {:keyword, keyword_results}
          ],
          k: rrf_k
        )

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
    k = Keyword.get(opts, :k, 60)

    # Calculate RRF scores for each item
    all_scores =
      Enum.reduce(ranked_lists, %{}, fn {_source, items}, acc ->
        merge_ranked_items(items, acc, k)
      end)

    # Sort by combined RRF score
    all_scores
    |> Map.values()
    |> Enum.sort_by(fn {_item, score} -> -score end)
    |> Enum.map(fn {item, score} ->
      Map.put(item, :score, score)
    end)
  end

  defp merge_ranked_items(items, acc, k) do
    items
    |> Enum.with_index(1)
    |> Enum.reduce(acc, fn {item, rank}, inner_acc ->
      add_rrf_score(item, rank, inner_acc, k)
    end)
  end

  defp add_rrf_score(item, rank, acc, k) do
    item_id = item.id || item[:id]
    rrf_score = 1.0 / (k + rank)

    Map.update(acc, item_id, {item, rrf_score}, fn {existing, score} ->
      {existing, score + rrf_score}
    end)
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

  defp emit_telemetry(measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :rag, :retrieve],
      measurements,
      metadata
    )
  end
end
