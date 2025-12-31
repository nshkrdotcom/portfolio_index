defmodule PortfolioIndex.Schemas.Queries do
  @moduledoc """
  Query helpers for document management schemas.
  Provides common queries for collections, documents, and chunks.
  """

  import Ecto.Query
  alias PortfolioIndex.Schemas.{Chunk, Collection, Document}

  @doc """
  Get collection by name.

  ## Parameters
    - `repo` - The Ecto repo to use
    - `name` - Collection name to search for

  ## Returns
    - `Collection.t()` if found
    - `nil` if not found

  ## Examples

      iex> get_collection_by_name(Repo, "docs")
      %Collection{name: "docs", ...}

      iex> get_collection_by_name(Repo, "nonexistent")
      nil
  """
  @spec get_collection_by_name(Ecto.Repo.t(), String.t()) :: Collection.t() | nil
  def get_collection_by_name(repo, name) do
    repo.get_by(Collection, name: name)
  end

  @doc """
  Get or create collection by name.

  If the collection already exists, returns it without modification.
  If it doesn't exist, creates it with the provided attributes.

  ## Parameters
    - `repo` - The Ecto repo to use
    - `name` - Collection name
    - `attrs` - Additional attributes for creation (optional)

  ## Returns
    - `{:ok, Collection.t()}` on success
    - `{:error, term()}` on failure

  ## Examples

      iex> get_or_create_collection(Repo, "docs")
      {:ok, %Collection{name: "docs"}}

      iex> get_or_create_collection(Repo, "products", %{description: "Product docs"})
      {:ok, %Collection{name: "products", description: "Product docs"}}
  """
  @spec get_or_create_collection(Ecto.Repo.t(), String.t(), map()) ::
          {:ok, Collection.t()} | {:error, term()}
  def get_or_create_collection(repo, name, attrs \\ %{}) do
    case get_collection_by_name(repo, name) do
      nil ->
        attrs_with_name = Map.put(attrs, :name, name)

        %Collection{}
        |> Collection.changeset(attrs_with_name)
        |> Collection.validate_unique_name()
        |> repo.insert()

      collection ->
        {:ok, collection}
    end
  end

  @doc """
  List documents by status.

  ## Parameters
    - `repo` - The Ecto repo to use
    - `status` - Document status to filter by
    - `opts` - Query options:
      - `:limit` - Maximum number of documents to return
      - `:offset` - Number of documents to skip
      - `:collection_id` - Filter by collection

  ## Returns
    - List of documents matching the status

  ## Examples

      iex> list_documents_by_status(Repo, :pending, limit: 10)
      [%Document{status: :pending}, ...]

      iex> list_documents_by_status(Repo, :failed, collection_id: collection_id)
      [%Document{status: :failed, collection_id: ^collection_id}, ...]
  """
  @spec list_documents_by_status(Ecto.Repo.t(), Document.status(), keyword()) :: [Document.t()]
  def list_documents_by_status(repo, status, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    collection_id = Keyword.get(opts, :collection_id)

    query =
      Document
      |> where([d], d.status == ^status)
      |> limit(^limit)
      |> offset(^offset)
      |> order_by([d], desc: d.inserted_at)

    query =
      if collection_id do
        where(query, [d], d.collection_id == ^collection_id)
      else
        query
      end

    repo.all(query)
  end

  @doc """
  Get document with chunks preloaded.

  ## Parameters
    - `repo` - The Ecto repo to use
    - `document_id` - Document ID to fetch

  ## Returns
    - `Document.t()` with chunks preloaded if found
    - `nil` if not found

  ## Examples

      iex> get_document_with_chunks(Repo, document_id)
      %Document{chunks: [%Chunk{}, ...]}
  """
  @spec get_document_with_chunks(Ecto.Repo.t(), Ecto.UUID.t()) :: Document.t() | nil
  def get_document_with_chunks(repo, document_id) do
    Document
    |> where([d], d.id == ^document_id)
    |> preload(:chunks)
    |> repo.one()
  end

  @doc """
  Find chunks by similarity search.

  Performs a cosine similarity search using pgvector.

  ## Parameters
    - `repo` - The Ecto repo to use
    - `embedding` - Query embedding vector (list of floats)
    - `opts` - Search options:
      - `:limit` - Maximum number of results (default: 10)
      - `:min_score` - Minimum similarity score (0.0 to 1.0)
      - `:document_id` - Filter by document
      - `:collection_id` - Filter by collection

  ## Returns
    - List of chunks ordered by similarity (most similar first)

  ## Examples

      iex> similarity_search(Repo, embedding, limit: 5)
      [%Chunk{}, ...]

      iex> similarity_search(Repo, embedding, limit: 10, min_score: 0.8)
      [%Chunk{}, ...]
  """
  @spec similarity_search(Ecto.Repo.t(), [float()], keyword()) :: [Chunk.t()]
  def similarity_search(repo, embedding, opts \\ []) when is_list(embedding) do
    limit = Keyword.get(opts, :limit, 10)
    min_score = Keyword.get(opts, :min_score)
    document_id = Keyword.get(opts, :document_id)
    collection_id = Keyword.get(opts, :collection_id)

    pgvector = Pgvector.new(embedding)

    query =
      Chunk
      |> where([c], not is_nil(c.embedding))
      |> order_by([c], fragment("embedding <=> ?", ^pgvector))
      |> limit(^limit)

    query =
      if min_score do
        # Cosine similarity: 1 - distance
        where(query, [c], fragment("1 - (embedding <=> ?) >= ?", ^pgvector, ^min_score))
      else
        query
      end

    query =
      if document_id do
        where(query, [c], c.document_id == ^document_id)
      else
        query
      end

    query =
      if collection_id do
        query
        |> join(:inner, [c], d in Document, on: c.document_id == d.id)
        |> where([c, d], d.collection_id == ^collection_id)
      else
        query
      end

    repo.all(query)
  end

  @doc """
  Count chunks needing embedding.

  Returns the number of chunks that have no embedding vector set.

  ## Parameters
    - `repo` - The Ecto repo to use

  ## Returns
    - Non-negative integer count

  ## Examples

      iex> count_chunks_without_embedding(Repo)
      42
  """
  @spec count_chunks_without_embedding(Ecto.Repo.t()) :: non_neg_integer()
  def count_chunks_without_embedding(repo) do
    Chunk
    |> where([c], is_nil(c.embedding))
    |> repo.aggregate(:count, :id)
  end

  @doc """
  Get failed documents for retry.

  ## Parameters
    - `repo` - The Ecto repo to use
    - `opts` - Query options:
      - `:limit` - Maximum number of documents to return (default: 100)
      - `:collection_id` - Filter by collection

  ## Returns
    - List of failed documents

  ## Examples

      iex> get_failed_documents(Repo, limit: 10)
      [%Document{status: :failed}, ...]
  """
  @spec get_failed_documents(Ecto.Repo.t(), keyword()) :: [Document.t()]
  def get_failed_documents(repo, opts \\ []) do
    list_documents_by_status(repo, :failed, opts)
  end

  @doc """
  Mark document as deleted (soft delete).

  Updates the document status to `:deleted` without removing it from the database.
  Associated chunks remain in the database.

  ## Parameters
    - `repo` - The Ecto repo to use
    - `document` - The document to soft delete

  ## Returns
    - `{:ok, Document.t()}` on success
    - `{:error, term()}` on failure

  ## Examples

      iex> soft_delete_document(Repo, document)
      {:ok, %Document{status: :deleted}}
  """
  @spec soft_delete_document(Ecto.Repo.t(), Document.t()) ::
          {:ok, Document.t()} | {:error, term()}
  def soft_delete_document(repo, document) do
    document
    |> Document.status_changeset(:deleted)
    |> repo.update()
  end
end
