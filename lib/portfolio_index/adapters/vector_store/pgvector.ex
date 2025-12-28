defmodule PortfolioIndex.Adapters.VectorStore.Pgvector do
  @moduledoc """
  PostgreSQL pgvector adapter for vector storage.

  Implements the `PortfolioCore.Ports.VectorStore` behaviour using
  PostgreSQL with the pgvector extension.

  ## Features

  - Dynamic table creation per index
  - IVFFlat and HNSW index support
  - Cosine, Euclidean, and Dot Product distance metrics
  - Batch operations for efficient ingestion
  - Metadata filtering in searches

  ## Index Configuration

      config = %{
        dimensions: 768,
        metric: :cosine,
        index_type: :hnsw,
        options: %{m: 16, ef_construction: 64}
      }

      Pgvector.create_index("my_index", config)
  """

  @behaviour PortfolioCore.Ports.VectorStore

  alias PortfolioIndex.Adapters.VectorStore.Pgvector.FullText
  alias PortfolioIndex.Repo
  require Logger

  @impl true
  def create_index(index_id, config) do
    # Check if index already exists
    case check_index_exists(index_id) do
      {:ok, true} ->
        ensure_existing_index(index_id, config)

      {:ok, false} ->
        do_create_index(index_id, config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_existing_index(index_id, config) do
    table_name = table_name(index_id)
    metric = normalize_metric(config[:metric] || :cosine)

    with :ok <- validate_dimensions(index_id, config),
         :ok <- create_vector_index(table_name, metric, config) do
      register_index(index_id, config)
    end
  end

  defp validate_dimensions(index_id, config) do
    case get_index_config(index_id) do
      {:ok, %{dimensions: dims}} ->
        if dims == config.dimensions do
          :ok
        else
          {:error,
           {:dimension_mismatch, %{index_id: index_id, expected: config.dimensions, actual: dims}}}
        end

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_create_index(index_id, config) do
    table_name = table_name(index_id)
    dimensions = config.dimensions
    metric = config[:metric] || :cosine

    create_table_sql = """
    CREATE TABLE #{table_name} (
      id VARCHAR(255) PRIMARY KEY,
      embedding vector(#{dimensions}),
      metadata JSONB DEFAULT '{}',
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    )
    """

    with {:ok, _} <- Repo.query(create_table_sql),
         :ok <- create_vector_index(table_name, metric, config),
         :ok <- register_index(index_id, config) do
      :ok
    else
      {:error, %Postgrex.Error{postgres: %{code: :duplicate_table}}} ->
        {:error, :already_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_index(index_id) do
    table_name = table_name(index_id)

    with {:ok, _} <- Repo.query("DROP TABLE IF EXISTS #{table_name}"),
         {:ok, _} <-
           Repo.query(
             "DELETE FROM vector_index_registry WHERE index_id = $1",
             [index_id]
           ) do
      :ok
    end
  end

  @impl true
  def store(index_id, id, vector, metadata) do
    start_time = System.monotonic_time(:millisecond)
    table_name = table_name(index_id)
    pgvector = to_pgvector(vector)

    sql = """
    INSERT INTO #{table_name} (id, embedding, metadata)
    VALUES ($1, $2, $3)
    ON CONFLICT (id) DO UPDATE SET
      embedding = EXCLUDED.embedding,
      metadata = EXCLUDED.metadata
    """

    case Repo.query(sql, [id, pgvector, metadata]) do
      {:ok, _} ->
        duration = System.monotonic_time(:millisecond) - start_time
        emit_telemetry(:store, %{duration_ms: duration}, %{index_id: index_id})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def store_batch(index_id, items) do
    start_time = System.monotonic_time(:millisecond)
    table_name = table_name(index_id)

    # Use a single transaction for batch insert
    result =
      Repo.transaction(fn ->
        Enum.each(items, &insert_batch_item(table_name, &1))
        length(items)
      end)

    handle_batch_result(result, start_time, index_id)
  end

  @impl true
  def search(index_id, query_vector, k, opts) do
    case Keyword.get(opts, :mode, :vector) do
      :keyword -> keyword_search(index_id, query_vector, k, opts)
      _ -> vector_search(index_id, query_vector, k, opts)
    end
  end

  @impl true
  def fulltext_search(index_id, query, k, opts) when is_binary(query) do
    fulltext_module = Keyword.get(opts, :fulltext_module, FullText)

    case fulltext_module.search(index_id, query, k, opts) do
      {:ok, results} ->
        {:ok, Enum.map(results, &normalize_fulltext_result/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fulltext_search(_index_id, _query, _k, _opts), do: {:ok, []}

  defp vector_search(index_id, query_vector, k, opts) do
    start_time = System.monotonic_time(:millisecond)
    table_name = table_name(index_id)
    pgvector = to_pgvector(query_vector)
    include_vector = Keyword.get(opts, :include_vector, false)
    filter = Keyword.get(opts, :filter, nil)
    min_score = Keyword.get(opts, :min_score, nil)

    # Get metric for this index to use correct operator
    metric = get_index_metric(index_id)
    distance_op = metric_to_operator(metric)

    select_clause =
      if include_vector do
        "id, metadata, embedding, 1 - (embedding #{distance_op} $1) as score"
      else
        "id, metadata, 1 - (embedding #{distance_op} $1) as score"
      end

    {where_clause, params} = build_filter_clause(filter, 2)

    where_clause =
      if min_score do
        score_filter = "1 - (embedding #{distance_op} $1) >= $#{length(params) + 2}"

        if where_clause == "" do
          " WHERE #{score_filter}"
        else
          "#{where_clause} AND #{score_filter}"
        end
      else
        where_clause
      end

    final_params =
      if min_score do
        [pgvector] ++ params ++ [min_score, k]
      else
        [pgvector] ++ params ++ [k]
      end

    sql = """
    SELECT #{select_clause}
    FROM #{table_name}
    #{where_clause}
    ORDER BY embedding #{distance_op} $1
    LIMIT $#{length(final_params)}
    """

    case Repo.query(sql, final_params) do
      {:ok, %Postgrex.Result{rows: rows, columns: columns}} ->
        results =
          Enum.map(rows, fn row ->
            parse_search_result(row, columns, include_vector)
          end)

        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(:search, %{duration_ms: duration, k: k, results: length(results)}, %{
          index_id: index_id
        })

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp keyword_search(index_id, query, k, opts) when is_binary(query) do
    start_time = System.monotonic_time(:millisecond)
    table_name = table_name(index_id)
    include_vector = Keyword.get(opts, :include_vector, false)
    filter = Keyword.get(opts, :filter, nil)
    query_value = "%" <> query <> "%"

    {where_clause, params} = build_filter_clause(filter, 2)

    keyword_clause = "metadata->>'content' ILIKE $1"

    where_clause =
      if where_clause == "" do
        " WHERE #{keyword_clause}"
      else
        "#{where_clause} AND #{keyword_clause}"
      end

    select_clause =
      if include_vector do
        "id, metadata, embedding, 1.0 as score"
      else
        "id, metadata, 1.0 as score"
      end

    final_params = [query_value] ++ params ++ [k]

    sql = """
    SELECT #{select_clause}
    FROM #{table_name}
    #{where_clause}
    LIMIT $#{length(final_params)}
    """

    case Repo.query(sql, final_params) do
      {:ok, %Postgrex.Result{rows: rows, columns: columns}} ->
        results =
          Enum.map(rows, fn row ->
            parse_search_result(row, columns, include_vector)
          end)

        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(:search, %{duration_ms: duration, k: k, results: length(results)}, %{
          index_id: index_id
        })

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp keyword_search(_index_id, _query, _k, _opts), do: {:ok, []}

  @impl true
  def delete(index_id, id) do
    table_name = table_name(index_id)
    sql = "DELETE FROM #{table_name} WHERE id = $1"

    case Repo.query(sql, [id]) do
      {:ok, %Postgrex.Result{num_rows: 1}} -> :ok
      {:ok, %Postgrex.Result{num_rows: 0}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def index_stats(index_id) do
    table_name = table_name(index_id)

    sql = """
    SELECT
      COUNT(*) as count,
      pg_total_relation_size('#{table_name}'::regclass) as size_bytes
    FROM #{table_name}
    """

    case Repo.query(sql, []) do
      {:ok, %Postgrex.Result{rows: [[count, size]]}} ->
        # Get dimensions and metric from registry
        case get_index_config(index_id) do
          {:ok, config} ->
            {:ok,
             %{
               count: count,
               dimensions: config.dimensions,
               metric: String.to_existing_atom(config.metric),
               size_bytes: size
             }}

          {:error, :not_found} ->
            {:error, :not_found}
        end

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def index_exists?(index_id) do
    case check_index_exists(index_id) do
      {:ok, exists} -> exists
      {:error, _reason} -> false
    end
  end

  defp check_index_exists(index_id) do
    table_name = table_name(index_id)

    sql = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_name = $1
    )
    """

    case Repo.query(sql, [table_name]) do
      {:ok, %Postgrex.Result{rows: [[true]]}} -> {:ok, true}
      {:ok, %Postgrex.Result{rows: [[false]]}} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp table_name(index_id) do
    # Sanitize index_id for use as table name
    safe_id =
      index_id
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.downcase()

    "vectors_#{safe_id}"
  end

  defp to_pgvector(vector) when is_list(vector) do
    Pgvector.new(vector)
  end

  defp to_pgvector(%Pgvector{} = pgvector), do: pgvector

  defp insert_batch_item(table_name, {id, vector, metadata}) do
    pgvector = to_pgvector(vector)

    sql = """
    INSERT INTO #{table_name} (id, embedding, metadata)
    VALUES ($1, $2, $3)
    ON CONFLICT (id) DO UPDATE SET
      embedding = EXCLUDED.embedding,
      metadata = EXCLUDED.metadata
    """

    case Repo.query(sql, [id, pgvector, metadata]) do
      {:ok, _} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp handle_batch_result({:ok, count}, start_time, index_id) do
    duration = System.monotonic_time(:millisecond) - start_time
    emit_telemetry(:store_batch, %{duration_ms: duration, count: count}, %{index_id: index_id})
    {:ok, count}
  end

  defp handle_batch_result({:error, reason}, _start_time, _index_id) do
    {:error, reason}
  end

  defp create_vector_index(table_name, metric, config) do
    metric = normalize_metric(metric)
    index_type = normalize_index_type(config[:index_type] || :ivfflat)
    op_class = metric_to_op_class(metric)
    index_name = "#{table_name}_embedding_idx"

    index_type
    |> build_index_sql(table_name, index_name, op_class, config)
    |> execute_index_sql()
  end

  defp normalize_index_type(value) when is_atom(value), do: value

  defp normalize_index_type(value) when is_binary(value) do
    case String.downcase(value) do
      "ivfflat" -> :ivfflat
      "hnsw" -> :hnsw
      "flat" -> :flat
      _ -> :ivfflat
    end
  end

  defp normalize_index_type(_), do: :ivfflat

  defp normalize_metric(value) when is_atom(value), do: value

  defp normalize_metric(value) when is_binary(value) do
    case String.downcase(value) do
      "cosine" -> :cosine
      "euclidean" -> :euclidean
      "dot_product" -> :dot_product
      "dot-product" -> :dot_product
      "dotproduct" -> :dot_product
      _ -> :cosine
    end
  end

  defp normalize_metric(_), do: :cosine

  defp build_index_sql(:ivfflat, table_name, index_name, op_class, config) do
    lists = get_in(config, [:options, :lists]) || 100

    """
    CREATE INDEX IF NOT EXISTS #{index_name}
    ON #{table_name}
    USING ivfflat (embedding #{op_class})
    WITH (lists = #{lists})
    """
  end

  defp build_index_sql(:hnsw, table_name, index_name, op_class, config) do
    m = get_in(config, [:options, :m]) || 16
    ef_construction = get_in(config, [:options, :ef_construction]) || 64

    """
    CREATE INDEX IF NOT EXISTS #{index_name}
    ON #{table_name}
    USING hnsw (embedding #{op_class})
    WITH (m = #{m}, ef_construction = #{ef_construction})
    """
  end

  defp build_index_sql(:flat, _table_name, _index_name, _op_class, _config) do
    # No index for flat/exact search
    nil
  end

  defp execute_index_sql(nil), do: :ok

  defp execute_index_sql(sql) do
    case Repo.query(sql) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp register_index(index_id, config) do
    sql = """
    INSERT INTO vector_index_registry (index_id, dimensions, metric, index_type, options, inserted_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
    ON CONFLICT (index_id) DO UPDATE SET
      dimensions = EXCLUDED.dimensions,
      metric = EXCLUDED.metric,
      index_type = EXCLUDED.index_type,
      options = EXCLUDED.options,
      updated_at = NOW()
    """

    params = [
      index_id,
      config.dimensions,
      to_string(config[:metric] || :cosine),
      to_string(config[:index_type] || :ivfflat),
      config[:options] || %{}
    ]

    case Repo.query(sql, params) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_index_config(index_id) do
    sql =
      "SELECT dimensions, metric, index_type, options FROM vector_index_registry WHERE index_id = $1"

    case Repo.query(sql, [index_id]) do
      {:ok, %Postgrex.Result{rows: [[dims, metric, index_type, options]]}} ->
        {:ok,
         %{
           dimensions: dims,
           metric: metric,
           index_type: index_type,
           options: options
         }}

      {:ok, %Postgrex.Result{rows: []}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_index_metric(index_id) do
    case get_index_config(index_id) do
      {:ok, %{metric: metric}} -> String.to_existing_atom(metric)
      _ -> :cosine
    end
  end

  defp metric_to_op_class(:cosine), do: "vector_cosine_ops"
  defp metric_to_op_class(:euclidean), do: "vector_l2_ops"
  defp metric_to_op_class(:dot_product), do: "vector_ip_ops"

  defp metric_to_operator(:cosine), do: "<=>"
  defp metric_to_operator(:euclidean), do: "<->"
  defp metric_to_operator(:dot_product), do: "<#>"

  defp build_filter_clause(nil, _start_param), do: {"", []}

  defp build_filter_clause(filter, _start_param) when is_map(filter) and map_size(filter) == 0 do
    {"", []}
  end

  defp build_filter_clause(filter, start_param) when is_map(filter) do
    {clauses, params, _} =
      Enum.reduce(filter, {[], [], start_param}, fn {key, value}, {clauses, params, idx} ->
        clause = "metadata->>$#{idx} = $#{idx + 1}"
        {[clause | clauses], params ++ [to_string(key), to_string(value)], idx + 2}
      end)

    where = " WHERE " <> Enum.join(Enum.reverse(clauses), " AND ")
    {where, params}
  end

  defp parse_search_result(row, columns, include_vector) do
    map = Enum.zip(columns, row) |> Map.new()

    result = %{
      id: map["id"],
      score: map["score"],
      metadata: map["metadata"] || %{}
    }

    if include_vector do
      Map.put(result, :vector, parse_vector(map["embedding"]))
    else
      Map.put(result, :vector, nil)
    end
  end

  defp parse_vector(nil), do: nil
  defp parse_vector(%Pgvector{} = vec), do: Pgvector.to_list(vec)
  defp parse_vector(vec) when is_struct(vec), do: Pgvector.to_list(vec)

  defp parse_vector(str) when is_binary(str) do
    str
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&String.to_float/1)
  end

  defp normalize_fulltext_result(result) do
    id = result[:id] || result["id"]
    score = result[:score] || result["score"] || 0.0
    metadata = result[:metadata] || result["metadata"] || %{}
    content = result[:content] || result["content"]

    metadata =
      if is_nil(content) do
        metadata
      else
        metadata
        |> Map.put_new("content", content)
        |> Map.put_new(:content, content)
      end

    %{
      id: id,
      score: score,
      metadata: metadata,
      vector: nil
    }
  end

  defp emit_telemetry(operation, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :vector_store, operation],
      measurements,
      metadata
    )
  end
end
