Application.put_env(:portfolio_index, :start_boltx, true)
Mix.Task.run("app.start")

alias PortfolioIndex.Adapters.Embedder.Gemini
alias PortfolioIndex.Adapters.GraphStore.Neo4j
alias PortfolioIndex.Adapters.VectorStore.Pgvector
alias PortfolioIndex.RAG.Strategies.GraphRAG

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

index_id = "example_graph_rag_index_#{System.unique_integer([:positive])}"
graph_id = "example_graph_rag_graph_#{System.unique_integer([:positive])}"

try do
  :ok =
    Pgvector.create_index(index_id, %{
      dimensions: 768,
      metric: :cosine,
      index_type: :flat
    })

  :ok = Neo4j.create_graph(graph_id, %{})

  {:ok, elixir_node} =
    Neo4j.create_node(graph_id, %{
      labels: ["Concept"],
      properties: %{name: "Elixir", type: "language"}
    })

  {:ok, genserver_node} =
    Neo4j.create_node(graph_id, %{
      labels: ["Concept"],
      properties: %{name: "GenServer", type: "behaviour"}
    })

  {:ok, _edge} =
    Neo4j.create_edge(graph_id, %{
      from_id: elixir_node.id,
      to_id: genserver_node.id,
      type: "HAS_FEATURE",
      properties: %{since: "1.0"}
    })

  {:ok, %{vector: vector}} = Gemini.embed("Elixir uses GenServer for processes.", [])

  :ok =
    Pgvector.store(index_id, "doc_1", vector, %{
      content: "Elixir uses GenServer for stateful processes.",
      source: "example"
    })

  {:ok, result} =
    GraphRAG.retrieve(
      "How does GenServer relate to Elixir?",
      %{index_id: index_id, graph_id: graph_id},
      k: 3,
      graph_id: graph_id
    )

  IO.inspect(result.items, label: "GraphRAG results")
after
  _ = Pgvector.delete_index(index_id)
  _ = Neo4j.delete_graph(graph_id)
end
