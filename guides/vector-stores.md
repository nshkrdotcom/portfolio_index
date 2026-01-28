# Vector Stores

PortfolioIndex provides vector store adapters for similarity search. The primary
production adapter is **pgvector** (PostgreSQL). An in-memory HNSWLib store is
available for testing and development.

## Pgvector Adapter

`PortfolioIndex.Adapters.VectorStore.Pgvector` stores embeddings in PostgreSQL
using the [pgvector](https://github.com/pgvector/pgvector) extension.

### Creating an Index

```elixir
alias PortfolioIndex.Adapters.VectorStore.Pgvector

# Basic cosine similarity index
:ok = Pgvector.create_index("docs", %{dimensions: 768, metric: :cosine})

# HNSW index with tuning parameters
:ok = Pgvector.create_index("embeddings", %{
  dimensions: 768,
  metric: :cosine,
  index_type: :hnsw,
  options: %{m: 16, ef_construction: 64}
})

# IVFFlat index for large datasets
:ok = Pgvector.create_index("images", %{
  dimensions: 512,
  metric: :euclidean,
  index_type: :ivfflat,
  options: %{lists: 100}
})
```

### Distance Metrics

| Metric | Operator | Best For |
|--------|----------|----------|
| `:cosine` | `<=>` | Text embeddings, normalized vectors |
| `:euclidean` | `<->` | Image embeddings, spatial data |
| `:dot_product` | `<#>` | Pre-normalized vectors |

### Index Types

| Type | Description | Tradeoffs |
|------|-------------|-----------|
| `:hnsw` | Hierarchical Navigable Small World | Fast queries, high recall, more memory |
| `:ivfflat` | Inverted file index | Good recall, less memory, slower queries |
| `:flat` | No index (exact search) | Perfect accuracy, slow on large datasets |

### Storing Vectors

```elixir
# Single store
:ok = Pgvector.store("docs", "doc_1", embedding_vector, %{
  source: "/path/to/file.md",
  title: "My Document",
  chunk_index: 0
})

# Batch store (much faster for bulk ingestion)
items = [
  {"doc_1", vector1, %{source: "/a.md"}},
  {"doc_2", vector2, %{source: "/b.md"}},
  {"doc_3", vector3, %{source: "/c.md"}}
]
{:ok, 3} = Pgvector.store_batch("docs", items)
```

### Searching

```elixir
# Basic k-NN search
{:ok, results} = Pgvector.search("docs", query_vector, 10, [])

# With metadata filter
{:ok, results} = Pgvector.search("docs", query_vector, 10,
  filter: %{source: "/a.md"}
)

# With minimum score threshold
{:ok, results} = Pgvector.search("docs", query_vector, 10,
  min_score: 0.8
)

# Include vectors in results
{:ok, results} = Pgvector.search("docs", query_vector, 10,
  include_vector: true
)
```

Results are returned as lists of maps: `%{id: "doc_1", score: 0.95, metadata: %{...}}`.

### Hybrid Search (Vector + Full-Text)

`PortfolioIndex.Adapters.VectorStore.Pgvector.Hybrid` combines vector similarity
with PostgreSQL `tsvector` full-text search using Reciprocal Rank Fusion (RRF):

```elixir
alias PortfolioIndex.Adapters.VectorStore.Pgvector.Hybrid

{:ok, results} = Hybrid.search("docs", query_vector, "elixir genserver", 10,
  vector_weight: 0.7,
  text_weight: 0.3
)
```

### Index Management

```elixir
Pgvector.index_exists?("docs")            # => true/false
{:ok, stats} = Pgvector.index_stats("docs") # count, dimensions, metric, size
:ok = Pgvector.delete("docs", "doc_1")     # delete single vector
:ok = Pgvector.delete_index("docs")        # delete entire index
```

## Memory Store

`PortfolioIndex.Adapters.VectorStore.Memory` provides an in-memory HNSWLib-based
store for testing and development:

```elixir
alias PortfolioIndex.Adapters.VectorStore.Memory

{:ok, pid} = Memory.start_link(dimensions: 768, max_elements: 10_000)
:ok = Memory.insert(pid, "doc_1", vector, %{content: "hello"})
{:ok, results} = Memory.search(pid, query_vector, 5)
```

Features:
- GenServer-based, thread-safe
- HNSWLib approximate nearest neighbor search
- Soft deletion support
- Optional file-based persistence via save/load

## Backend Abstraction

`PortfolioIndex.VectorStore.Backend` provides a unified API with runtime backend switching:

```elixir
alias PortfolioIndex.VectorStore.Backend

# Uses the configured default backend
{:ok, results} = Backend.search("docs", query_vector, 10)

# Override backend per call
{:ok, results} = Backend.search("docs", query_vector, 10, backend: :memory)

# Backend aliases: :pgvector, :memory, :qdrant
# Module syntax: {Memory, store: pid}
```

## Collection Management

`PortfolioIndex.VectorStore.Collections` organizes vectors into logical groups:

```elixir
alias PortfolioIndex.VectorStore.Collections

Collections.insert_to_collection("my_collection", "docs", "doc_1", vector, metadata)
{:ok, results} = Collections.search_collection("my_collection", query_vector, 10)
{:ok, stats} = Collections.collection_stats("my_collection")
Collections.list_collections("docs")
Collections.clear_collection("my_collection")
```

## Soft Delete

`PortfolioIndex.VectorStore.SoftDelete` marks items as deleted without removing them:

```elixir
alias PortfolioIndex.VectorStore.SoftDelete

SoftDelete.soft_delete("docs", "doc_1")
SoftDelete.restore("docs", "doc_1")
SoftDelete.purge_deleted("docs", max_age_days: 30)
SoftDelete.count_deleted("docs")
```

## Index Manager

`PortfolioIndex.VectorStore.IndexManager` automates index lifecycle:

```elixir
alias PortfolioIndex.VectorStore.IndexManager

IndexManager.ensure_index("docs", %{dimensions: 768})
IndexManager.rebuild_index("docs", %{})
IndexManager.drop_index("docs")
```

## Performance Tips

1. **Use HNSW for production** -- better query performance than IVFFlat
2. **Batch inserts** -- use `store_batch/2` for bulk ingestion
3. **Tune HNSW parameters**: `m` (higher = better recall, more memory), `ef_construction` (higher = better quality, slower build)
4. **Use metadata filters** -- reduces search space before vector comparison
5. **Set `min_score`** -- filters low-quality matches early

## Telemetry Events

```elixir
[:portfolio_index, :vector_store, :store]       # %{duration_ms: 5}
[:portfolio_index, :vector_store, :store_batch]  # %{duration_ms: 50, count: 100}
[:portfolio_index, :vector_store, :search]       # %{duration_ms: 10, k: 10, results: 8}
```

All events include `%{index_id: "my_index"}` in metadata.
