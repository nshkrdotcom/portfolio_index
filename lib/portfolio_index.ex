defmodule PortfolioIndex do
  @moduledoc """
  Production adapters and pipelines for PortfolioCore.

  Portfolio Index implements the port specifications defined in Portfolio Core,
  providing concrete adapters for vector stores, graph databases, embedding
  providers, and LLMs, along with Broadway-based ingestion pipelines and
  advanced RAG strategies.

  ## Adapters

  - Vector Stores: `PortfolioIndex.Adapters.VectorStore.Pgvector`
    (hybrid fulltext via `PortfolioIndex.Adapters.VectorStore.Pgvector.Hybrid`)
  - Graph Stores: `PortfolioIndex.Adapters.GraphStore.Neo4j`
    (community ops via `PortfolioIndex.Adapters.GraphStore.Neo4j.Community`)
  - Embedders: `PortfolioIndex.Adapters.Embedder.Gemini`,
    `PortfolioIndex.Adapters.Embedder.OpenAI`,
    `PortfolioIndex.Adapters.Embedder.Ollama`,
    `PortfolioIndex.Adapters.Embedder.Bumblebee`
  - LLMs: `PortfolioIndex.Adapters.LLM.Gemini`, `PortfolioIndex.Adapters.LLM.Anthropic`,
    `PortfolioIndex.Adapters.LLM.OpenAI`, `PortfolioIndex.Adapters.LLM.Codex`,
    `PortfolioIndex.Adapters.LLM.Ollama`, `PortfolioIndex.Adapters.LLM.VLLM`
  - Chunkers: `PortfolioIndex.Adapters.Chunker.Recursive`
  - Document Stores: `PortfolioIndex.Adapters.DocumentStore.Postgres`

  ## Pipelines

  - `PortfolioIndex.Pipelines.Ingestion` - Document ingestion with chunking
  - `PortfolioIndex.Pipelines.Embedding` - Rate-limited embedding generation

  ## RAG Strategies

  - `PortfolioIndex.RAG.Strategies.Hybrid` - Vector + keyword with RRF
  - `PortfolioIndex.RAG.Strategies.SelfRAG` - Self-critique and refinement
  - `PortfolioIndex.RAG.Strategies.GraphRAG` - Graph-aware retrieval
  - `PortfolioIndex.RAG.Strategies.Agentic` - Tool-based iterative retrieval

  ## Quick Start

      # Start ingestion pipeline
      {:ok, _pid} = PortfolioIndex.Pipelines.Ingestion.start(
        paths: ["/path/to/docs"],
        patterns: ["**/*.md"],
        index_id: "my_index"
      )

      # Start embedding pipeline
      {:ok, _pid} = PortfolioIndex.Pipelines.Embedding.start(
        index_id: "my_index"
      )

      # RAG query
      {:ok, result} = PortfolioIndex.RAG.Strategies.Hybrid.retrieve(
        "What is Elixir?",
        %{index_id: "my_index"},
        [k: 5]
      )
  """

  @doc """
  Returns the version of PortfolioIndex.
  """
  def version do
    Application.spec(:portfolio_index, :vsn) |> to_string()
  end

  @doc """
  Get the configured adapter for a port.

  ## Examples

      PortfolioIndex.adapter(:vector_store)
      # => PortfolioIndex.Adapters.VectorStore.Pgvector

      PortfolioIndex.adapter(:embedder)
      # => PortfolioIndex.Adapters.Embedder.Gemini
  """
  def adapter(:vector_store) do
    Application.get_env(
      :portfolio_index,
      :vector_store,
      PortfolioIndex.Adapters.VectorStore.Pgvector
    )
  end

  def adapter(:graph_store) do
    Application.get_env(:portfolio_index, :graph_store, PortfolioIndex.Adapters.GraphStore.Neo4j)
  end

  def adapter(:embedder) do
    Application.get_env(:portfolio_index, :embedder, PortfolioIndex.Adapters.Embedder.Gemini)
  end

  def adapter(:llm) do
    Application.get_env(:portfolio_index, :llm, PortfolioIndex.Adapters.LLM.Gemini)
  end

  def adapter(:chunker) do
    Application.get_env(:portfolio_index, :chunker, PortfolioIndex.Adapters.Chunker.Recursive)
  end

  def adapter(:document_store) do
    Application.get_env(
      :portfolio_index,
      :document_store,
      PortfolioIndex.Adapters.DocumentStore.Postgres
    )
  end

  @doc """
  Check if all required services are healthy.

  Returns a map with the health status of each component.
  """
  def health_check do
    %{
      repo: check_repo(),
      neo4j: check_neo4j(),
      status: :ok
    }
  end

  defp check_repo do
    case PortfolioIndex.Repo.query("SELECT 1") do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  rescue
    _ -> :error
  end

  defp check_neo4j do
    _ = Boltx.query!(Boltx, "RETURN 1")
    :ok
  rescue
    _ -> :error
  end
end
