Mix.Task.run("app.start")

alias PortfolioIndex.Adapters.Embedder.Gemini
alias PortfolioIndex.Adapters.VectorStore.Pgvector
alias PortfolioIndex.RAG.Strategies.Hybrid

index_id = "example_hybrid_#{System.unique_integer([:positive])}"

try do
  :ok =
    Pgvector.create_index(index_id, %{
      dimensions: 768,
      metric: :cosine,
      index_type: :flat
    })

  {:ok, %{vector: vector1}} = Gemini.embed("Elixir is a functional language on the BEAM VM.", [])
  {:ok, %{vector: vector2}} = Gemini.embed("BEAM is the Erlang VM for concurrency.", [])

  :ok =
    Pgvector.store(index_id, "doc_1", vector1, %{
      content: "Elixir is a functional language that runs on the BEAM VM.",
      source: "example"
    })

  :ok =
    Pgvector.store(index_id, "doc_2", vector2, %{
      content: "BEAM is the Erlang VM used for lightweight concurrency.",
      source: "example"
    })

  {:ok, result} = Hybrid.retrieve("BEAM VM", %{index_id: index_id}, k: 3)
  IO.inspect(result.items, label: "Hybrid results")
after
  _ = Pgvector.delete_index(index_id)
end
