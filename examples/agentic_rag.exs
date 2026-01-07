Mix.Task.run("app.start")

alias PortfolioIndex.Adapters.Embedder.Gemini
alias PortfolioIndex.Adapters.DocumentStore.Postgres
alias PortfolioIndex.Adapters.VectorStore.Pgvector
alias PortfolioIndex.RAG.Strategies.Agentic

index_id = "example_agentic_#{System.unique_integer([:positive])}"
store_id = "example_agentic_store_#{System.unique_integer([:positive])}"
doc_id = "doc_1"

try do
  :ok =
    Pgvector.create_index(index_id, %{
      dimensions: 768,
      metric: :cosine,
      index_type: :flat
    })

  {:ok, %{vector: vector}} = Gemini.embed("PortfolioIndex provides adapters for RAG.", [])

  :ok =
    Pgvector.store(index_id, doc_id, vector, %{
      content: "PortfolioIndex provides adapters and RAG strategies.",
      source: "example"
    })

  {:ok, _doc} =
    Postgres.store(
      store_id,
      doc_id,
      "PortfolioIndex provides adapters, RAG strategies, and telemetry hooks.",
      %{source: "example"}
    )

  context = %{
    index_id: index_id,
    store_id: store_id,
    adapters: %{
      embedder: Gemini,
      vector_store: Pgvector,
      document_store: Postgres
    }
  }

  {:ok, result} = Agentic.retrieve("What does PortfolioIndex provide?", context, k: 3)
  IO.inspect(result.items, label: "Agentic results")
after
  _ = Postgres.delete(store_id, doc_id)
  _ = Pgvector.delete_index(index_id)
end
