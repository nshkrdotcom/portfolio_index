# Getting Started

This guide walks you through setting up PortfolioIndex and running your first
vector search, RAG query, and document ingestion pipeline.

## Prerequisites

PortfolioIndex requires:

- **Elixir** 1.15+
- **PostgreSQL** 16+ with the [pgvector](https://github.com/pgvector/pgvector) extension
- **Neo4j** (optional, for GraphRAG features)
- At least one embedding/LLM provider API key (Gemini, OpenAI, Anthropic, or a local Ollama server)

### Install PostgreSQL + pgvector

```bash
# Ubuntu / WSL
sudo apt install postgresql postgresql-contrib libpq-dev postgresql-16-pgvector

createdb portfolio_index_dev
psql -d portfolio_index_dev -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### Install Neo4j (optional)

```bash
curl -fsSL https://debian.neo4j.com/neotechnology.gpg.key | \
  sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/neo4j.gpg
echo "deb https://debian.neo4j.com stable latest" | \
  sudo tee /etc/apt/sources.list.d/neo4j.list
sudo apt update && sudo apt install neo4j
sudo systemctl enable neo4j && sudo systemctl start neo4j
sudo neo4j-admin dbms set-initial-password password
```

## Installation

Add `portfolio_index` to your `mix.exs`:

```elixir
def deps do
  [
    {:portfolio_index, "~> 0.5.0"}
  ]
end
```

Then fetch dependencies and set up the database:

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
```

Or use the install task for guided setup:

```bash
mix portfolio.install
```

This generates the required migrations and prints configuration instructions.

## First Vector Search

```elixir
alias PortfolioIndex.Adapters.VectorStore.Pgvector
alias PortfolioIndex.Adapters.Embedder.Gemini

# Create an index
:ok = Pgvector.create_index("my_docs", %{dimensions: 768, metric: :cosine})

# Embed and store a document
{:ok, %{vector: vec}} = Gemini.embed("Elixir is a functional programming language.")
:ok = Pgvector.store("my_docs", "doc_1", vec, %{content: "Elixir is a functional programming language."})

# Search
{:ok, %{vector: query_vec}} = Gemini.embed("What is Elixir?")
{:ok, results} = Pgvector.search("my_docs", query_vec, 5, [])
IO.inspect(results, label: "Search results")
```

## First RAG Query

```elixir
alias PortfolioIndex.RAG.Strategies.Hybrid

{:ok, result} = Hybrid.retrieve(
  "How does pattern matching work?",
  %{index_id: "my_docs"},
  k: 10
)

IO.inspect(result.items, label: "Retrieved documents")
```

## First Broadway Pipeline

```elixir
# Ingest documents from a directory
{:ok, _pid} = PortfolioIndex.Pipelines.Ingestion.start(
  paths: ["/path/to/docs"],
  patterns: ["**/*.md"],
  index_id: "my_docs",
  chunk_size: 1000,
  chunk_overlap: 200
)

# Embed the ingested chunks
{:ok, _pid} = PortfolioIndex.Pipelines.Embedding.start(
  index_id: "my_docs",
  batch_size: 50
)
```

## Environment Variables

Set your provider API keys:

```bash
export GEMINI_API_KEY="your-key"
export OPENAI_API_KEY="your-key"      # for OpenAI embeddings/LLM
export ANTHROPIC_API_KEY="your-key"   # for Claude LLM
```

See the [Configuration guide](configuration.md) for full details.

## Next Steps

- [Vector Stores](vector-stores.md) -- pgvector setup, indexing, and search
- [Embedders](embedders.md) -- embedding providers and configuration
- [LLM Adapters](llm-adapters.md) -- all supported LLM providers
- [RAG Strategies](rag-strategies.md) -- Hybrid, Self-RAG, GraphRAG, Agentic
- [Pipelines](pipelines.md) -- Broadway ingestion and embedding
