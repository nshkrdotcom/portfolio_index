# Pipelines

PortfolioIndex uses [Broadway](https://github.com/dashbitco/broadway) for
document ingestion and embedding with backpressure, batching, and fault tolerance.

## Ingestion Pipeline

`PortfolioIndex.Pipelines.Ingestion` reads files from disk, chunks them, and
stores the chunks in the document store:

```elixir
{:ok, _pid} = PortfolioIndex.Pipelines.Ingestion.start(
  paths: ["/path/to/docs"],
  patterns: ["**/*.md", "**/*.ex"],
  index_id: "my_index",
  chunk_size: 1000,
  chunk_overlap: 200
)
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `:paths` | List of directories to scan | required |
| `:patterns` | Glob patterns to match | `["**/*"]` |
| `:index_id` | Target index name | required |
| `:chunk_size` | Characters per chunk | `1000` |
| `:chunk_overlap` | Overlap between chunks | `200` |

### How It Works

1. `FileProducer` scans directories and emits file paths
2. Broadway processors read file contents
3. Files are chunked using the configured chunker
4. Chunks are stored as `PortfolioIndex.Schemas.Document` and `PortfolioIndex.Schemas.Chunk` records
5. Documents track status: `:pending` → `:processing` → `:completed` (or `:failed`)

### Ad-Hoc File Indexing

```elixir
PortfolioIndex.Pipelines.Ingestion.enqueue(pipeline_pid, "/path/to/new_file.md")
```

## Embedding Pipeline

`PortfolioIndex.Pipelines.Embedding` reads unembedded chunks and generates
vector embeddings:

```elixir
{:ok, _pid} = PortfolioIndex.Pipelines.Embedding.start(
  index_id: "my_index",
  rate_limit: 100,
  batch_size: 50
)
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `:index_id` | Index to process | required |
| `:rate_limit` | Max embeddings per second | `100` |
| `:batch_size` | Chunks per batch | `50` |

### How It Works

1. `ETSProducer` queries for chunks without embeddings
2. Broadway batchers group chunks for efficient API calls
3. The configured embedder generates vectors
4. Vectors are stored in the vector store with chunk metadata

## Producers

### File Producer

`PortfolioIndex.Pipelines.Producers.FileProducer` scans directories for files
matching glob patterns:

```elixir
{:ok, pid} = FileProducer.start_link(
  paths: ["/docs"],
  patterns: ["**/*.md"]
)
```

### ETS Producer

`PortfolioIndex.Pipelines.Producers.ETSProducer` reads records from ETS tables,
used internally by the embedding pipeline to fetch unprocessed chunks.

## Document Schemas

The pipeline uses Ecto schemas for persistence:

### Collection

`PortfolioIndex.Schemas.Collection` groups related documents:

```elixir
%Collection{
  name: "my_collection",
  metadata: %{},
  document_count: 42  # virtual field
}
```

### Document

`PortfolioIndex.Schemas.Document` tracks ingested documents:

```elixir
%Document{
  source_id: "/path/to/file.md",
  content: "...",
  content_hash: "sha256...",    # for deduplication
  status: :completed,           # :pending | :processing | :completed | :failed | :deleted
  error_message: nil,
  collection_id: "..."
}
```

### Chunk

`PortfolioIndex.Schemas.Chunk` stores document chunks with embeddings:

```elixir
%Chunk{
  content: "chunk text...",
  embedding: Pgvector.Ecto.Vector,
  start_char: 0,
  end_char: 999,
  token_count: 250,
  chunk_index: 0,
  document_id: "..."
}
```

## Query Helpers

`PortfolioIndex.Schemas.Queries` provides common queries:

```elixir
alias PortfolioIndex.Schemas.Queries

Queries.get_collection_by_name(repo, "my_collection")
Queries.get_or_create_collection(repo, "my_collection", %{})
Queries.list_documents_by_status(repo, :failed, limit: 10)
Queries.get_document_with_chunks(repo, document_id)
Queries.similarity_search(repo, query_vector, k: 10)
Queries.count_chunks_without_embedding(repo)
Queries.get_failed_documents(repo, limit: 10)
Queries.soft_delete_document(repo, document_id)
```

## Generating Migrations

Use the install task to generate initial migrations:

```bash
mix portfolio.install --dimension 768
```

Or generate a migration for dimension changes:

```bash
mix portfolio.gen.embedding_migration --dimension 1536
```
