defmodule PortfolioIndex.Adapters.GraphStore.Neo4j.Community do
  @moduledoc """
  Community CRUD operations for Neo4j graph store.

  Manages community nodes and their relationships to entity members.
  Communities are stored as nodes with a `:Community` label and have
  relationships to their member entities.

  ## Structure

  Community nodes have:
  - `id` - Unique identifier
  - `level` - Hierarchical level (0 for base communities)
  - `summary` - LLM-generated summary text
  - `embedding` - Vector embedding of the summary

  ## Example

      # Create a community
      {:ok, community} = Community.create_community("my_graph", %{
        id: "community_0",
        level: 0,
        members: ["entity_1", "entity_2"],
        summary: "This community focuses on...",
        embedding: [0.1, 0.2, ...]
      })

      # Search communities by vector
      {:ok, communities} = Community.search_communities_by_vector(
        "my_graph",
        query_embedding,
        5
      )
  """

  @behaviour PortfolioCore.Ports.GraphStore.Community

  require Logger

  @impl true
  @spec create_community(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_community(graph_id, community_id, opts) do
    name = Keyword.get(opts, :name, community_id)
    level = Keyword.get(opts, :level, 0)
    member_ids = Keyword.get(opts, :member_ids, [])
    summary = Keyword.get(opts, :summary)
    embedding = Keyword.get(opts, :embedding)

    community = %{
      id: community_id,
      name: name,
      level: level,
      members: member_ids,
      summary: summary,
      embedding: embedding
    }

    case create_community(graph_id, community) do
      {:ok, _community} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create a community in the graph.

  ## Parameters

  - `graph_id` - The graph identifier
  - `community` - Community map with:
    - `:id` - Community identifier (required)
    - `:level` - Hierarchical level (default: 0)
    - `:members` - List of member entity IDs (required)
    - `:summary` - Community summary text (optional)
    - `:embedding` - Summary embedding vector (optional)

  ## Returns

  - `{:ok, community}` - Created community
  - `{:error, reason}` on failure
  """
  @spec create_community(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_community(graph_id, community) do
    start_time = System.monotonic_time(:millisecond)

    community_id = community[:id] || community.id
    name = community[:name] || community.name || community_id
    level = community[:level] || 0
    members = community[:members] || []
    summary = community[:summary]
    embedding = community[:embedding]

    # Create community node
    create_query = """
    CREATE (c:Community {
      id: $community_id,
      name: $name,
      _graph_id: $graph_id,
      level: $level,
      summary: $summary,
      embedding: $embedding,
      member_count: $member_count,
      created_at: datetime()
    })
    RETURN c
    """

    params = %{
      community_id: community_id,
      graph_id: graph_id,
      name: name,
      level: level,
      summary: summary,
      embedding: embedding,
      member_count: length(members)
    }

    with {:ok, _} <- execute_query(create_query, params),
         :ok <- create_member_relationships(graph_id, community_id, members) do
      duration = System.monotonic_time(:millisecond) - start_time

      emit_telemetry(
        :create_community,
        %{duration_ms: duration, member_count: length(members)},
        %{graph_id: graph_id}
      )

      {:ok,
       %{
         id: community_id,
         name: name,
         level: level,
         members: members,
         summary: summary,
         embedding: embedding
       }}
    end
  end

  @doc """
  List all communities in a graph.

  ## Options

  - `:level` - Filter by community level
  - `:limit` - Maximum number to return (default: 100)
  - `:offset` - Offset for pagination (default: 0)

  ## Returns

  - `{:ok, communities}` - List of community maps
  """
  @spec list_communities(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @impl true
  def list_communities(graph_id, opts \\ []) do
    level = Keyword.get(opts, :level)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    level_clause = if level, do: "AND c.level = $level", else: ""

    query = """
    MATCH (c:Community {_graph_id: $graph_id})
    #{level_clause}
    RETURN c.id as id, c.name as name, c.level as level, c.summary as summary,
           c.member_count as member_count, c.embedding as embedding
    ORDER BY c.level, c.id
    SKIP $offset
    LIMIT $limit
    """

    params = %{graph_id: graph_id, level: level, offset: offset, limit: limit}

    case execute_query(query, params) do
      {:ok, %{results: results}} ->
        communities =
          Enum.map(results, fn record ->
            %{
              id: record["id"],
              name: record["name"] || record["id"],
              level: record["level"],
              summary: record["summary"],
              member_count: record["member_count"],
              embedding: record["embedding"]
            }
          end)

        {:ok, communities}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get members of a community.

  ## Returns

  - `{:ok, members}` - List of member entity IDs
  """
  @impl true
  @spec get_community_members(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def get_community_members(graph_id, community_id) do
    query = """
    MATCH (c:Community {id: $community_id, _graph_id: $graph_id})-[:HAS_MEMBER]->(m)
    RETURN m.id as id
    """

    case execute_query(query, %{graph_id: graph_id, community_id: community_id}) do
      {:ok, %{results: results}} ->
        members = Enum.map(results, & &1["id"])

        {:ok, members}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search communities by vector similarity on their summary embeddings.

  Used for global search in GraphRAG.

  ## Parameters

  - `graph_id` - The graph identifier
  - `query_vector` - The query embedding
  - `k` - Number of results to return
  - `opts` - Options:
    - `:level` - Filter by community level
    - `:min_similarity` - Minimum similarity threshold

  ## Returns

  - `{:ok, communities}` - List of matching communities with similarity scores
  """
  @spec search_communities_by_vector(String.t(), [float()], pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def search_communities_by_vector(graph_id, query_vector, k, opts \\ []) do
    level = Keyword.get(opts, :level)
    min_similarity = Keyword.get(opts, :min_similarity, 0.0)

    start_time = System.monotonic_time(:millisecond)

    level_clause = if level, do: "AND c.level = $level", else: ""

    # Get communities with embeddings
    query = """
    MATCH (c:Community {_graph_id: $graph_id})
    WHERE c.embedding IS NOT NULL #{level_clause}
    RETURN c.id as id, c.level as level, c.summary as summary,
           c.member_count as member_count, c.embedding as embedding
    """

    case execute_query(query, %{graph_id: graph_id, level: level}) do
      {:ok, %{results: results}} ->
        communities =
          results
          |> Enum.map(fn record ->
            embedding = record["embedding"]
            similarity = if embedding, do: cosine_similarity(query_vector, embedding), else: 0.0

            %{
              id: record["id"],
              level: record["level"],
              summary: record["summary"],
              member_count: record["member_count"],
              similarity: similarity
            }
          end)
          |> Enum.filter(fn c -> c.similarity >= min_similarity end)
          |> Enum.sort_by(& &1.similarity, :desc)
          |> Enum.take(k)

        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(
          :search_communities_by_vector,
          %{duration_ms: duration, result_count: length(communities)},
          %{graph_id: graph_id}
        )

        {:ok, communities}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete a community and its member relationships.

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec delete_community(String.t(), String.t()) :: :ok | {:error, term()}
  def delete_community(graph_id, community_id) do
    query = """
    MATCH (c:Community {id: $community_id, _graph_id: $graph_id})
    DETACH DELETE c
    """

    case execute_query(query, %{graph_id: graph_id, community_id: community_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update a community's summary and embedding.

  ## Returns

  - `{:ok, community}` - Updated community
  - `{:error, reason}` on failure
  """
  @spec update_community_summary(String.t(), String.t(), String.t(), [float()] | nil) ::
          {:ok, map()} | {:error, term()}
  def update_community_summary(graph_id, community_id, summary, embedding) do
    query = """
    MATCH (c:Community {id: $community_id, _graph_id: $graph_id})
    SET c.summary = $summary, c.embedding = $embedding, c.updated_at = datetime()
    RETURN c.id as id, c.name as name, c.level as level, c.summary as summary, c.member_count as member_count
    """

    params = %{
      graph_id: graph_id,
      community_id: community_id,
      summary: summary,
      embedding: embedding
    }

    case execute_query(query, params) do
      {:ok, %{results: [record | _]}} ->
        {:ok,
         %{
           id: record["id"],
           name: record["name"] || record["id"],
           level: record["level"],
           summary: record["summary"],
           member_count: record["member_count"]
         }}

      {:ok, %{results: []}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @spec update_community_summary(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def update_community_summary(graph_id, community_id, summary) do
    case update_community_summary(graph_id, community_id, summary, nil) do
      {:ok, _community} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  @spec create_member_relationships(String.t(), String.t(), [String.t()]) ::
          :ok | {:error, term()}
  defp create_member_relationships(_graph_id, _community_id, []), do: :ok

  defp create_member_relationships(graph_id, community_id, member_ids) do
    query = """
    MATCH (c:Community {id: $community_id, _graph_id: $graph_id})
    UNWIND $member_ids AS member_id
    MATCH (m {id: member_id, _graph_id: $graph_id})
    WHERE NOT m:_Graph AND NOT m:Community
    CREATE (c)-[:HAS_MEMBER]->(m)
    """

    case execute_query(query, %{
           graph_id: graph_id,
           community_id: community_id,
           member_ids: member_ids
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
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

  @spec execute_query(String.t(), map()) :: {:ok, map()} | {:error, term()}
  defp execute_query(query, params) do
    response = Boltx.query!(Boltx, query, params)
    {:ok, %{results: response.results}}
  rescue
    e in Boltx.Error ->
      Logger.error("Neo4j community query failed: #{inspect(e)}")
      {:error, inspect(e)}

    e ->
      Logger.error("Neo4j community query failed: #{inspect(e)}")
      {:error, inspect(e)}
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :graph_store, :community, event],
      measurements,
      metadata
    )
  end
end
