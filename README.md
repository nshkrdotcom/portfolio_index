# Portfolio Index

<p align="center">
  <img src="assets/portfolio_index.svg" alt="Portfolio Index Logo" width="200">
</p>

<p align="center">
  <a href="https://hex.pm/packages/portfolio_index"><img alt="Hex.pm" src="https://img.shields.io/hexpm/v/portfolio_index.svg"></a>
  <a href="https://hexdocs.pm/portfolio_index"><img alt="Documentation" src="https://img.shields.io/badge/docs-hexdocs-purple.svg"></a>
  <a href="https://github.com/nshkrdotcom/portfolio_index/actions"><img alt="Build Status" src="https://img.shields.io/github/actions/workflow/status/nshkrdotcom/portfolio_index/ci.yml"></a>
  <a href="https://opensource.org/licenses/MIT"><img alt="License" src="https://img.shields.io/hexpm/l/portfolio_index.svg"></a>
</p>

**Production adapters and pipelines for the PortfolioCore hexagonal architecture. Vector stores, graph databases, embedders, Broadway pipelines, and advanced RAG strategies.**

---

## Overview

Portfolio Index implements the port specifications defined in [Portfolio Core](https://github.com/nshkrdotcom/portfolio_core), providing:

- **Vector Store Adapters** - pgvector (PostgreSQL + fulltext hybrid)
- **Graph Store Adapters** - Neo4j via boltx + community operations
- **Embedding Providers** - Google Gemini
- **LLM Providers** - Google Gemini, Anthropic Claude, OpenAI (openai_ex), Codex (codex_sdk),
  Ollama, vLLM (SnakeBridge)
- **Broadway Pipelines** - Ingestion and embedding with backpressure
- **RAG Strategies** - Hybrid (RRF fusion), Self-RAG (self-critique), GraphRAG, Agentic

## Prerequisites

### PostgreSQL with pgvector

```bash
# Ubuntu/WSL
sudo apt install postgresql postgresql-contrib libpq-dev postgresql-16-pgvector

# Create database
createdb portfolio_index_dev
```

### Neo4j

```bash
# Install via apt (Ubuntu/WSL)
curl -fsSL https://debian.neo4j.com/neotechnology.gpg.key | \
  sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/neo4j.gpg
echo "deb https://debian.neo4j.com stable latest" | \
  sudo tee /etc/apt/sources.list.d/neo4j.list
sudo apt update && sudo apt install neo4j

# Start service
sudo systemctl enable neo4j && sudo systemctl start neo4j

# Set password
sudo neo4j-admin dbms set-initial-password password
```

**Access Points:**

| Service       | URL                     | Credentials        |
|---------------|-------------------------|--------------------|
| Neo4j Browser | http://localhost:7474   | neo4j / password   |
| Bolt endpoint | bolt://localhost:7687   | neo4j / password   |

### Gemini API Key

```bash
export GEMINI_API_KEY="your-api-key"
```

## Installation

Add `portfolio_index` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:portfolio_index, "~> 0.4.0"}
  ]
end
```

Then run:

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
```

## Quick Start

### Vector Search

```elixir
alias PortfolioIndex.Adapters.VectorStore.Pgvector
alias PortfolioIndex.Adapters.Embedder.Gemini

# Create index
:ok = Pgvector.create_index("docs", %{dimensions: 768, metric: :cosine})

# Generate embedding and store
{:ok, %{vector: vec}} = Gemini.embed("Hello, world!")
:ok = Pgvector.store("docs", "doc_1", vec, %{content: "Hello, world!"})

# Search
{:ok, results} = Pgvector.search("docs", query_vector, 10, [])
```

### Graph Operations

```elixir
alias PortfolioIndex.Adapters.GraphStore.Neo4j

# Create a graph namespace
:ok = Neo4j.create_graph("knowledge", %{})

# Create nodes
{:ok, node1} = Neo4j.create_node("knowledge", %{
  labels: ["Concept"],
  properties: %{name: "Elixir", type: "language"}
})

{:ok, node2} = Neo4j.create_node("knowledge", %{
  labels: ["Concept"],
  properties: %{name: "GenServer", type: "behaviour"}
})

# Create relationship
{:ok, _edge} = Neo4j.create_edge("knowledge", %{
  from_id: node1.id,
  to_id: node2.id,
  type: "HAS_FEATURE",
  properties: %{since: "1.0"}
})

# Query neighbors
{:ok, neighbors} = Neo4j.get_neighbors("knowledge", node1.id, direction: :outgoing)
```

### RAG Query

```elixir
alias PortfolioIndex.RAG.Strategies.Hybrid

{:ok, result} = Hybrid.retrieve(
  "How does authentication work?",
  %{index_id: "docs"},
  k: 10
)

# result.items contains ranked results
# result.timing_ms contains query duration
```

### Self-RAG with Critique

```elixir
alias PortfolioIndex.RAG.Strategies.SelfRAG

{:ok, result} = SelfRAG.retrieve(
  "What is GenServer?",
  %{index_id: "docs"},
  k: 5, min_critique_score: 3
)

# result.answer contains the generated answer
# result.critique contains relevance/support/completeness scores
```

### Broadway Pipeline

```elixir
# Start ingestion pipeline
{:ok, _} = PortfolioIndex.Pipelines.Ingestion.start(
  paths: ["/path/to/docs"],
  patterns: ["**/*.md", "**/*.ex"],
  index_id: "my_index",
  chunk_size: 1000,
  chunk_overlap: 200
)

# Start embedding pipeline
{:ok, _} = PortfolioIndex.Pipelines.Embedding.start(
  index_id: "my_index",
  rate_limit: 100,
  batch_size: 50
)
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection URL | - |
| `NEO4J_URI` | Neo4j Bolt URI | `bolt://localhost:7687` |
| `NEO4J_USER` | Neo4j username | `neo4j` |
| `NEO4J_PASSWORD` | Neo4j password | - |
| `GEMINI_API_KEY` | Google Gemini API key | - |
| `OPENAI_API_KEY` | OpenAI API key (OpenAI + Codex) | - |
| `OPENAI_ORGANIZATION` | OpenAI organization ID (optional) | - |
| `ANTHROPIC_API_KEY` | Anthropic API key | - |
| `CODEX_API_KEY` | Codex SDK API key (optional) | - |
| `OLLAMA_HOST` | Ollama host URL | `http://localhost:11434` |
| `OLLAMA_BASE_URL` | Ollama base URL (override) | `http://localhost:11434/api` |
| `OLLAMA_API_KEY` | Ollama API key (optional) | - |
| `HF_TOKEN` | HuggingFace token (gated models) | - |

### Local Model Setup

Ollama examples require a running Ollama server and these models:

- `llama3.2` (LLM)
- `nomic-embed-text` (embeddings)

Install them with:

```bash
ollama pull llama3.2
ollama pull nomic-embed-text
```

Or run:

```bash
mix run examples/ollama_setup.exs
```

vLLM uses the `vllm` Elixir library (SnakeBridge) and requires a CUDA-capable GPU.

```bash
mix deps.get
mix snakebridge.setup
```

### Config Files

```elixir
# config/dev.exs
config :portfolio_index, PortfolioIndex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "portfolio_index_dev"

config :boltx, Boltx,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  pool_size: 10
```

## Adapters

### Vector Store

| Adapter | Backend | Features |
|---------|---------|----------|
| `Pgvector` | PostgreSQL + pgvector | IVFFlat, HNSW indexes, cosine/euclidean/dot_product |

### Graph Store

| Adapter | Backend | Features |
|---------|---------|----------|
| `Neo4j` | Neo4j via boltx | Multi-graph isolation, Cypher queries |

### Embedders

- **Gemini** - Google Gemini text-embedding-004
- **OpenAI** - text-embedding-3-small/large
- **Ollama** - Local embeddings via ollixir

| Adapter | Provider | Model |
|---------|----------|-------|
| `Gemini` | Google | text-embedding-004 (768 dims) |
| `OpenAI` | OpenAI | text-embedding-3-small/large |
| `Ollama` | Ollama | nomic-embed-text (default) |

### LLMs

- **Gemini** - gemini-flash-lite-latest with streaming
- **Anthropic** - Claude via claude_agent_sdk
- **OpenAI** - GPT-4o-mini (low-cost default) via openai_ex
- **Codex** - OpenAI Codex SDK with agentic support
- **Ollama** - Local models via ollixir
- **vLLM** - Local GPU inference via vllm (SnakeBridge)

| Adapter | Provider | Model |
|---------|----------|-------|
| `Gemini` | Google | gemini-flash-lite-latest |
| `Anthropic` | Anthropic | Claude (SDK default) |
| `OpenAI` | OpenAI | gpt-4o-mini (default) |
| `Codex` | OpenAI | Codex SDK default |
| `Ollama` | Ollama | llama3.2 (default) |
| `VLLM` | vLLM | Qwen/Qwen2-0.5B-Instruct (default) |

### Chunker

| Adapter | Strategy | Features |
|---------|----------|----------|
| `Recursive` | Recursive text splitting | Format-aware for 17+ languages |
| `Character` | Character-based | Boundary modes: word, sentence, none |
| `Sentence` | Sentence-based | NLP tokenization, abbreviation handling |
| `Paragraph` | Paragraph-based | Intelligent merge/split at boundaries |
| `Semantic` | Embedding similarity | Groups by semantic coherence |

#### Supported Formats

| Category | Formats |
|----------|---------|
| Languages | Elixir, Ruby, PHP, Python, JavaScript, TypeScript, Vue |
| Markup | Markdown, HTML, LaTeX |
| Documents | doc, docx, epub, odt, pdf, rtf |

#### Token-Based Chunking

All chunkers support custom size measurement via `:get_chunk_size`:

```elixir
# Character-based (default)
Recursive.chunk(text, :elixir, %{chunk_size: 1000})

# Token-based (for LLM context limits)
Recursive.chunk(text, :elixir, %{
  chunk_size: 256,
  get_chunk_size: &MyTokenizer.count_tokens/1
})

# Byte-based (for storage limits)
Recursive.chunk(text, :plain, %{
  chunk_size: 4096,
  get_chunk_size: &byte_size/1
})
```

## RAG Strategies

- **Hybrid** - Vector + keyword search with Reciprocal Rank Fusion
- **SelfRAG** - Retrieval with self-critique and answer refinement
- **GraphRAG** - Graph-aware retrieval
- **Agentic** - Tool-based iterative retrieval

| Strategy | Description |
|----------|-------------|
| `Hybrid` | Vector + keyword search with Reciprocal Rank Fusion |
| `SelfRAG` | Retrieval with self-critique and answer refinement |
| `Agentic` | Tool-based iterative retrieval |
| `GraphRAG` | Graph-aware retrieval with vector fusion |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Portfolio Index                          │
├─────────────────────────────────────────────────────────────┤
│  Adapters                                                   │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐      │
│  │ Vector Store  │ │ Graph Store   │ │   Embedder    │      │
│  │ • Pgvector    │ │ • Neo4j       │ │ • Gemini      │      │
│  │               │ │               │ │ • OpenAI      │      │
│  └───────────────┘ └───────────────┘ └───────────────┘      │
│  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐      │
│  │     LLM       │ │   Chunker     │ │ Document Store│      │
│  │ • Gemini      │ │ • Recursive   │ │ • Postgres    │      │
│  │ • Anthropic   │ │               │ │               │      │
│  │ • OpenAI      │ │               │ │               │      │
│  │ • Codex       │ │               │ │               │      │
│  │ • Ollama      │ │               │ │               │      │
│  │ • vLLM        │ │               │ │               │      │
│  └───────────────┘ └───────────────┘ └───────────────┘      │
├─────────────────────────────────────────────────────────────┤
│  Pipelines (Broadway)                                       │
│  ┌───────────────────────────┐ ┌───────────────────────────┐│
│  │        Ingestion          │ │        Embedding          ││
│  │ FileProducer → Chunker    │ │ ETSProducer → VectorStore ││
│  └───────────────────────────┘ └───────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  RAG Strategies                                             │
│  ┌────────────────────┐ ┌────────────────────┐              │
│  │       Hybrid       │ │      Self-RAG      │              │
│  │ Vector + RRF fusion│ │ Critique + Refine  │              │
│  └────────────────────┘ └────────────────────┘              │
│  ┌────────────────────┐ ┌────────────────────┐              │
│  │      Agentic       │ │      GraphRAG      │              │
│  │   (placeholder)    │ │   (placeholder)    │              │
│  └────────────────────┘ └────────────────────┘              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Portfolio Core                          │
│              (Port Specifications & Registry)               │
└─────────────────────────────────────────────────────────────┘
```

## Testing

```bash
# Run unit tests (mocked adapters)
mix test

# Run integration tests (requires running services)
mix test --include integration

# Run only Neo4j integration tests
mix test test/adapters/graph_store/neo4j_test.exs --include integration

# Run only Pgvector integration tests
mix test test/adapters/vector_store/pgvector_test.exs --include integration
```

### Test Structure

The test suite separates **unit tests** (mocked, fast) from **integration tests** (live services):

| Test Type | Tag | Services Required | Run Command |
|-----------|-----|-------------------|-------------|
| Unit | (default) | None | `mix test` |
| Integration | `@tag :integration` | Neo4j, PostgreSQL | `mix test --include integration` |

Integration tests are **excluded by default** in `test/test_helper.exs`:

```elixir
ExUnit.start(exclude: [:integration, :skip])
```

### Test Fixtures

`test/support/fixtures.ex` provides test data generators:

```elixir
alias PortfolioIndex.Fixtures

# Vector fixtures
Fixtures.random_vector(768)              # Random 768-dim vector
Fixtures.random_normalized_vector(768)   # Normalized (unit length)

# Graph fixtures
Fixtures.sample_node("node_1")           # %{id, labels, properties}
Fixtures.sample_edge("from", "to")       # %{id, type, from_id, to_id, properties}
Fixtures.sample_graph(5)                 # %{nodes: [...], edges: [...]}

# Document fixtures
Fixtures.sample_document()               # Sample markdown content
Fixtures.sample_code()                   # Sample Elixir code
Fixtures.sample_chunks(content, 3)       # Split content into chunks
```

## Neo4j Details

### Schema Management

Unlike SQL databases, Neo4j doesn't use traditional migrations. Instead, `PortfolioIndex.Adapters.GraphStore.Neo4j.Schema` provides schema management:

```elixir
alias PortfolioIndex.Adapters.GraphStore.Neo4j.Schema

# Setup all constraints and indexes
Schema.setup!()

# Check current schema version
Schema.version()
#=> 1

# Run migrations up to a specific version
Schema.migrate!(2)

# Reset database (DANGEROUS - testing only)
Schema.reset!()

# Clean a specific graph namespace
Schema.clean_graph!("my_graph")
```

### Schema Versioning

Schema versions are tracked in a `:SchemaVersion` node:

```cypher
(:SchemaVersion {id: 'current', version: 1, updated_at: datetime()})
```

Each migration is idempotent and can be re-run safely.

### Constraints and Indexes

The schema setup creates:

| Type | Name | Description |
|------|------|-------------|
| Constraint | `node_id_unique` | Unique node IDs within a graph |
| Constraint | `edge_id_unique` | Unique edge IDs within a graph |
| Index | `idx_node_graph_id` | Fast graph isolation queries |
| Index | `idx_node_labels` | Label-based queries |
| Index | `idx_fulltext_content` | Full-text search on content/name/title |

### Multi-Graph Isolation

All nodes and edges include a `_graph_id` property for namespace isolation:

```elixir
# Each graph is isolated by its graph_id
Neo4j.create_graph("project_a", %{})
Neo4j.create_graph("project_b", %{})

# Nodes in different graphs don't interfere
Neo4j.create_node("project_a", %{labels: ["File"], properties: %{path: "/app.ex"}})
Neo4j.create_node("project_b", %{labels: ["File"], properties: %{path: "/app.ex"}})

# Queries are scoped to a graph
Neo4j.get_neighbors("project_a", node_id, direction: :outgoing)
```

The underlying Cypher uses `_graph_id` for isolation:

```cypher
MATCH (n {id: $node_id, _graph_id: $graph_id})
RETURN n, labels(n) as labels
```

### Custom Cypher Queries

Execute arbitrary Cypher with automatic graph_id injection:

```elixir
cypher = """
MATCH (p:Person {_graph_id: $graph_id})
WHERE p.age > $min_age
RETURN p.name AS name, p.age AS age
ORDER BY p.age DESC
"""

{:ok, result} = Neo4j.query("my_graph", cypher, %{min_age: 25})
# result.records contains [%{"name" => "Alice", "age" => 30}, ...]
```

Both `$graph_id` and `$_graph_id` are available in queries.

### Boltx Driver

This adapter uses [boltx](https://hex.pm/packages/boltx) (v0.0.6+) for Neo4j connectivity:

```elixir
# config/dev.exs
config :boltx, Boltx,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  pool_size: 10,
  name: Boltx  # Required for connection pool registration
```

### Neo4j Integration Tests

Integration tests create isolated graph namespaces per test:

```elixir
defmodule MyNeo4jTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.GraphStore.Neo4j

  describe "my feature" do
    @tag :integration
    test "creates nodes" do
      # Create unique graph for this test
      graph_id = "test_#{System.unique_integer([:positive])}"
      :ok = Neo4j.create_graph(graph_id, %{})

      # Test logic...
      {:ok, node} = Neo4j.create_node(graph_id, %{
        labels: ["Test"],
        properties: %{name: "example"}
      })

      assert is_binary(node.id)

      # Cleanup
      Neo4j.delete_graph(graph_id)
    end
  end
end
```

### Telemetry Events

The Neo4j adapter emits telemetry events:

```elixir
# Event names
[:portfolio_index, :graph_store, :create_node]
[:portfolio_index, :graph_store, :create_edge]
[:portfolio_index, :graph_store, :query]

# Measurements
%{duration_ms: 5}

# Metadata
%{graph_id: "my_graph"}
```

Attach handlers for observability:

```elixir
:telemetry.attach(
  "neo4j-logger",
  [:portfolio_index, :graph_store, :query],
  fn _event, %{duration_ms: ms}, %{graph_id: id}, _config ->
    Logger.info("Neo4j query on #{id} took #{ms}ms")
  end,
  nil
)
```

## Pgvector Details

### PostgreSQL Setup

```bash
# Install PostgreSQL and pgvector extension
sudo apt install postgresql postgresql-contrib libpq-dev postgresql-16-pgvector

# Create database
createdb portfolio_index_dev

# Enable pgvector extension
psql -d portfolio_index_dev -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Run migrations
mix ecto.migrate
```

### Index Configuration

Create vector indexes with customizable parameters:

```elixir
alias PortfolioIndex.Adapters.VectorStore.Pgvector

# Basic index with defaults
:ok = Pgvector.create_index("docs", %{dimensions: 768})

# Cosine similarity with HNSW index
:ok = Pgvector.create_index("embeddings", %{
  dimensions: 768,
  metric: :cosine,
  index_type: :hnsw,
  options: %{m: 16, ef_construction: 64}
})

# Euclidean distance with IVFFlat index
:ok = Pgvector.create_index("images", %{
  dimensions: 512,
  metric: :euclidean,
  index_type: :ivfflat,
  options: %{lists: 100}
})
```

### Distance Metrics

| Metric | Operator | Use Case |
|--------|----------|----------|
| `:cosine` | `<=>` | Text embeddings, normalized vectors |
| `:euclidean` | `<->` | Image embeddings, spatial data |
| `:dot_product` | `<#>` | When vectors are already normalized |

### Index Types

| Type | Description | Best For |
|------|-------------|----------|
| `:ivfflat` | Inverted file index | Large datasets, good recall |
| `:hnsw` | Hierarchical navigable small world | Fast queries, high recall |
| `:flat` | No index (exact search) | Small datasets, perfect accuracy |

### Vector Operations

```elixir
alias PortfolioIndex.Adapters.VectorStore.Pgvector

# Store a vector with metadata
:ok = Pgvector.store("docs", "doc_1", embedding_vector, %{
  source: "/path/to/file.md",
  title: "My Document",
  chunk_index: 0
})

# Batch store (more efficient)
items = [
  {"doc_1", vector1, %{source: "/a.md"}},
  {"doc_2", vector2, %{source: "/b.md"}},
  {"doc_3", vector3, %{source: "/c.md"}}
]
{:ok, 3} = Pgvector.store_batch("docs", items)

# Search with k nearest neighbors
{:ok, results} = Pgvector.search("docs", query_vector, 10, [])
# results = [%{id: "doc_1", score: 0.95, metadata: %{...}}, ...]

# Search with metadata filter
{:ok, results} = Pgvector.search("docs", query_vector, 10,
  filter: %{source: "/a.md"}
)

# Search with minimum score threshold
{:ok, results} = Pgvector.search("docs", query_vector, 10,
  min_score: 0.8
)

# Include vectors in results
{:ok, results} = Pgvector.search("docs", query_vector, 10,
  include_vector: true
)

# Delete a vector
:ok = Pgvector.delete("docs", "doc_1")

# Get index statistics
{:ok, stats} = Pgvector.index_stats("docs")
# stats = %{count: 1000, dimensions: 768, metric: :cosine, size_bytes: ...}

# Check if index exists
Pgvector.index_exists?("docs")  # => true or false

# Delete entire index
:ok = Pgvector.delete_index("docs")
```

### Table Structure

Each index creates a table with this schema:

```sql
CREATE TABLE vectors_<index_id> (
  id VARCHAR(255) PRIMARY KEY,
  embedding vector(<dimensions>),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

Index metadata is tracked in the registry:

```sql
CREATE TABLE vector_index_registry (
  index_id VARCHAR(255) PRIMARY KEY,
  dimensions INTEGER NOT NULL,
  metric VARCHAR(50) NOT NULL,
  index_type VARCHAR(50) NOT NULL,
  options JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

### Ecto Configuration

```elixir
# config/dev.exs
config :portfolio_index, PortfolioIndex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "portfolio_index_dev",
  pool_size: 10

# config/test.exs
config :portfolio_index, PortfolioIndex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "portfolio_index_test",
  pool: Ecto.Adapters.SQL.Sandbox
```

### Pgvector Integration Tests

Integration tests use Ecto sandbox for isolation:

```elixir
defmodule MyVectorTest do
  use ExUnit.Case, async: false

  alias PortfolioIndex.Adapters.VectorStore.Pgvector

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(PortfolioIndex.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @tag :integration
  test "stores and searches vectors" do
    index_id = "test_#{System.unique_integer([:positive])}"
    :ok = Pgvector.create_index(index_id, %{dimensions: 768})

    vector = for _ <- 1..768, do: :rand.uniform()
    :ok = Pgvector.store(index_id, "doc_1", vector, %{})

    {:ok, results} = Pgvector.search(index_id, vector, 1, [])
    assert hd(results).id == "doc_1"

    Pgvector.delete_index(index_id)
  end
end
```

### Telemetry Events

The Pgvector adapter emits telemetry events:

```elixir
# Event names
[:portfolio_index, :vector_store, :store]
[:portfolio_index, :vector_store, :store_batch]
[:portfolio_index, :vector_store, :search]

# Measurements
%{duration_ms: 5}                    # store
%{duration_ms: 50, count: 100}       # store_batch
%{duration_ms: 10, k: 10, results: 8} # search

# Metadata
%{index_id: "my_index"}
```

Attach handlers for monitoring:

```elixir
:telemetry.attach(
  "pgvector-logger",
  [:portfolio_index, :vector_store, :search],
  fn _event, %{duration_ms: ms, results: n}, %{index_id: id}, _config ->
    Logger.info("Search on #{id}: #{n} results in #{ms}ms")
  end,
  nil
)
```

### Performance Tips

1. **Use HNSW for production** - Better query performance than IVFFlat
2. **Batch inserts** - Use `store_batch/2` for bulk ingestion
3. **Tune HNSW parameters**:
   - `m`: Higher = better recall, more memory (default: 16)
   - `ef_construction`: Higher = better index quality, slower build (default: 64)
4. **Use metadata filters** - Reduces search space before vector comparison
5. **Set appropriate `min_score`** - Filters low-quality matches early

## Documentation

- [HexDocs](https://hexdocs.pm/portfolio_index)

## Related Packages

- [`portfolio_core`](https://github.com/nshkrdotcom/portfolio_core) - Hexagonal architecture primitives
- [`portfolio_manager`](https://github.com/nshkrdotcom/portfolio_manager) - CLI and application layer

## Acknowledgments

Significant portions of this library's architecture and features were derived from
analysis of [Arcana](https://github.com/georgeguimaraes/arcana) by George Guimarães,
licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

Features inspired by Arcana include:
- RAG pipeline architecture (query rewriting, expansion, decomposition)
- Evaluation system design (IR metrics, test case generation)
- Chunker token utilities and sizing options
- Telemetry patterns and agent system design

See `docs/20251230/arcana_gap_analysis/` for detailed analysis.

## License

MIT License - see [LICENSE](LICENSE) for details.
