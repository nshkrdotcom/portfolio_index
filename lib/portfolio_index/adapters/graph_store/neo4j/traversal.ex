defmodule PortfolioIndex.Adapters.GraphStore.Neo4j.Traversal do
  @moduledoc """
  Graph traversal algorithms for Neo4j.

  Provides BFS traversal and subgraph extraction capabilities for
  knowledge graph exploration.

  ## Usage

      # BFS from a starting node
      {:ok, nodes} = Traversal.bfs("my_graph", "start_node_id", 3)

      # Get subgraph containing specific nodes
      {:ok, subgraph} = Traversal.get_subgraph("my_graph", ["node1", "node2", "node3"])
  """

  require Logger

  @default_depth 2
  @default_limit 100

  @doc """
  Perform breadth-first traversal from a starting node.

  Explores the graph level by level, returning all nodes reachable
  within the specified depth.

  ## Parameters

  - `graph_id` - The graph identifier
  - `start_node_id` - ID of the starting node
  - `depth` - Maximum traversal depth (default: 2)
  - `opts` - Options:
    - `:direction` - Traversal direction (:outgoing, :incoming, :both) (default: :both)
    - `:edge_types` - Filter by edge types (optional)
    - `:limit` - Maximum nodes to return (default: 100)
    - `:include_edges` - Whether to include edge information (default: false)

  ## Returns

  - `{:ok, nodes}` - List of nodes with depth information
  - `{:error, reason}` on failure
  """
  @spec bfs(String.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def bfs(graph_id, start_node_id, depth \\ @default_depth, opts \\ []) do
    direction = Keyword.get(opts, :direction, :both)
    edge_types = Keyword.get(opts, :edge_types, [])
    limit = Keyword.get(opts, :limit, @default_limit)
    include_edges = Keyword.get(opts, :include_edges, false)

    start_time = System.monotonic_time(:millisecond)

    rel_pattern = build_relationship_pattern(direction, edge_types)

    query =
      if include_edges do
        build_bfs_query_with_edges(rel_pattern, depth)
      else
        build_bfs_query(rel_pattern, depth)
      end

    params = %{
      graph_id: graph_id,
      start_node_id: start_node_id,
      depth: depth,
      limit: limit
    }

    case execute_query(query, params) do
      {:ok, %{results: results}} ->
        nodes = parse_bfs_results(results, include_edges)
        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(
          :bfs,
          %{
            duration_ms: duration,
            result_count: length(nodes),
            depth: depth
          },
          %{graph_id: graph_id}
        )

        {:ok, nodes}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get a subgraph containing all nodes and edges within a set of node IDs.

  Extracts the subgraph formed by the specified nodes and all edges
  between them.

  ## Parameters

  - `graph_id` - The graph identifier
  - `node_ids` - List of node IDs to include
  - `opts` - Options:
    - `:include_internal_edges` - Include edges between nodes (default: true)

  ## Returns

  - `{:ok, %{nodes: [...], edges: [...]}}` - Subgraph with nodes and edges
  """
  @spec get_subgraph(String.t(), [String.t()], keyword()) ::
          {:ok, %{nodes: [map()], edges: [map()]}} | {:error, term()}
  def get_subgraph(graph_id, node_ids, opts \\ []) do
    include_internal_edges = Keyword.get(opts, :include_internal_edges, true)

    start_time = System.monotonic_time(:millisecond)

    # Get all nodes
    nodes_query = """
    MATCH (n {_graph_id: $graph_id})
    WHERE n.id IN $node_ids AND NOT n:_Graph
    RETURN n.id as id, n.name as name, n.type as type, n.description as description,
           labels(n) as labels
    """

    with {:ok, %{results: node_results}} <-
           execute_query(nodes_query, %{graph_id: graph_id, node_ids: node_ids}) do
      nodes =
        Enum.map(node_results, fn record ->
          %{
            id: record["id"],
            name: record["name"],
            type: record["type"],
            description: record["description"],
            labels: (record["labels"] || []) -- ["_Graph"]
          }
        end)

      edges =
        if include_internal_edges and length(node_ids) > 1 do
          case get_internal_edges(graph_id, node_ids) do
            {:ok, e} -> e
            _ -> []
          end
        else
          []
        end

      duration = System.monotonic_time(:millisecond) - start_time

      emit_telemetry(
        :get_subgraph,
        %{
          duration_ms: duration,
          node_count: length(nodes),
          edge_count: length(edges)
        },
        %{graph_id: graph_id}
      )

      {:ok, %{nodes: nodes, edges: edges}}
    end
  end

  @doc """
  Find the shortest path between two nodes.

  ## Parameters

  - `graph_id` - The graph identifier
  - `source_id` - Source node ID
  - `target_id` - Target node ID
  - `opts` - Options:
    - `:max_depth` - Maximum path length (default: 10)
    - `:edge_types` - Filter by edge types (optional)

  ## Returns

  - `{:ok, path}` - Path as list of nodes with edges
  - `{:ok, nil}` - If no path exists
  - `{:error, reason}` on failure
  """
  @spec shortest_path(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, [map()] | nil} | {:error, term()}
  def shortest_path(graph_id, source_id, target_id, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 10)
    edge_types = Keyword.get(opts, :edge_types, [])

    rel_pattern = build_path_relationship_pattern(edge_types, max_depth)

    query = """
    MATCH (source {id: $source_id, _graph_id: $graph_id})
    MATCH (target {id: $target_id, _graph_id: $graph_id})
    MATCH path = shortestPath((source)#{rel_pattern}(target))
    RETURN [n IN nodes(path) | {id: n.id, name: n.name, labels: labels(n)}] as path_nodes,
           [r IN relationships(path) | {type: type(r), from: startNode(r).id, to: endNode(r).id}] as path_edges
    """

    params = %{
      graph_id: graph_id,
      source_id: source_id,
      target_id: target_id
    }

    case execute_query(query, params) do
      {:ok, %{results: [result | _]}} ->
        path_nodes = result["path_nodes"] || []
        path_edges = result["path_edges"] || []

        path =
          path_nodes
          |> Enum.with_index()
          |> Enum.map(fn {node, idx} ->
            edge = Enum.at(path_edges, idx)
            Map.put(node, :edge_to_next, edge)
          end)

        {:ok, path}

      {:ok, %{results: []}} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get N-hop neighbors of a node.

  Similar to BFS but returns only nodes at exactly the specified distance.

  ## Parameters

  - `graph_id` - The graph identifier
  - `node_id` - Starting node ID
  - `hops` - Number of hops (1 = immediate neighbors)
  - `opts` - Same options as `bfs/4`

  ## Returns

  - `{:ok, nodes}` - List of nodes at the specified distance
  """
  @spec n_hop_neighbors(String.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def n_hop_neighbors(graph_id, node_id, hops, opts \\ []) do
    direction = Keyword.get(opts, :direction, :both)
    edge_types = Keyword.get(opts, :edge_types, [])
    limit = Keyword.get(opts, :limit, @default_limit)

    rel_pattern = build_exact_hop_pattern(direction, edge_types, hops)

    query = """
    MATCH (start {id: $node_id, _graph_id: $graph_id})#{rel_pattern}(n)
    WHERE n._graph_id = $graph_id AND NOT n:_Graph
    RETURN DISTINCT n.id as id, n.name as name, n.type as type,
           n.description as description, labels(n) as labels
    LIMIT $limit
    """

    case execute_query(query, %{graph_id: graph_id, node_id: node_id, limit: limit}) do
      {:ok, %{results: results}} ->
        nodes =
          Enum.map(results, fn record ->
            %{
              id: record["id"],
              name: record["name"],
              type: record["type"],
              description: record["description"],
              labels: (record["labels"] || []) -- ["_Graph"],
              distance: hops
            }
          end)

        {:ok, nodes}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  @spec build_bfs_query(String.t(), pos_integer()) :: String.t()
  defp build_bfs_query(rel_pattern, _depth) do
    """
    MATCH (start {id: $start_node_id, _graph_id: $graph_id})
    CALL {
      WITH start
      MATCH path = (start)#{rel_pattern}*(n)
      WHERE length(path) <= $depth AND n._graph_id = $graph_id AND NOT n:_Graph
      RETURN n, length(path) as distance
    }
    RETURN DISTINCT n.id as id, n.name as name, n.type as type,
           n.description as description, labels(n) as labels, distance
    ORDER BY distance
    LIMIT $limit
    """
  end

  @spec build_bfs_query_with_edges(String.t(), pos_integer()) :: String.t()
  defp build_bfs_query_with_edges(rel_pattern, _depth) do
    """
    MATCH (start {id: $start_node_id, _graph_id: $graph_id})
    CALL {
      WITH start
      MATCH path = (start)#{rel_pattern}*(n)
      WHERE length(path) <= $depth AND n._graph_id = $graph_id AND NOT n:_Graph
      RETURN n, length(path) as distance,
             [r IN relationships(path) | {type: type(r), from: startNode(r).id, to: endNode(r).id}] as edges
    }
    RETURN DISTINCT n.id as id, n.name as name, n.type as type,
           n.description as description, labels(n) as labels, distance, edges
    ORDER BY distance
    LIMIT $limit
    """
  end

  @spec parse_bfs_results([map()], boolean()) :: [map()]
  defp parse_bfs_results(results, include_edges) do
    Enum.map(results, fn record ->
      base = %{
        id: record["id"],
        name: record["name"],
        type: record["type"],
        description: record["description"],
        labels: (record["labels"] || []) -- ["_Graph"],
        distance: record["distance"]
      }

      if include_edges do
        Map.put(base, :edges, record["edges"] || [])
      else
        base
      end
    end)
  end

  @spec get_internal_edges(String.t(), [String.t()]) :: {:ok, [map()]} | {:error, term()}
  defp get_internal_edges(graph_id, node_ids) do
    query = """
    MATCH (a {_graph_id: $graph_id})-[r]->(b {_graph_id: $graph_id})
    WHERE a.id IN $node_ids AND b.id IN $node_ids AND NOT a:_Graph AND NOT b:_Graph
    RETURN DISTINCT a.id as source, b.id as target, type(r) as type, r.id as edge_id
    """

    case execute_query(query, %{graph_id: graph_id, node_ids: node_ids}) do
      {:ok, %{results: results}} ->
        edges =
          Enum.map(results, fn record ->
            %{
              id: record["edge_id"],
              source: record["source"],
              target: record["target"],
              type: record["type"]
            }
          end)

        {:ok, edges}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec build_relationship_pattern(atom(), [String.t()]) :: String.t()
  defp build_relationship_pattern(:outgoing, []), do: "-[]->"
  defp build_relationship_pattern(:incoming, []), do: "<-[]-"
  defp build_relationship_pattern(:both, []), do: "-[]-"

  defp build_relationship_pattern(:outgoing, types) do
    "-[:#{Enum.join(types, "|")}]->"
  end

  defp build_relationship_pattern(:incoming, types) do
    "<-[:#{Enum.join(types, "|")}]-"
  end

  defp build_relationship_pattern(:both, types) do
    "-[:#{Enum.join(types, "|")}]-"
  end

  @spec build_path_relationship_pattern([String.t()], pos_integer()) :: String.t()
  defp build_path_relationship_pattern([], max_depth) do
    "-[*1..#{max_depth}]-"
  end

  defp build_path_relationship_pattern(types, max_depth) do
    "-[:#{Enum.join(types, "|")}*1..#{max_depth}]-"
  end

  @spec build_exact_hop_pattern(atom(), [String.t()], pos_integer()) :: String.t()
  defp build_exact_hop_pattern(:outgoing, [], hops), do: "-[*#{hops}]->"
  defp build_exact_hop_pattern(:incoming, [], hops), do: "<-[*#{hops}]-"
  defp build_exact_hop_pattern(:both, [], hops), do: "-[*#{hops}]-"

  defp build_exact_hop_pattern(:outgoing, types, hops) do
    "-[:#{Enum.join(types, "|")}*#{hops}]->"
  end

  defp build_exact_hop_pattern(:incoming, types, hops) do
    "<-[:#{Enum.join(types, "|")}*#{hops}]-"
  end

  defp build_exact_hop_pattern(:both, types, hops) do
    "-[:#{Enum.join(types, "|")}*#{hops}]-"
  end

  @spec execute_query(String.t(), map()) :: {:ok, map()} | {:error, term()}
  defp execute_query(query, params) do
    response = Boltx.query!(Boltx, query, params)
    {:ok, %{results: response.results}}
  rescue
    e in Boltx.Error ->
      Logger.error("Neo4j traversal query failed: #{inspect(e)}")
      {:error, inspect(e)}

    e ->
      Logger.error("Neo4j traversal query failed: #{inspect(e)}")
      {:error, inspect(e)}
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :graph_store, :traversal, event],
      measurements,
      metadata
    )
  end
end
