# Prompt 3: Production Maintenance Implementation

## Target Repositories
- **portfolio_index**: `/home/home/p/g/n/portfolio_index`
- **portfolio_manager**: `/home/home/p/g/n/portfolio_manager`

## Required Reading Before Implementation

### Reference Implementation (Arcana)
Read these files to understand the reference implementation:
```
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/maintenance.ex
/home/home/p/g/n/portfolio_index/arcana/lib/mix/tasks/arcana.install.ex
/home/home/p/g/n/portfolio_index/arcana/lib/mix/tasks/arcana.gen.embedding_migration.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/reembedder.ex
```

### Existing Portfolio Code
Read these files to understand existing patterns:
```
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/voyage.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/instructor.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/embedder.ex
/home/home/p/g/n/portfolio_index/mix.exs
```

### Gap Analysis Documentation
```
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/07_mix_tasks.md
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/08_maintenance_and_documents.md
```

---

## Implementation Tasks

### Task 1: Maintenance Module (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/maintenance.ex`:

```elixir
defmodule PortfolioIndex.Maintenance do
  @moduledoc """
  Production maintenance utilities for document and embedding management.
  Provides re-embedding, diagnostics, and batch operations.
  """

  alias PortfolioIndex.Schemas.{Document, Chunk, Collection}

  @type reembed_result :: %{
    total: non_neg_integer(),
    processed: non_neg_integer(),
    failed: non_neg_integer(),
    errors: [%{chunk_id: String.t(), error: term()}]
  }

  @type diagnostics_result :: %{
    collections: non_neg_integer(),
    documents: non_neg_integer(),
    chunks: non_neg_integer(),
    chunks_without_embedding: non_neg_integer(),
    failed_documents: non_neg_integer(),
    storage_bytes: non_neg_integer() | nil
  }

  @doc """
  Re-embed all chunks or a filtered subset.

  Options:
  - `:collection` - Only re-embed chunks in this collection
  - `:document_id` - Only re-embed chunks for this document
  - `:batch_size` - Number of chunks per batch (default 100)
  - `:embedder` - Embedder module to use (default from config)
  - `:on_progress` - Callback function for progress updates
  """
  @spec reembed(Ecto.Repo.t(), keyword()) :: {:ok, reembed_result()} | {:error, term()}
  def reembed(repo, opts \\ [])

  @doc """
  Get system diagnostics including counts and storage usage.
  """
  @spec diagnostics(Ecto.Repo.t()) :: {:ok, diagnostics_result()}
  def diagnostics(repo)

  @doc """
  Retry failed document processing.

  Options:
  - `:limit` - Max documents to retry (default all)
  - `:on_progress` - Callback for progress updates
  """
  @spec retry_failed(Ecto.Repo.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def retry_failed(repo, opts \\ [])

  @doc """
  Clean up soft-deleted documents and their chunks.
  """
  @spec cleanup_deleted(Ecto.Repo.t(), keyword()) :: {:ok, non_neg_integer()}
  def cleanup_deleted(repo, opts \\ [])

  @doc """
  Verify embedding consistency (detect dimension mismatches).
  """
  @spec verify_embeddings(Ecto.Repo.t()) :: {:ok, map()} | {:error, term()}
  def verify_embeddings(repo)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/maintenance_test.exs`

---

### Task 2: Install Mix Task (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/mix/tasks/portfolio.install.ex`:

```elixir
defmodule Mix.Tasks.Portfolio.Install do
  @moduledoc """
  Installs PortfolioIndex into a Phoenix application.

  ## Usage

      mix portfolio.install

  ## What it does

  1. Creates required database migrations
  2. Prints configuration instructions
  3. Provides next steps for setup

  ## Options

  - `--repo` - Ecto repo module (default: inferred from app)
  - `--dimension` - Embedding vector dimension (default: 384)
  - `--no-migrations` - Skip migration generation
  """

  use Mix.Task

  @shortdoc "Install PortfolioIndex in your application"

  @impl Mix.Task
  def run(args)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/mix/tasks/portfolio.install_test.exs`

---

### Task 3: Embedding Migration Generator (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/mix/tasks/portfolio.gen.embedding_migration.ex`:

```elixir
defmodule Mix.Tasks.Portfolio.Gen.EmbeddingMigration do
  @moduledoc """
  Generates a migration for changing embedding dimensions.

  ## Usage

      mix portfolio.gen.embedding_migration --dimension 1536

  This is useful when switching embedding models with different dimensions.

  ## Options

  - `--dimension` - New embedding dimension (required)
  - `--table` - Table name (default: portfolio_chunks)
  - `--column` - Column name (default: embedding)
  """

  use Mix.Task

  @shortdoc "Generate migration to change embedding dimensions"

  @impl Mix.Task
  def run(args)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/mix/tasks/portfolio.gen.embedding_migration_test.exs`

---

### Task 4: Re-embed Mix Task (portfolio_manager)

Create `/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.reembed.ex`:

```elixir
defmodule Mix.Tasks.Portfolio.Reembed do
  @moduledoc """
  Re-embeds documents using the current embedding configuration.

  ## Usage

      # Re-embed all chunks
      mix portfolio.reembed

      # Re-embed specific collection
      mix portfolio.reembed --collection my_docs

      # Re-embed with progress output
      mix portfolio.reembed --verbose

  ## Options

  - `--collection` - Only re-embed chunks in this collection
  - `--batch-size` - Chunks per batch (default: 100)
  - `--verbose` - Show progress updates
  - `--dry-run` - Show what would be re-embedded without doing it
  """

  use Mix.Task

  @shortdoc "Re-embed documents with current embedding model"

  @impl Mix.Task
  def run(args)
end
```

**Test file**: `/home/home/p/g/n/portfolio_manager/test/mix/tasks/portfolio.reembed_test.exs`

---

### Task 5: Diagnostics Mix Task (portfolio_manager)

Create `/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.diagnostics.ex`:

```elixir
defmodule Mix.Tasks.Portfolio.Diagnostics do
  @moduledoc """
  Shows diagnostics for the PortfolioIndex system.

  ## Usage

      mix portfolio.diagnostics

  ## Output

  Shows:
  - Collection count and names
  - Document count by status
  - Chunk count and embedding coverage
  - Storage usage estimates
  - Configuration summary
  """

  use Mix.Task

  @shortdoc "Show PortfolioIndex system diagnostics"

  @impl Mix.Task
  def run(args)
end
```

**Test file**: `/home/home/p/g/n/portfolio_manager/test/mix/tasks/portfolio.diagnostics_test.exs`

---

### Task 6: Progress Reporter Module (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/maintenance/progress.ex`:

```elixir
defmodule PortfolioIndex.Maintenance.Progress do
  @moduledoc """
  Progress reporting utilities for maintenance operations.
  Provides callbacks for CLI and programmatic progress tracking.
  """

  @type progress_callback :: (map() -> :ok)

  @type progress_event :: %{
    operation: atom(),
    current: non_neg_integer(),
    total: non_neg_integer(),
    percentage: float(),
    message: String.t() | nil
  }

  @doc "Create a CLI progress reporter that prints to stdout"
  @spec cli_reporter(keyword()) :: progress_callback()
  def cli_reporter(opts \\ [])

  @doc "Create a silent reporter (no-op)"
  @spec silent_reporter() :: progress_callback()
  def silent_reporter()

  @doc "Create a telemetry-emitting reporter"
  @spec telemetry_reporter(list()) :: progress_callback()
  def telemetry_reporter(event_prefix)

  @doc "Report progress event"
  @spec report(progress_callback() | nil, progress_event()) :: :ok
  def report(callback, event)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/maintenance/progress_test.exs`

---

## TDD Requirements

For each task:

1. **Write tests FIRST** following existing test patterns in the repos
2. Tests must cover:
   - Happy path with valid input
   - Error handling (database errors, invalid options)
   - Edge cases (empty database, no embeddings)
   - Progress callback invocation
   - CLI option parsing (for Mix tasks)
3. Run tests continuously: `mix test path/to/test_file.exs`

## Quality Gates

Before considering this prompt complete:

```bash
# In portfolio_index
cd /home/home/p/g/n/portfolio_index
mix test
mix credo --strict
mix dialyzer

# In portfolio_manager
cd /home/home/p/g/n/portfolio_manager
mix test
mix credo --strict
mix dialyzer
```

All must pass with zero warnings and zero errors.

## Documentation Updates

### portfolio_index
Update `/home/home/p/g/n/portfolio_index/CHANGELOG.md` - add entry to version 0.3.1:
```markdown
### Added
- `PortfolioIndex.Maintenance` - Production maintenance utilities (reembed, diagnostics, retry)
- `PortfolioIndex.Maintenance.Progress` - Progress reporting for maintenance operations
- `mix portfolio.install` - Installation task for new projects
- `mix portfolio.gen.embedding_migration` - Generate migration for dimension changes
```

### portfolio_manager
Update `/home/home/p/g/n/portfolio_manager/CHANGELOG.md` - add entry to version 0.3.1:
```markdown
### Added
- `mix portfolio.reembed` - Re-embed documents with current embedding model
- `mix portfolio.diagnostics` - Show system diagnostics and health
```

## Verification Checklist

- [ ] All new files created in correct locations
- [ ] All tests pass in both repos
- [ ] No credo warnings
- [ ] No dialyzer errors
- [ ] Changelogs updated for both repos
- [ ] Module documentation complete with @moduledoc and @doc
- [ ] Type specifications complete with @type and @spec
- [ ] Mix task help text is clear and complete

