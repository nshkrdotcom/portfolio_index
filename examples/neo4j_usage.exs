Application.put_env(:portfolio_index, :start_repo, false)
Application.put_env(:portfolio_index, :start_boltx, true)
Mix.Task.run("app.start")

alias PortfolioIndex.Adapters.GraphStore.Neo4j

boltx_config = Application.get_env(:boltx, Boltx, [])

case Process.whereis(Boltx) do
  nil ->
    case Boltx.start_link(boltx_config) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise "Failed to start Boltx: #{inspect(reason)}"
    end

  _pid ->
    :ok
end

graph_id = "example_graph_#{System.unique_integer([:positive])}"

try do
  :ok = Neo4j.create_graph(graph_id, %{})

  {:ok, node1} =
    Neo4j.create_node(graph_id, %{
      labels: ["Concept"],
      properties: %{name: "Elixir", type: "language"}
    })

  {:ok, node2} =
    Neo4j.create_node(graph_id, %{
      labels: ["Concept"],
      properties: %{name: "GenServer", type: "behaviour"}
    })

  {:ok, _edge} =
    Neo4j.create_edge(graph_id, %{
      from_id: node1.id,
      to_id: node2.id,
      type: "HAS_FEATURE",
      properties: %{since: "1.0"}
    })

  {:ok, neighbors} = Neo4j.get_neighbors(graph_id, node1.id, direction: :outgoing)
  IO.inspect(neighbors, label: "Neighbors")
after
  _ = Neo4j.delete_graph(graph_id)
end
