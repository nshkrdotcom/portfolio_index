defmodule PortfolioIndex.Adapters.GraphStore.Neo4j.EntitySearch do
  @moduledoc """
  Vector-based entity search for Neo4j graph store.

  Enables semantic search over entity embeddings stored in Neo4j.
  Requires entities to have an `embedding` property containing a vector.

  ## Usage

      {:ok, entities} = EntitySearch.search_by_vector(
        "my_graph",
        query_embedding,
        10,
        min_similarity: 0.7
      )

  ## Vector Index

  Before using vector search, ensure the index exists:

      :ok = EntitySearch.ensure_vector_index("my_graph", 768)
  """

  require Logger

  @default_k 10
  @default_min_similarity 0.0

  @doc """
  Search entities by vector similarity.

  Uses cosine similarity to find entities with embeddings similar to
  the query vector.

  ## Parameters

  - `graph_id` - The graph identifier
  - `query_vector` - The query embedding vector
  - `k` - Number of results to return (default: 10)
  - `opts` - Options:
    - `:min_similarity` - Minimum similarity threshold (default: 0.0)
    - `:labels` - Filter by entity labels (optional)
    - `:properties` - Filter by property values (optional)

  ## Returns

  - `{:ok, entities}` - List of matching entities with similarity scores
  - `{:error, reason}` on failure
  """
  @spec search_by_vector(String.t(), [float()], pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def search_by_vector(graph_id, query_vector, k \\ @default_k, opts \\ []) do
    min_similarity = Keyword.get(opts, :min_similarity, @default_min_similarity)
    labels = Keyword.get(opts, :labels, [])
    properties = Keyword.get(opts, :properties, %{})

    start_time = System.monotonic_time(:millisecond)

    # Build the query
    label_clause = build_label_clause(labels)
    property_clause = build_property_clause(properties)

    query = """
    MATCH (n#{label_clause} {_graph_id: $graph_id})
    #{property_clause}
    WHERE n.embedding IS NOT NULL
    WITH n, gds.similarity.cosine(n.embedding, $query_vector) AS similarity
    WHERE similarity >= $min_similarity
    RETURN n.id as id, n.name as name, n.type as type, n.description as description,
           labels(n) as labels, similarity
    ORDER BY similarity DESC
    LIMIT $k
    """

    params = %{
      graph_id: graph_id,
      query_vector: query_vector,
      min_similarity: min_similarity,
      k: k
    }

    case execute_query(query, params) do
      {:ok, %{results: results}} ->
        entities =
          Enum.map(results, fn record ->
            %{
              id: record["id"],
              name: record["name"],
              type: record["type"],
              description: record["description"],
              labels: (record["labels"] || []) -- ["_Graph"],
              similarity: record["similarity"]
            }
          end)

        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(
          :search_by_vector,
          %{duration_ms: duration, result_count: length(entities)},
          %{graph_id: graph_id}
        )

        {:ok, entities}

      {:error, _reason} ->
        # Fallback to manual cosine similarity calculation if GDS is not available
        search_by_vector_manual(graph_id, query_vector, k, min_similarity, labels, properties)
    end
  end

  @doc """
  Ensure a vector index exists for entity embeddings.

  Creates a vector index on the embedding property if it doesn't exist.
  Note: This requires Neo4j 5.x+ with vector index support.

  ## Parameters

  - `graph_id` - The graph identifier
  - `dimensions` - The embedding dimensions (e.g., 768, 1536)
  - `opts` - Options:
    - `:similarity_function` - Similarity function (default: "cosine")
    - `:index_name` - Custom index name (default: "entity_embedding_idx")

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec ensure_vector_index(String.t(), pos_integer(), keyword()) :: :ok | {:error, term()}
  def ensure_vector_index(graph_id, dimensions, opts \\ []) do
    similarity_fn = Keyword.get(opts, :similarity_function, "cosine")
    index_name = Keyword.get(opts, :index_name, "entity_embedding_idx_#{graph_id}")

    query = """
    CREATE VECTOR INDEX #{index_name} IF NOT EXISTS
    FOR (n:Entity)
    ON (n.embedding)
    OPTIONS {
      indexConfig: {
        `vector.dimensions`: $dimensions,
        `vector.similarity_function`: $similarity_fn
      }
    }
    """

    case execute_query(query, %{dimensions: dimensions, similarity_fn: similarity_fn}) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Could not create vector index: #{inspect(reason)}. Manual similarity search will be used."
        )

        # Don't fail, just use manual search
        :ok
    end
  end

  # Private functions

  @spec search_by_vector_manual(
          String.t(),
          [float()],
          pos_integer(),
          float(),
          [String.t()],
          map()
        ) ::
          {:ok, [map()]} | {:error, term()}
  defp search_by_vector_manual(graph_id, query_vector, k, min_similarity, labels, properties) do
    label_clause = build_label_clause(labels)
    property_clause = build_property_clause(properties)

    # Get all entities with embeddings
    query = """
    MATCH (n#{label_clause} {_graph_id: $graph_id})
    #{property_clause}
    WHERE n.embedding IS NOT NULL AND NOT n:_Graph
    RETURN n.id as id, n.name as name, n.type as type, n.description as description,
           labels(n) as labels, n.embedding as embedding
    """

    case execute_query(query, %{graph_id: graph_id}) do
      {:ok, %{results: results}} ->
        entities =
          results
          |> Enum.map(fn record ->
            embedding = record["embedding"]
            similarity = if embedding, do: cosine_similarity(query_vector, embedding), else: 0.0

            %{
              id: record["id"],
              name: record["name"],
              type: record["type"],
              description: record["description"],
              labels: (record["labels"] || []) -- ["_Graph"],
              similarity: similarity
            }
          end)
          |> Enum.filter(fn e -> e.similarity >= min_similarity end)
          |> Enum.sort_by(& &1.similarity, :desc)
          |> Enum.take(k)

        {:ok, entities}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec cosine_similarity([float()], [float()]) :: float()
  defp cosine_similarity(vec1, vec2) when length(vec1) == length(vec2) do
    dot = vec1 |> Enum.zip(vec2) |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
    mag1 = :math.sqrt(Enum.reduce(vec1, 0.0, fn x, acc -> acc + x * x end))
    mag2 = :math.sqrt(Enum.reduce(vec2, 0.0, fn x, acc -> acc + x * x end))

    if mag1 == 0 or mag2 == 0, do: 0.0, else: dot / (mag1 * mag2)
  end

  defp cosine_similarity(_vec1, _vec2), do: 0.0

  @spec build_label_clause([String.t()]) :: String.t()
  defp build_label_clause([]), do: ""
  defp build_label_clause(labels), do: ":" <> Enum.join(labels, ":")

  @spec build_property_clause(map()) :: String.t()
  defp build_property_clause(properties) when map_size(properties) == 0, do: ""

  defp build_property_clause(properties) do
    clauses =
      Enum.map_join(properties, " AND ", fn {key, value} ->
        "n.#{key} = '#{value}'"
      end)

    "WHERE #{clauses}"
  end

  @spec execute_query(String.t(), map()) :: {:ok, map()} | {:error, term()}
  defp execute_query(query, params) do
    response = Boltx.query!(Boltx, query, params)
    {:ok, %{results: response.results}}
  rescue
    e in Boltx.Error ->
      Logger.error("Neo4j entity search query failed: #{inspect(e)}")
      {:error, inspect(e)}

    e ->
      Logger.error("Neo4j entity search query failed: #{inspect(e)}")
      {:error, inspect(e)}
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :graph_store, :entity_search, event],
      measurements,
      metadata
    )
  end
end
