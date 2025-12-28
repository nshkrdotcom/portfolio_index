defmodule PortfolioIndex.Adapters.GraphStore.Neo4j do
  @moduledoc """
  Neo4j graph database adapter using boltx driver.

  Implements the `PortfolioCore.Ports.GraphStore` behaviour.

  ## Multi-Graph Support

  This adapter supports multi-graph isolation using a `_graph_id` property
  on all nodes and edges. Each graph_id represents an isolated namespace.

  ## Connection

  Connection is managed through the boltx connection pool configured
  in the application supervision tree.

  ## Example

      # Create a graph namespace
      Neo4j.create_graph("repo:my-project", %{})

      # Create a node
      Neo4j.create_node("repo:my-project", %{
        id: "func_1",
        labels: ["Function"],
        properties: %{name: "my_function", arity: 2}
      })
  """

  @behaviour PortfolioCore.Ports.GraphStore

  alias PortfolioIndex.Adapters.GraphStore.Neo4j.Traversal

  require Logger

  @impl true
  def create_graph(graph_id, config) do
    # Create a graph metadata node to track the graph
    query = """
    MERGE (g:_Graph {id: $graph_id})
    SET g.created_at = datetime(),
        g.config = $config
    RETURN g
    """

    params = %{graph_id: graph_id, config: Jason.encode!(config)}

    case execute_query(query, params) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_graph(graph_id) do
    # Delete all nodes belonging to this graph
    query = """
    MATCH (n {_graph_id: $graph_id})
    DETACH DELETE n
    """

    with {:ok, _} <- execute_query(query, %{graph_id: graph_id}),
         # Delete the graph metadata node
         {:ok, _} <-
           execute_query(
             "MATCH (g:_Graph {id: $graph_id}) DELETE g",
             %{graph_id: graph_id}
           ) do
      :ok
    end
  end

  @impl true
  def create_node(graph_id, node) do
    start_time = System.monotonic_time(:millisecond)

    labels = build_labels(node[:labels] || node.labels)
    label_clause = if labels == "", do: "", else: ":#{labels}"

    # Generate ID if not provided
    node_id = node[:id] || generate_id()

    query = """
    CREATE (n#{label_clause})
    SET n = $props,
        n.id = $node_id,
        n._graph_id = $graph_id
    RETURN n, labels(n) as labels
    """

    props = node[:properties] || %{}

    params = %{
      props: props,
      node_id: node_id,
      graph_id: graph_id
    }

    case execute_query(query, params) do
      {:ok, %{results: [result | _]}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        emit_telemetry(:create_node, %{duration_ms: duration}, %{graph_id: graph_id})
        {:ok, parse_node(result)}

      {:ok, %{results: []}} ->
        {:error, :creation_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def create_edge(graph_id, edge) do
    start_time = System.monotonic_time(:millisecond)

    edge_type = String.upcase(edge[:type] || edge.type)
    edge_id = edge[:id] || generate_id()

    query = """
    MATCH (a {id: $from_id, _graph_id: $graph_id})
    MATCH (b {id: $to_id, _graph_id: $graph_id})
    CREATE (a)-[r:#{edge_type}]->(b)
    SET r = $props,
        r.id = $edge_id,
        r._graph_id = $graph_id
    RETURN r, type(r) as type
    """

    params = %{
      from_id: edge[:from_id] || edge.from_id,
      to_id: edge[:to_id] || edge.to_id,
      graph_id: graph_id,
      edge_id: edge_id,
      props: edge[:properties] || %{}
    }

    case execute_query(query, params) do
      {:ok, %{results: [result | _]}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        emit_telemetry(:create_edge, %{duration_ms: duration}, %{graph_id: graph_id})
        {:ok, parse_edge(result, edge.from_id, edge.to_id)}

      {:ok, %{results: []}} ->
        {:error, :nodes_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_node(graph_id, node_id) do
    query = """
    MATCH (n {id: $node_id, _graph_id: $graph_id})
    RETURN n, labels(n) as labels
    """

    case execute_query(query, %{node_id: node_id, graph_id: graph_id}) do
      {:ok, %{results: [result | _]}} ->
        {:ok, parse_node(result)}

      {:ok, %{results: []}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_neighbors(graph_id, node_id, opts) do
    direction = Keyword.get(opts, :direction, :both)
    edge_types = Keyword.get(opts, :edge_types, [])
    limit = Keyword.get(opts, :limit, 100)

    rel_pattern = build_relationship_pattern(direction, edge_types)

    query = """
    MATCH (n {id: $node_id, _graph_id: $graph_id})#{rel_pattern}(neighbor)
    WHERE neighbor._graph_id = $graph_id
    RETURN DISTINCT neighbor, labels(neighbor) as labels
    LIMIT $limit
    """

    params = %{node_id: node_id, graph_id: graph_id, limit: limit}

    case execute_query(query, params) do
      {:ok, %{results: results}} ->
        nodes = Enum.map(results, &parse_node/1)
        {:ok, nodes}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def traverse(graph_id, node_id, opts) do
    depth = Keyword.get(opts, :max_depth, 2)

    case Keyword.get(opts, :algorithm, :bfs) do
      :dfs ->
        Traversal.bfs(graph_id, node_id, depth, opts)

      _ ->
        Traversal.bfs(graph_id, node_id, depth, opts)
    end
  end

  @impl true
  def query(graph_id, cypher_query, params) do
    start_time = System.monotonic_time(:millisecond)

    # Add graph_id to params for use in query (both forms for flexibility)
    enhanced_params =
      params
      |> Map.put(:_graph_id, graph_id)
      |> Map.put(:graph_id, graph_id)

    case execute_query(cypher_query, enhanced_params) do
      {:ok, %{results: results}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        emit_telemetry(:query, %{duration_ms: duration}, %{graph_id: graph_id})

        {:ok,
         %{
           nodes: [],
           edges: [],
           records: results
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_node(graph_id, node_id) do
    query = """
    MATCH (n {id: $node_id, _graph_id: $graph_id})
    DETACH DELETE n
    """

    case execute_query(query, %{node_id: node_id, graph_id: graph_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete_edge(graph_id, edge_id) do
    query = """
    MATCH ()-[r {id: $edge_id, _graph_id: $graph_id}]-()
    DELETE r
    """

    case execute_query(query, %{edge_id: edge_id, graph_id: graph_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def graph_stats(graph_id) do
    query = """
    MATCH (n {_graph_id: $graph_id})
    WITH count(n) as node_count
    OPTIONAL MATCH ()-[r {_graph_id: $graph_id}]-()
    RETURN node_count, count(r) / 2 as edge_count
    """

    case execute_query(query, %{graph_id: graph_id}) do
      {:ok, %{results: [%{"node_count" => nodes, "edge_count" => edges} | _]}} ->
        {:ok,
         %{
           node_count: nodes || 0,
           edge_count: edges || 0,
           graph_id: graph_id
         }}

      {:ok, %{results: []}} ->
        {:ok, %{node_count: 0, edge_count: 0, graph_id: graph_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp execute_query(query, params) do
    response = Boltx.query!(Boltx, query, params)
    {:ok, %{results: response.results}}
  rescue
    e in Boltx.Error ->
      Logger.error("Neo4j query failed: #{inspect(e)}")
      {:error, inspect(e)}

    e ->
      Logger.error("Neo4j query failed: #{inspect(e)}")
      {:error, inspect(e)}
  end

  defp build_labels([]), do: ""

  defp build_labels(labels) when is_list(labels) do
    Enum.map_join(labels, ":", &sanitize_label/1)
  end

  defp sanitize_label(label) do
    label
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp build_relationship_pattern(:outgoing, []), do: "-->"
  defp build_relationship_pattern(:incoming, []), do: "<--"
  defp build_relationship_pattern(:both, []), do: "--"

  defp build_relationship_pattern(:outgoing, types) do
    "-[:#{Enum.join(types, "|")}]->"
  end

  defp build_relationship_pattern(:incoming, types) do
    "<-[:#{Enum.join(types, "|")}]-"
  end

  defp build_relationship_pattern(:both, types) do
    "-[:#{Enum.join(types, "|")}]-"
  end

  defp parse_node(%{"n" => %Boltx.Types.Node{properties: props, labels: labels}}) do
    %{
      id: props["id"],
      labels: labels -- ["_Graph"],
      properties: Map.drop(props, ["id", "_graph_id"])
    }
  end

  defp parse_node(%{"n" => node_props, "labels" => labels}) when is_map(node_props) do
    %{
      id: node_props["id"],
      labels: (labels || []) -- ["_Graph"],
      properties: Map.drop(node_props, ["id", "_graph_id"])
    }
  end

  defp parse_node(%{"neighbor" => %Boltx.Types.Node{} = node}) do
    parse_node(%{"n" => node})
  end

  defp parse_node(%{"neighbor" => node_props, "labels" => labels}) do
    parse_node(%{"n" => node_props, "labels" => labels})
  end

  defp parse_node(other) do
    Logger.warning("Unexpected node format: #{inspect(other)}")
    %{id: nil, labels: [], properties: %{}}
  end

  defp parse_edge(
         %{"r" => %Boltx.Types.Relationship{properties: props, type: type}},
         from_id,
         to_id
       ) do
    %{
      id: props["id"],
      type: type,
      from_id: from_id,
      to_id: to_id,
      properties: Map.drop(props, ["id", "_graph_id"])
    }
  end

  defp parse_edge(%{"r" => edge_props, "type" => type}, from_id, to_id) when is_map(edge_props) do
    %{
      id: edge_props["id"],
      type: type,
      from_id: from_id,
      to_id: to_id,
      properties: Map.drop(edge_props, ["id", "_graph_id"])
    }
  end

  defp emit_telemetry(operation, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :graph_store, operation],
      measurements,
      metadata
    )
  end
end
