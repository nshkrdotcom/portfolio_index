defmodule PortfolioIndex.Adapters.VectorStore.Pgvector.FullText do
  @moduledoc """
  PostgreSQL tsvector-based full-text search.

  Provides proper full-text search capabilities using PostgreSQL's
  built-in text search features, including:
  - tsvector/tsquery for efficient text search
  - ts_rank for relevance scoring
  - Language-aware stemming
  - Phrase matching support

  ## Usage

  # Ensure tsvector column exists
  :ok = FullText.ensure_tsvector_column("my_index")

      # Search using full-text
      {:ok, results} = FullText.search("my_index", "elixir functional", 10)

  ## Language Support

  By default uses 'english' language configuration. Override with:

      opts = [language: "spanish"]
      {:ok, results} = FullText.search("my_index", "buscar", 10, opts)
  """

  require Logger

  import Ecto.Query

  alias PortfolioIndex.Repo

  @default_language "english"

  @doc """
  Perform full-text search on an index.

  ## Parameters

  - `index_id` - The index identifier (table name)
  - `query_text` - The search query
  - `k` - Number of results to return
  - `opts` - Options:
    - `:language` - Text search language (default: "english")
    - `:phrase` - If true, search for exact phrase
    - `:filter` - Additional metadata filters

  ## Returns

  - `{:ok, results}` - List of matching documents with scores
  - `{:error, reason}` on failure
  """
  @spec search(String.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def search(index_id, query_text, k, opts \\ []) do
    language = sanitize_language(Keyword.get(opts, :language, @default_language))
    phrase = Keyword.get(opts, :phrase, false)
    filter = Keyword.get(opts, :filter)
    content_column = content_column_sql(opts)

    start_time = System.monotonic_time(:millisecond)

    ts_query = build_tsquery(query_text, language, phrase)

    case ensure_tsvector_column(index_id, Keyword.put(opts, :content_column, content_column)) do
      :ok ->
        # Build the query using Ecto fragments for full-text search
        query =
          build_search_query(index_id, ts_query, language, k, filter, content_column)

        case Repo.all(query) do
          results when is_list(results) ->
            documents =
              Enum.map(results, fn result ->
                %{
                  id: result.id,
                  content: result.content,
                  score: result.rank,
                  metadata: result.metadata || %{}
                }
              end)

            duration = System.monotonic_time(:millisecond) - start_time

            emit_telemetry(:search, %{duration_ms: duration, result_count: length(documents)}, %{
              index_id: index_id
            })

            {:ok, documents}

          error ->
            Logger.error("Full-text search failed: #{inspect(error)}")
            {:error, error}
        end

      {:error, reason} ->
        Logger.debug("Full-text search unavailable: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Full-text search error: #{inspect(e)}")
      {:error, inspect(e)}
  end

  @doc """
  Ensure the tsvector column and GIN index exist for an index.

  Creates:
  1. A generated tsvector column from the content
  2. A GIN index for efficient text search

  ## Parameters

  - `index_id` - The index identifier (table name)
  - `opts` - Options:
    - `:language` - Text search language (default: "english")
    - `:content_column` - Column/expression to index (default: "metadata->>'content'")

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec ensure_tsvector_column(String.t(), keyword()) :: :ok | {:error, term()}
  def ensure_tsvector_column(index_id, opts \\ []) do
    language = sanitize_language(Keyword.get(opts, :language, @default_language))
    content_column = content_column_sql(opts)
    table_name = table_name(index_id)

    # Add tsvector column if it doesn't exist
    add_column_sql = """
    ALTER TABLE #{table_name}
    ADD COLUMN IF NOT EXISTS tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('#{language}', COALESCE(#{content_column}, ''))) STORED
    """

    # Create GIN index
    create_index_sql = """
    CREATE INDEX IF NOT EXISTS #{table_name}_tsv_idx ON #{table_name} USING GIN (tsv)
    """

    with {:ok, _} <- Repo.query(add_column_sql),
         {:ok, _} <- Repo.query(create_index_sql) do
      :ok
    else
      {:error, reason} ->
        Logger.debug("Could not create tsvector column: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.debug("Error ensuring tsvector column: #{inspect(e)}")
      {:error, inspect(e)}
  end

  @doc """
  Build an Ecto query for full-text search.

  Returns an Ecto query that can be composed with other queries.
  """
  @spec build_search_query(String.t(), String.t(), String.t(), pos_integer(), map() | nil) ::
          Ecto.Query.t()
  def build_search_query(index_id, ts_query, language, k, filter) do
    build_search_query(index_id, ts_query, language, k, filter, content_column_sql([]))
  end

  @spec build_search_query(
          String.t(),
          String.t(),
          String.t(),
          pos_integer(),
          map() | nil,
          String.t()
        ) ::
          Ecto.Query.t()
  def build_search_query(index_id, ts_query, language, k, filter, content_column) do
    table = table_name(index_id)
    language = sanitize_language(language)

    base_query =
      case {content_column, language} do
        {"content", "simple"} ->
          from(d in table,
            select: %{
              id: d.id,
              content: d.content,
              metadata: d.metadata,
              rank: fragment("ts_rank(tsv, to_tsquery('simple', ?))", ^ts_query)
            },
            where: fragment("tsv @@ to_tsquery('simple', ?)", ^ts_query),
            order_by: [desc: fragment("ts_rank(tsv, to_tsquery('simple', ?))", ^ts_query)],
            limit: ^k
          )

        {"content", _} ->
          from(d in table,
            select: %{
              id: d.id,
              content: d.content,
              metadata: d.metadata,
              rank: fragment("ts_rank(tsv, to_tsquery('english', ?))", ^ts_query)
            },
            where: fragment("tsv @@ to_tsquery('english', ?)", ^ts_query),
            order_by: [desc: fragment("ts_rank(tsv, to_tsquery('english', ?))", ^ts_query)],
            limit: ^k
          )

        {_, "simple"} ->
          from(d in table,
            select: %{
              id: d.id,
              content: fragment("metadata->>'content'"),
              metadata: d.metadata,
              rank: fragment("ts_rank(tsv, to_tsquery('simple', ?))", ^ts_query)
            },
            where: fragment("tsv @@ to_tsquery('simple', ?)", ^ts_query),
            order_by: [desc: fragment("ts_rank(tsv, to_tsquery('simple', ?))", ^ts_query)],
            limit: ^k
          )

        _ ->
          from(d in table,
            select: %{
              id: d.id,
              content: fragment("metadata->>'content'"),
              metadata: d.metadata,
              rank: fragment("ts_rank(tsv, to_tsquery('english', ?))", ^ts_query)
            },
            where: fragment("tsv @@ to_tsquery('english', ?)", ^ts_query),
            order_by: [desc: fragment("ts_rank(tsv, to_tsquery('english', ?))", ^ts_query)],
            limit: ^k
          )
      end

    maybe_add_filter(base_query, filter)
  end

  @doc """
  Build a tsquery string from user input.

  Handles:
  - AND/OR operators
  - Phrase matching
  - Prefix matching

  ## Examples

      build_tsquery("elixir functional", "english", false)
      # => "elixir & functional"

      build_tsquery("exact phrase", "english", true)
      # => "exact <-> phrase"
  """
  @spec build_tsquery(String.t(), String.t(), boolean()) :: String.t()
  def build_tsquery(query_text, _language, true) do
    # Phrase matching: use <-> operator for proximity
    query_text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" <-> ")
  end

  def build_tsquery(query_text, _language, false) do
    # Normal search: AND together all terms
    query_text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join(" & ", &escape_tsquery_term/1)
  end

  # Private functions

  @spec escape_tsquery_term(String.t()) :: String.t()
  defp escape_tsquery_term(term) do
    # Escape special characters in tsquery
    term
    |> String.replace(~r/[&|!():*]/, "")
    |> then(fn t -> if String.ends_with?(t, "*"), do: t, else: t end)
  end

  @spec maybe_add_filter(Ecto.Query.t(), map() | nil) :: Ecto.Query.t()
  defp maybe_add_filter(query, nil), do: query
  defp maybe_add_filter(query, filter) when map_size(filter) == 0, do: query

  defp maybe_add_filter(query, filter) do
    Enum.reduce(filter, query, fn {key, value}, q ->
      from(d in q, where: fragment("metadata->>? = ?", ^to_string(key), ^to_string(value)))
    end)
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :vector_store, :fulltext, event],
      measurements,
      metadata
    )
  end

  defp content_column_sql(opts) do
    case Keyword.get(opts, :content_column) do
      "content" -> "content"
      :content -> "content"
      "metadata->>'content'" -> "metadata->>'content'"
      :metadata_content -> "metadata->>'content'"
      _ -> "metadata->>'content'"
    end
  end

  defp table_name(index_id) do
    safe_id =
      index_id
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.downcase()

    "vectors_#{safe_id}"
  end

  defp sanitize_language(language) when is_binary(language) do
    if Regex.match?(~r/^[a-z_]+$/i, language) do
      String.downcase(language)
    else
      @default_language
    end
  end

  defp sanitize_language(_), do: @default_language
end
