# Maintenance

PortfolioIndex provides production maintenance utilities for managing embeddings,
diagnosing issues, and recovering from failures.

## Maintenance Module

`PortfolioIndex.Maintenance` is the main entry point for maintenance operations.

### Re-embedding

Re-embed all chunks or a filtered subset when you change embedding models or
dimensions:

```elixir
alias PortfolioIndex.Maintenance

# Re-embed everything
{:ok, stats} = Maintenance.reembed(repo,
  progress: Maintenance.Progress.cli_reporter("Re-embedding")
)

# Re-embed a specific collection
{:ok, stats} = Maintenance.reembed(repo,
  collection: "my_docs",
  progress: Maintenance.Progress.cli_reporter("Re-embedding my_docs")
)
```

### Diagnostics

Get system health information:

```elixir
{:ok, diagnostics} = Maintenance.diagnostics(repo)

# diagnostics includes:
# - Total document count
# - Chunks with/without embeddings
# - Collection statistics
# - Storage usage estimates
# - Failed document count
```

### Retry Failed Documents

Reset failed documents to pending for reprocessing:

```elixir
{:ok, count} = Maintenance.retry_failed(repo, limit: 100)
IO.puts("Reset #{count} documents for retry")
```

### Cleanup Deleted Documents

Permanently remove soft-deleted documents and their chunks:

```elixir
{:ok, count} = Maintenance.cleanup_deleted(repo,
  older_than_days: 30
)
```

### Verify Embeddings

Check embedding consistency across chunks:

```elixir
{:ok, report} = Maintenance.verify_embeddings(repo)

# report includes:
# - Chunks with missing embeddings
# - Chunks with wrong dimensions
# - Dimension mismatches across collections
```

## Progress Reporting

`PortfolioIndex.Maintenance.Progress` provides progress reporting for
long-running maintenance operations:

### CLI Reporter

Prints progress to stdout:

```elixir
reporter = Maintenance.Progress.cli_reporter("Re-embedding")
# Output: Re-embedding: 42% (420/1000)
```

### Silent Reporter

No output (for background jobs):

```elixir
reporter = Maintenance.Progress.silent_reporter()
```

### Telemetry Reporter

Emits telemetry events for monitoring:

```elixir
reporter = Maintenance.Progress.telemetry_reporter("reembed")
# Emits: [:portfolio_index, :maintenance, :progress]
```

### Building Custom Events

```elixir
event = Maintenance.Progress.build_event(:reembed, 42, 1000, %{collection: "docs"})
# %{operation: :reembed, current: 42, total: 1000, metadata: %{...}}
```

## Mix Tasks

### portfolio.install

Generates migrations and configuration for new projects:

```bash
mix portfolio.install
mix portfolio.install --repo MyApp.Repo --dimension 1536 --no-migrations
```

Options:
- `--repo` -- Ecto repo module (default: auto-detected)
- `--dimension` -- vector dimensions (default: 768)
- `--no-migrations` -- skip migration generation

### portfolio.gen.embedding_migration

Generates a migration to change vector column dimensions:

```bash
mix portfolio.gen.embedding_migration --dimension 1536
mix portfolio.gen.embedding_migration --dimension 3072 --table my_chunks --column my_embedding
```

Options:
- `--dimension` -- new dimension (required)
- `--table` -- table name (default: `portfolio_chunks`)
- `--column` -- column name (default: `embedding`)

This drops and recreates the HNSW index for the new dimensions.
