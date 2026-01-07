Mix.Task.run("app.start")

alias PortfolioIndex.Adapters.VectorStore.Pgvector

index_id = "example_index_#{System.unique_integer([:positive])}"
vector = [0.1, 0.2, 0.3]

try do
  :ok =
    Pgvector.create_index(index_id, %{
      dimensions: length(vector),
      metric: :cosine,
      index_type: :flat
    })

  :ok = Pgvector.store(index_id, "doc_1", vector, %{content: "Hello from pgvector"})

  {:ok, results} = Pgvector.search(index_id, vector, 5, [])
  IO.inspect(results, label: "Search results")
after
  _ = Pgvector.delete_index(index_id)
end
