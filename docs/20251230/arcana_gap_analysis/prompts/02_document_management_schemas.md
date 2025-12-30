# Prompt 2: Document Management Schemas Implementation

## Target Repository
- **portfolio_index**: `/home/home/p/g/n/portfolio_index`

## Required Reading Before Implementation

### Reference Implementation (Arcana)
Read these files to understand the reference implementation:
```
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/document.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/chunk.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/collection.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/schemas/document.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/schemas/chunk.ex
/home/home/p/g/n/portfolio_index/arcana/priv/repo/migrations/*_create_arcana_*.exs
```

### Existing Portfolio Code
Read these files to understand existing patterns:
```
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/vector_store/pgvector.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/vector_store.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/embedder.ex
```

### Gap Analysis Documentation
```
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/08_maintenance_and_documents.md
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/03_vector_store.md
```

---

## Implementation Tasks

### Task 1: Collection Ecto Schema

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/schemas/collection.ex`:

```elixir
defmodule PortfolioIndex.Schemas.Collection do
  @moduledoc """
  Ecto schema for document collections.
  Collections group related documents for organized retrieval and routing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: Ecto.UUID.t() | nil,
    name: String.t(),
    description: String.t() | nil,
    metadata: map(),
    document_count: non_neg_integer(),
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_collections" do
    field :name, :string
    field :description, :string
    field :metadata, :map, default: %{}
    field :document_count, :integer, default: 0, virtual: true

    has_many :documents, PortfolioIndex.Schemas.Document

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating/updating collections"
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(collection, attrs)

  @doc "Validate name uniqueness"
  @spec validate_unique_name(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_unique_name(changeset)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/schemas/collection_test.exs`

---

### Task 2: Document Ecto Schema

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/schemas/document.ex`:

```elixir
defmodule PortfolioIndex.Schemas.Document do
  @moduledoc """
  Ecto schema for ingested documents.
  Tracks document metadata, status, and relationship to chunks.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :pending | :processing | :completed | :failed | :deleted

  @type t :: %__MODULE__{
    id: Ecto.UUID.t() | nil,
    source_id: String.t() | nil,
    content_hash: String.t() | nil,
    title: String.t() | nil,
    source_path: String.t() | nil,
    metadata: map(),
    status: status(),
    error_message: String.t() | nil,
    chunk_count: non_neg_integer(),
    collection_id: Ecto.UUID.t() | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_documents" do
    field :source_id, :string
    field :content_hash, :string
    field :title, :string
    field :source_path, :string
    field :metadata, :map, default: %{}
    field :status, Ecto.Enum, values: [:pending, :processing, :completed, :failed, :deleted], default: :pending
    field :error_message, :string
    field :chunk_count, :integer, default: 0

    belongs_to :collection, PortfolioIndex.Schemas.Collection
    has_many :chunks, PortfolioIndex.Schemas.Chunk

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating documents"
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(document, attrs)

  @doc "Changeset for updating document status"
  @spec status_changeset(t(), status(), String.t() | nil) :: Ecto.Changeset.t()
  def status_changeset(document, status, error_message \\ nil)

  @doc "Compute content hash for deduplication"
  @spec compute_hash(String.t()) :: String.t()
  def compute_hash(content)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/schemas/document_test.exs`

---

### Task 3: Chunk Ecto Schema with pgvector

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/schemas/chunk.ex`:

```elixir
defmodule PortfolioIndex.Schemas.Chunk do
  @moduledoc """
  Ecto schema for document chunks with vector embeddings.
  Supports pgvector for similarity search.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: Ecto.UUID.t() | nil,
    content: String.t(),
    embedding: Pgvector.Ecto.Vector.t() | nil,
    chunk_index: non_neg_integer(),
    token_count: non_neg_integer() | nil,
    start_char: non_neg_integer() | nil,
    end_char: non_neg_integer() | nil,
    metadata: map(),
    document_id: Ecto.UUID.t() | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_chunks" do
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :chunk_index, :integer
    field :token_count, :integer
    field :start_char, :integer
    field :end_char, :integer
    field :metadata, :map, default: %{}

    belongs_to :document, PortfolioIndex.Schemas.Document

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating chunks"
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(chunk, attrs)

  @doc "Changeset for updating embedding"
  @spec embedding_changeset(t(), [float()]) :: Ecto.Changeset.t()
  def embedding_changeset(chunk, embedding)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/schemas/chunk_test.exs`

---

### Task 4: Database Migrations

Create migration file `/home/home/p/g/n/portfolio_index/priv/repo/migrations/YYYYMMDDHHMMSS_create_portfolio_document_schemas.exs`:

```elixir
defmodule PortfolioIndex.Repo.Migrations.CreatePortfolioDocumentSchemas do
  use Ecto.Migration

  def up do
    # Enable pgvector extension
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    # Collections table
    create table(:portfolio_collections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:portfolio_collections, [:name])

    # Documents table
    create table(:portfolio_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_id, :string
      add :content_hash, :string
      add :title, :string
      add :source_path, :string
      add :metadata, :map, default: %{}
      add :status, :string, default: "pending"
      add :error_message, :text
      add :chunk_count, :integer, default: 0
      add :collection_id, references(:portfolio_collections, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:portfolio_documents, [:collection_id])
    create index(:portfolio_documents, [:source_id])
    create index(:portfolio_documents, [:status])
    create index(:portfolio_documents, [:content_hash])

    # Chunks table with vector column
    # Note: Vector dimension should be configurable, default 384 for bge-small
    create table(:portfolio_chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :text, null: false
      add :embedding, :vector, size: 384
      add :chunk_index, :integer, null: false
      add :token_count, :integer
      add :start_char, :integer
      add :end_char, :integer
      add :metadata, :map, default: %{}
      add :document_id, references(:portfolio_documents, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:portfolio_chunks, [:document_id])

    # HNSW index for fast similarity search
    execute "CREATE INDEX portfolio_chunks_embedding_idx ON portfolio_chunks USING hnsw (embedding vector_cosine_ops)"
  end

  def down do
    drop table(:portfolio_chunks)
    drop table(:portfolio_documents)
    drop table(:portfolio_collections)
  end
end
```

**Note**: Replace `YYYYMMDDHHMMSS` with actual timestamp when creating.

---

### Task 5: Schema Query Helpers

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/schemas/queries.ex`:

```elixir
defmodule PortfolioIndex.Schemas.Queries do
  @moduledoc """
  Query helpers for document management schemas.
  Provides common queries for collections, documents, and chunks.
  """

  import Ecto.Query
  alias PortfolioIndex.Schemas.{Collection, Document, Chunk}

  @doc "Get collection by name"
  @spec get_collection_by_name(Ecto.Repo.t(), String.t()) :: Collection.t() | nil
  def get_collection_by_name(repo, name)

  @doc "Get or create collection by name"
  @spec get_or_create_collection(Ecto.Repo.t(), String.t(), map()) :: {:ok, Collection.t()} | {:error, term()}
  def get_or_create_collection(repo, name, attrs \\ %{})

  @doc "List documents by status"
  @spec list_documents_by_status(Ecto.Repo.t(), Document.status(), keyword()) :: [Document.t()]
  def list_documents_by_status(repo, status, opts \\ [])

  @doc "Get document with chunks preloaded"
  @spec get_document_with_chunks(Ecto.Repo.t(), Ecto.UUID.t()) :: Document.t() | nil
  def get_document_with_chunks(repo, document_id)

  @doc "Find chunks by similarity search"
  @spec similarity_search(Ecto.Repo.t(), [float()], keyword()) :: [Chunk.t()]
  def similarity_search(repo, embedding, opts \\ [])

  @doc "Count chunks needing embedding"
  @spec count_chunks_without_embedding(Ecto.Repo.t()) :: non_neg_integer()
  def count_chunks_without_embedding(repo)

  @doc "Get failed documents for retry"
  @spec get_failed_documents(Ecto.Repo.t(), keyword()) :: [Document.t()]
  def get_failed_documents(repo, opts \\ [])

  @doc "Mark document as deleted (soft delete)"
  @spec soft_delete_document(Ecto.Repo.t(), Document.t()) :: {:ok, Document.t()} | {:error, term()}
  def soft_delete_document(repo, document)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/schemas/queries_test.exs`

---

## TDD Requirements

For each task:

1. **Write tests FIRST** following existing test patterns in the repo
2. Tests must cover:
   - Schema validations (required fields, constraints)
   - Changeset edge cases (missing fields, invalid values)
   - Query functions with fixtures
   - Migration up/down (integration test)
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
- `PortfolioIndex.Schemas.Collection` - Ecto schema for document collections
- `PortfolioIndex.Schemas.Document` - Ecto schema for ingested documents with status tracking
- `PortfolioIndex.Schemas.Chunk` - Ecto schema for document chunks with pgvector embeddings
- `PortfolioIndex.Schemas.Queries` - Query helpers for schema operations
- Database migration for document management tables with pgvector support
```

## Verification Checklist

- [ ] All schema files created in correct locations
- [ ] Migration file created with correct structure
- [ ] All tests pass
- [ ] No credo warnings
- [ ] No dialyzer errors
- [ ] Changelog updated
- [ ] Module documentation complete with @moduledoc and @doc
- [ ] Type specifications complete with @type and @spec

