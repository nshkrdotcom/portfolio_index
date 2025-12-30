# Prompt 6: Vector Store Enhancements Implementation

## Target Repository
- **portfolio_index**: `/home/home/p/g/n/portfolio_index`

## Required Reading Before Implementation

### Reference Implementation (Arcana)
Read these files to understand the reference implementation:
```
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/vector_store.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/vector_store/pgvector.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/vector_store/hnswlib.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/search.ex
```

### Existing Portfolio Code
Read these files to understand existing patterns:
```
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/vector_store.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/vector_store/pgvector.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/vector_store/qdrant.ex
```

### Gap Analysis Documentation
```
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/03_vector_store.md
```

---

## Implementation Tasks

### Task 1: In-Memory HNSWLib Adapter

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/vector_store/memory.ex`:

```elixir
defmodule PortfolioIndex.Adapters.VectorStore.Memory do
  @moduledoc """
  In-memory vector store using HNSWLib for fast similarity search.
  Useful for testing, development, and small datasets.

  ## Configuration

      config :portfolio_index, PortfolioIndex.Adapters.VectorStore.Memory,
        dimensions: 384,
        max_elements: 10_000,
        ef_construction: 200,
        m: 16

  ## Usage

  Add to supervision tree:

      children = [
        {PortfolioIndex.Adapters.VectorStore.Memory, name: :my_index, dimensions: 384}
      ]

  ## Notes

  - Data is not persisted across restarts
  - Supports optional file-based persistence via save/load
  - Thread-safe for concurrent reads and writes
  """

  @behaviour PortfolioCore.Ports.VectorStore

  use GenServer

  @default_opts [
    max_elements: 10_000,
    ef_construction: 200,
    m: 16,
    space: :cosine
  ]

  # GenServer callbacks
  def start_link(opts)
  def init(opts)
  def child_spec(opts)

  @impl PortfolioCore.Ports.VectorStore
  def insert(store, id, embedding, metadata \\ %{}, opts \\ [])

  @impl PortfolioCore.Ports.VectorStore
  def insert_batch(store, items, opts \\ [])

  @impl PortfolioCore.Ports.VectorStore
  def search(store, embedding, opts \\ [])

  @impl PortfolioCore.Ports.VectorStore
  def delete(store, id, opts \\ [])

  @impl PortfolioCore.Ports.VectorStore
  def get(store, id, opts \\ [])

  @doc "Save index to file"
  @spec save(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def save(store, path)

  @doc "Load index from file"
  @spec load(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def load(store, path)

  @doc "Get index statistics"
  @spec stats(GenServer.server()) :: map()
  def stats(store)

  @doc "Clear all data"
  @spec clear(GenServer.server()) :: :ok
  def clear(store)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/vector_store/memory_test.exs`

---

### Task 2: Backend Override Pattern

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/vector_store/backend.ex`:

```elixir
defmodule PortfolioIndex.VectorStore.Backend do
  @moduledoc """
  Backend resolution and override utilities for vector store operations.
  Allows per-call backend switching without global configuration changes.

  ## Usage

      # Use default backend from config
      Backend.search(embedding, limit: 5)

      # Override backend for this call
      Backend.search(embedding, limit: 5, backend: :memory)

      # Use specific backend module
      Backend.search(embedding, backend: PortfolioIndex.Adapters.VectorStore.Qdrant)
  """

  alias PortfolioIndex.Adapters.VectorStore

  @type backend_spec :: atom() | module() | {module(), keyword()}

  @backend_aliases %{
    pgvector: VectorStore.Pgvector,
    qdrant: VectorStore.Qdrant,
    memory: VectorStore.Memory
  }

  @doc "Resolve backend specification to module and options"
  @spec resolve(backend_spec() | nil) :: {module(), keyword()}
  def resolve(backend_spec \\ nil)

  @doc "Get the default backend from configuration"
  @spec default() :: {module(), keyword()}
  def default()

  @doc "Execute search with backend resolution"
  @spec search([float()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(embedding, opts \\ [])

  @doc "Execute insert with backend resolution"
  @spec insert(String.t(), [float()], map(), keyword()) :: :ok | {:error, term()}
  def insert(id, embedding, metadata, opts \\ [])

  @doc "Execute batch insert with backend resolution"
  @spec insert_batch([map()], keyword()) :: :ok | {:error, term()}
  def insert_batch(items, opts \\ [])

  @doc "Execute delete with backend resolution"
  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(id, opts \\ [])

  @doc "Get item by ID with backend resolution"
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, :not_found} | {:error, term()}
  def get(id, opts \\ [])
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/vector_store/backend_test.exs`

---

### Task 3: Auto Index Creation

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/vector_store/index_manager.ex`:

```elixir
defmodule PortfolioIndex.VectorStore.IndexManager do
  @moduledoc """
  Manages vector store indexes including auto-creation and configuration.
  """

  @doc """
  Ensure index exists, creating if necessary.

  Options vary by backend:
  - pgvector: Creates HNSW index on embedding column
  - qdrant: Creates collection with specified config
  - memory: Initializes HNSWLib index
  """
  @spec ensure_index(module(), keyword()) :: :ok | {:error, term()}
  def ensure_index(backend, opts \\ [])

  @doc """
  Check if index exists.
  """
  @spec index_exists?(module(), keyword()) :: boolean()
  def index_exists?(backend, opts \\ [])

  @doc """
  Get index statistics.
  """
  @spec index_stats(module(), keyword()) :: {:ok, map()} | {:error, term()}
  def index_stats(backend, opts \\ [])

  @doc """
  Rebuild index (useful after bulk inserts).
  """
  @spec rebuild_index(module(), keyword()) :: :ok | {:error, term()}
  def rebuild_index(backend, opts \\ [])

  @doc """
  Drop index.
  """
  @spec drop_index(module(), keyword()) :: :ok | {:error, term()}
  def drop_index(backend, opts \\ [])
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/vector_store/index_manager_test.exs`

---

### Task 4: Collection Organization

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/vector_store/collections.ex`:

```elixir
defmodule PortfolioIndex.VectorStore.Collections do
  @moduledoc """
  Collection-based organization for vector store operations.
  Provides logical grouping of vectors without separate physical stores.
  """

  @doc """
  Search within a specific collection.
  """
  @spec search_collection(String.t(), [float()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def search_collection(collection, embedding, opts \\ [])

  @doc """
  Insert into a specific collection.
  """
  @spec insert_to_collection(String.t(), String.t(), [float()], map(), keyword()) :: :ok | {:error, term()}
  def insert_to_collection(collection, id, embedding, metadata, opts \\ [])

  @doc """
  List all collections.
  """
  @spec list_collections(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def list_collections(opts \\ [])

  @doc """
  Get collection statistics.
  """
  @spec collection_stats(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def collection_stats(collection, opts \\ [])

  @doc """
  Delete all vectors in a collection.
  """
  @spec clear_collection(String.t(), keyword()) :: :ok | {:error, term()}
  def clear_collection(collection, opts \\ [])

  @doc """
  Check if collection exists.
  """
  @spec collection_exists?(String.t(), keyword()) :: boolean()
  def collection_exists?(collection, opts \\ [])
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/vector_store/collections_test.exs`

---

### Task 5: Soft Deletion Support

Update the pgvector adapter to support soft deletion:

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/vector_store/soft_delete.ex`:

```elixir
defmodule PortfolioIndex.VectorStore.SoftDelete do
  @moduledoc """
  Soft deletion utilities for vector store items.
  Marks items as deleted without removing from storage.
  """

  @doc """
  Soft delete an item by ID.
  """
  @spec soft_delete(Ecto.Repo.t(), String.t()) :: :ok | {:error, term()}
  def soft_delete(repo, id)

  @doc """
  Soft delete items matching filter.
  """
  @spec soft_delete_where(Ecto.Repo.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def soft_delete_where(repo, filters)

  @doc """
  Restore a soft-deleted item.
  """
  @spec restore(Ecto.Repo.t(), String.t()) :: :ok | {:error, term()}
  def restore(repo, id)

  @doc """
  Permanently delete soft-deleted items older than threshold.
  """
  @spec purge_deleted(Ecto.Repo.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def purge_deleted(repo, opts \\ [])

  @doc """
  Count soft-deleted items.
  """
  @spec count_deleted(Ecto.Repo.t()) :: non_neg_integer()
  def count_deleted(repo)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/vector_store/soft_delete_test.exs`

---

### Task 6: Enhanced Search Options

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/vector_store/search.ex`:

```elixir
defmodule PortfolioIndex.VectorStore.Search do
  @moduledoc """
  Enhanced search utilities with filtering, scoring, and result processing.
  """

  @type search_opts :: [
    limit: pos_integer(),
    threshold: float(),
    collection: String.t(),
    filters: keyword(),
    include_deleted: boolean(),
    include_metadata: boolean(),
    distance_metric: :cosine | :euclidean | :dot_product
  ]

  @doc """
  Execute similarity search with enhanced options.
  """
  @spec similarity_search([float()], search_opts()) :: {:ok, [map()]} | {:error, term()}
  def similarity_search(embedding, opts \\ [])

  @doc """
  Execute hybrid search combining vector and keyword search.
  Uses Reciprocal Rank Fusion (RRF) for result merging.
  """
  @spec hybrid_search([float()], String.t(), search_opts()) :: {:ok, [map()]} | {:error, term()}
  def hybrid_search(embedding, query_text, opts \\ [])

  @doc """
  Apply metadata filters to search results.
  """
  @spec filter_results([map()], keyword()) :: [map()]
  def filter_results(results, filters)

  @doc """
  Normalize similarity scores to 0-1 range.
  """
  @spec normalize_scores([map()], atom()) :: [map()]
  def normalize_scores(results, distance_metric)

  @doc """
  Deduplicate results by content hash or ID.
  """
  @spec deduplicate([map()], atom()) :: [map()]
  def deduplicate(results, key \\ :id)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/vector_store/search_test.exs`

---

## TDD Requirements

For each task:

1. **Write tests FIRST** following existing test patterns in the repo
2. Tests must cover:
   - CRUD operations (insert, search, delete, get)
   - Batch operations
   - Collection filtering
   - Backend override functionality
   - Edge cases (empty results, not found)
   - Concurrent access (for memory store)
3. Run tests continuously: `mix test path/to/test_file.exs`

## Quality Gates

Before considering this prompt complete:

```bash
cd /home/home/p/g/n/portfolio_index
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
- `PortfolioIndex.Adapters.VectorStore.Memory` - In-memory HNSWLib vector store
- `PortfolioIndex.VectorStore.Backend` - Backend resolution with per-call override
- `PortfolioIndex.VectorStore.IndexManager` - Index auto-creation and management
- `PortfolioIndex.VectorStore.Collections` - Collection-based organization
- `PortfolioIndex.VectorStore.SoftDelete` - Soft deletion support
- `PortfolioIndex.VectorStore.Search` - Enhanced search with hybrid support
```

## Verification Checklist

- [ ] All new files created in correct locations
- [ ] All tests pass
- [ ] No credo warnings
- [ ] No dialyzer errors
- [ ] Changelog updated
- [ ] Module documentation complete with @moduledoc and @doc
- [ ] Type specifications complete with @type and @spec
- [ ] Memory store properly handles concurrent access

