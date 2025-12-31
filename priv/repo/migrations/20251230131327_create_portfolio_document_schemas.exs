defmodule PortfolioIndex.Repo.Migrations.CreatePortfolioDocumentSchemas do
  @moduledoc """
  Creates tables for document management with pgvector support.

  Tables:
    - portfolio_collections: Groups of related documents
    - portfolio_documents: Ingested documents with status tracking
    - portfolio_chunks: Document chunks with vector embeddings
  """

  use Ecto.Migration

  def up do
    # Enable pgvector extension (may already exist from previous migrations)
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    # Collections table
    create table(:portfolio_collections, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:metadata, :map, default: %{})

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:portfolio_collections, [:name]))

    # Documents table
    create table(:portfolio_documents, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:source_id, :string)
      add(:content_hash, :string)
      add(:title, :string)
      add(:source_path, :string)
      add(:metadata, :map, default: %{})
      add(:status, :string, default: "pending")
      add(:error_message, :text)
      add(:chunk_count, :integer, default: 0)

      add(
        :collection_id,
        references(:portfolio_collections, type: :binary_id, on_delete: :nilify_all)
      )

      timestamps(type: :utc_datetime)
    end

    create(index(:portfolio_documents, [:collection_id]))
    create(index(:portfolio_documents, [:source_id]))
    create(index(:portfolio_documents, [:status]))
    create(index(:portfolio_documents, [:content_hash]))

    # Chunks table with vector column
    # Note: Vector dimension 384 is for bge-small embedding model
    # For other models, consider making this configurable or using a larger dimension
    create table(:portfolio_chunks, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:content, :text, null: false)
      add(:chunk_index, :integer, null: false)
      add(:token_count, :integer)
      add(:start_char, :integer)
      add(:end_char, :integer)
      add(:metadata, :map, default: %{})

      add(
        :document_id,
        references(:portfolio_documents, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime)
    end

    # Add vector column separately since Ecto.Migration doesn't support vector type directly
    execute("ALTER TABLE portfolio_chunks ADD COLUMN embedding vector(384)")

    create(index(:portfolio_chunks, [:document_id]))

    # HNSW index for fast similarity search with cosine distance
    execute("""
    CREATE INDEX portfolio_chunks_embedding_idx ON portfolio_chunks
    USING hnsw (embedding vector_cosine_ops)
    """)
  end

  def down do
    drop(table(:portfolio_chunks))
    drop(table(:portfolio_documents))
    drop(table(:portfolio_collections))
  end
end
