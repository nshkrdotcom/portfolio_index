defmodule PortfolioIndex.Telemetry.VectorStore do
  @moduledoc """
  Vector store telemetry utilities.

  Provides utilities for wrapping vector store operations with telemetry instrumentation.

  ## Usage

      alias PortfolioIndex.Telemetry.VectorStore

      VectorStore.search_span(
        backend: :pgvector,
        collection: "documents",
        limit: 10
      ], fn ->
        Pgvector.search(embedding, opts)
      end)

  ## Metadata Fields

  Search spans include:
  - `:backend` - Vector store backend
  - `:collection` - Collection name (if applicable)
  - `:limit` - Requested result limit
  - `:result_count` - Actual results returned
  - `:mode` - Search mode (semantic, hybrid)

  Insert spans include:
  - `:backend` - Vector store backend
  - `:collection` - Collection name
  - `:count` - Number of items inserted (for batch)
  """

  @doc """
  Wrap a search operation with telemetry.

  Emits `[:portfolio, :vector_store, :search, :start]`, `[:portfolio, :vector_store, :search, :stop]`,
  and `[:portfolio, :vector_store, :search, :exception]` events.

  ## Parameters

    - `metadata` - Keyword list with search context:
      - `:backend` - Vector store backend (:pgvector, :memory, :qdrant)
      - `:collection` - Collection name (optional)
      - `:limit` - Requested result limit
      - `:mode` - Search mode (:semantic, :hybrid, :fulltext)
    - `fun` - Function that performs the search

  ## Example

      VectorStore.search_span([backend: :pgvector, limit: 10], fn ->
        Pgvector.search(embedding, limit: 10)
      end)
  """
  @spec search_span(keyword(), (-> result)) :: result when result: any()
  def search_span(metadata, fun) when is_function(fun, 0) do
    enriched_metadata = enrich_metadata(metadata)

    :telemetry.span(
      [:portfolio, :vector_store, :search],
      Map.new(enriched_metadata),
      fn ->
        result = fun.()
        stop_meta = enrich_search_stop_metadata(result)
        {result, stop_meta}
      end
    )
  end

  @doc """
  Wrap an insert operation with telemetry.

  Emits `[:portfolio, :vector_store, :insert, :start]`, `[:portfolio, :vector_store, :insert, :stop]`,
  and `[:portfolio, :vector_store, :insert, :exception]` events.

  ## Parameters

    - `metadata` - Keyword list with insert context:
      - `:backend` - Vector store backend
      - `:collection` - Collection name (optional)
      - `:id` - Item ID
    - `fun` - Function that performs the insert

  ## Example

      VectorStore.insert_span([backend: :pgvector, collection: "docs"], fn ->
        Pgvector.insert(id, embedding, metadata)
      end)
  """
  @spec insert_span(keyword(), (-> result)) :: result when result: any()
  def insert_span(metadata, fun) when is_function(fun, 0) do
    enriched_metadata = enrich_metadata(metadata)

    :telemetry.span(
      [:portfolio, :vector_store, :insert],
      Map.new(enriched_metadata),
      fn ->
        result = fun.()
        stop_meta = enrich_insert_stop_metadata(result)
        {result, stop_meta}
      end
    )
  end

  @doc """
  Wrap a batch insert operation with telemetry.

  Emits `[:portfolio, :vector_store, :insert_batch, :start]`, `[:portfolio, :vector_store, :insert_batch, :stop]`,
  and `[:portfolio, :vector_store, :insert_batch, :exception]` events.

  ## Parameters

    - `metadata` - Keyword list with batch insert context:
      - `:backend` - Vector store backend
      - `:collection` - Collection name (optional)
      - `:count` - Number of items being inserted
      - `:items` - List of items (will extract count)
    - `fun` - Function that performs the batch insert

  ## Example

      VectorStore.batch_insert_span([backend: :pgvector, count: 100], fn ->
        Pgvector.insert_batch(items)
      end)
  """
  @spec batch_insert_span(keyword(), (-> result)) :: result when result: any()
  def batch_insert_span(metadata, fun) when is_function(fun, 0) do
    enriched_metadata = enrich_batch_metadata(metadata)

    :telemetry.span(
      [:portfolio, :vector_store, :insert_batch],
      Map.new(enriched_metadata),
      fn ->
        result = fun.()
        stop_meta = enrich_batch_stop_metadata(result)
        {result, stop_meta}
      end
    )
  end

  # Private functions

  defp enrich_metadata(metadata) do
    metadata
    |> Keyword.take([:backend, :collection, :limit, :mode, :id])
    |> Keyword.put_new(:backend, :unknown)
  end

  defp enrich_batch_metadata(metadata) do
    base =
      metadata
      |> Keyword.take([:backend, :collection, :count])
      |> Keyword.put_new(:backend, :unknown)

    # Calculate count if items provided
    case Keyword.get(metadata, :items) do
      items when is_list(items) ->
        Keyword.put_new(base, :count, length(items))

      _ ->
        base
    end
  end

  defp enrich_search_stop_metadata({:ok, results}) when is_list(results) do
    %{result_count: length(results)}
  end

  defp enrich_search_stop_metadata(results) when is_list(results) do
    %{result_count: length(results)}
  end

  defp enrich_search_stop_metadata({:error, _reason}) do
    %{success: false}
  end

  defp enrich_search_stop_metadata(_) do
    %{}
  end

  defp enrich_insert_stop_metadata({:ok, _}) do
    %{success: true}
  end

  defp enrich_insert_stop_metadata(:ok) do
    %{success: true}
  end

  defp enrich_insert_stop_metadata({:error, _reason}) do
    %{success: false}
  end

  defp enrich_insert_stop_metadata(_) do
    %{}
  end

  defp enrich_batch_stop_metadata({:ok, %{inserted: count}}) when is_integer(count) do
    %{inserted_count: count, success: true}
  end

  defp enrich_batch_stop_metadata({:ok, _}) do
    %{success: true}
  end

  defp enrich_batch_stop_metadata(:ok) do
    %{success: true}
  end

  defp enrich_batch_stop_metadata({:error, _reason}) do
    %{success: false}
  end

  defp enrich_batch_stop_metadata(_) do
    %{}
  end
end
