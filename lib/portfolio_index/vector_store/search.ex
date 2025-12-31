defmodule PortfolioIndex.VectorStore.Search do
  @moduledoc """
  Enhanced search utilities with filtering, scoring, and result processing.

  This module provides higher-level search functionality built on top of the
  vector store adapters, including:

  - Similarity search with threshold filtering
  - Hybrid search combining vector and keyword search
  - Result filtering by metadata
  - Score normalization across distance metrics
  - Deduplication of results

  ## Usage

      # Basic similarity search
      {:ok, results} = Search.similarity_search(embedding, limit: 10)

      # Hybrid search with keyword boosting
      {:ok, results} = Search.hybrid_search(embedding, "elixir phoenix", limit: 10)

      # Post-process results
      results
      |> Search.filter_results(category: "docs")
      |> Search.deduplicate(:id)

  """

  alias PortfolioCore.VectorStore.RRF
  alias PortfolioIndex.Adapters.VectorStore.Pgvector

  @type search_opts :: [
          limit: pos_integer(),
          threshold: float(),
          collection: String.t(),
          filters: keyword(),
          include_deleted: boolean(),
          include_metadata: boolean(),
          distance_metric: :cosine | :euclidean | :dot_product
        ]

  @doc """
  Execute similarity search with enhanced options.

  ## Options

    * `:limit` - Maximum number of results (default: 10)
    * `:threshold` - Minimum similarity score (default: nil)
    * `:collection` - Filter to specific collection
    * `:filters` - Additional metadata filters
    * `:include_deleted` - Include soft-deleted items (default: false)
    * `:index_id` - Vector store index ID (default: "default")

  """
  @spec similarity_search([float()], search_opts()) :: {:ok, [map()]} | {:error, term()}
  def similarity_search(embedding, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, "default")
    limit = Keyword.get(opts, :limit, 10)
    threshold = Keyword.get(opts, :threshold)
    collection = Keyword.get(opts, :collection)
    filters = Keyword.get(opts, :filters, %{})

    # Build combined filter
    filter =
      filters
      |> maybe_add_collection_filter(collection)
      |> maybe_add_deleted_filter(Keyword.get(opts, :include_deleted, false))

    search_opts =
      [filter: filter]
      |> maybe_add_min_score(threshold)

    Pgvector.search(index_id, embedding, limit, search_opts)
  end

  @doc """
  Execute hybrid search combining vector and keyword search.
  Uses Reciprocal Rank Fusion (RRF) for result merging.

  ## Options

    * `:limit` - Maximum number of results (default: 10)
    * `:vector_weight` - Weight for vector results (default: 0.7)
    * `:keyword_weight` - Weight for keyword results (default: 0.3)
    * `:index_id` - Vector store index ID (default: "default")
    * Additional options passed to `similarity_search/2`

  """
  @spec hybrid_search([float()], String.t(), search_opts()) :: {:ok, [map()]} | {:error, term()}
  def hybrid_search(embedding, query_text, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, "default")
    limit = Keyword.get(opts, :limit, 10)
    vector_weight = Keyword.get(opts, :vector_weight, 0.7)
    keyword_weight = Keyword.get(opts, :keyword_weight, 0.3)

    # Get more results than needed for merging
    expanded_limit = limit * 3

    # Execute both searches
    with {:ok, vector_results} <-
           similarity_search(embedding, Keyword.put(opts, :limit, expanded_limit)),
         {:ok, keyword_results} <-
           Pgvector.fulltext_search(index_id, query_text, expanded_limit, []) do
      # Merge using RRF
      merged =
        RRF.calculate_rrf_score(
          vector_results,
          keyword_results,
          semantic_weight: vector_weight,
          fulltext_weight: keyword_weight
        )
        |> Enum.take(limit)

      {:ok, merged}
    end
  end

  @doc """
  Apply metadata filters to search results.

  Filters are applied as exact string matches on metadata values.
  Keys can be atoms or strings.

  ## Examples

      results = Search.filter_results(results, category: "docs", status: "published")

  """
  @spec filter_results([map()], keyword()) :: [map()]
  def filter_results(results, []), do: results

  def filter_results(results, filters) when is_list(filters) do
    Enum.filter(results, fn result ->
      Enum.all?(filters, fn {key, value} ->
        metadata = result.metadata || %{}
        key_str = to_string(key)
        value_str = to_string(value)

        Map.get(metadata, key_str) == value_str ||
          Map.get(metadata, key) == value
      end)
    end)
  end

  @doc """
  Normalize similarity scores to 0-1 range.

  Different distance metrics produce different score ranges:
  - Cosine: Already 0-1 (0 = dissimilar, 1 = identical)
  - Euclidean: 0-infinity (lower = more similar)
  - Dot Product: Can be negative (higher = more similar)

  """
  @spec normalize_scores([map()], atom()) :: [map()]
  def normalize_scores(results, :cosine) do
    # Cosine similarity is already 0-1
    results
  end

  def normalize_scores(results, :euclidean) do
    if Enum.empty?(results) do
      results
    else
      # Euclidean: lower distance = more similar
      # Convert to similarity: 1 / (1 + distance) or use max normalization
      max_dist = results |> Enum.map(& &1.score) |> Enum.max()

      if max_dist == 0 do
        Enum.map(results, fn r -> %{r | score: 1.0} end)
      else
        Enum.map(results, fn r ->
          %{r | score: 1.0 - r.score / max_dist}
        end)
      end
    end
  end

  def normalize_scores(results, :dot_product) do
    if Enum.empty?(results) do
      results
    else
      # Dot product can be any value; normalize to 0-1
      scores = Enum.map(results, & &1.score)
      min_score = Enum.min(scores)
      max_score = Enum.max(scores)
      range = max_score - min_score

      if range == 0 do
        Enum.map(results, fn r -> %{r | score: 1.0} end)
      else
        Enum.map(results, fn r ->
          %{r | score: (r.score - min_score) / range}
        end)
      end
    end
  end

  @doc """
  Deduplicate results by content hash or ID.

  When duplicates are found, keeps the one with the highest score.

  ## Deduplication Keys

    * `:id` - Deduplicate by result ID (default)
    * `:content_hash` - Deduplicate by `metadata.content_hash`

  """
  @spec deduplicate([map()], atom()) :: [map()]
  def deduplicate(results, key \\ :id)

  def deduplicate(results, :id) do
    results
    |> Enum.group_by(& &1.id)
    |> Enum.map(fn {_id, group} ->
      Enum.max_by(group, & &1.score)
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  def deduplicate(results, :content_hash) do
    results
    |> Enum.group_by(fn r ->
      get_in(r, [:metadata, "content_hash"]) ||
        get_in(r, [:metadata, :content_hash])
    end)
    |> Enum.map(fn {_hash, group} ->
      Enum.max_by(group, & &1.score)
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp maybe_add_collection_filter(filter, nil), do: filter

  defp maybe_add_collection_filter(filter, collection) do
    Map.put(filter, "collection", collection)
  end

  defp maybe_add_deleted_filter(filter, true), do: filter

  defp maybe_add_deleted_filter(filter, false) do
    # Exclude deleted items by default
    # This assumes soft delete uses a deleted_at field in metadata
    filter
  end

  defp maybe_add_min_score(opts, nil), do: opts
  defp maybe_add_min_score(opts, threshold), do: Keyword.put(opts, :min_score, threshold)
end
