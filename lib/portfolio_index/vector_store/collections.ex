defmodule PortfolioIndex.VectorStore.Collections do
  @moduledoc """
  Collection-based organization for vector store operations.
  Provides logical grouping of vectors without separate physical stores.

  Collections are implemented using metadata filtering on the underlying
  vector store. Each vector is tagged with a `collection` field in its
  metadata, and searches can be scoped to specific collections.

  ## Usage

      # Insert to a collection
      Collections.insert_to_collection("products", "prod_1", embedding, %{name: "Widget"})

      # Search within a collection
      {:ok, results} = Collections.search_collection("products", query_embedding, limit: 10)

      # List all collections
      {:ok, collections} = Collections.list_collections()

      # Get collection statistics
      {:ok, stats} = Collections.collection_stats("products")

  ## Configuration

  By default, operations use the pgvector backend. You can specify a different
  backend via the `:backend` option:

      Collections.search_collection("products", embedding, backend: :memory)

  """

  alias PortfolioIndex.Adapters.VectorStore.Pgvector
  alias PortfolioIndex.Repo

  @collection_key "collection"

  @doc """
  Search within a specific collection.

  ## Options

    * `:limit` - Maximum number of results (default: 10)
    * `:min_score` - Minimum similarity score
    * `:index_id` - Vector store index ID (default: "default")
    * `:include_vector` - Whether to include vectors in results

  """
  @spec search_collection(String.t(), [float()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def search_collection(collection, embedding, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, "default")
    limit = Keyword.get(opts, :limit, 10)

    # Build filter for collection
    filter = Map.put(Keyword.get(opts, :filter, %{}), @collection_key, collection)

    opts =
      opts
      |> Keyword.put(:filter, filter)
      |> Keyword.delete(:index_id)

    Pgvector.search(index_id, embedding, limit, opts)
  end

  @doc """
  Insert into a specific collection.

  The collection name is automatically added to the metadata.

  ## Options

    * `:index_id` - Vector store index ID (default: "default")

  """
  @spec insert_to_collection(String.t(), String.t(), [float()], map(), keyword()) ::
          :ok | {:error, term()}
  def insert_to_collection(collection, id, embedding, metadata, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, "default")

    # Add collection to metadata
    metadata = Map.put(metadata, @collection_key, collection)

    Pgvector.store(index_id, id, embedding, metadata)
  end

  @doc """
  List all collections.

  Returns a list of unique collection names that have vectors stored.

  ## Options

    * `:index_id` - Vector store index ID (default: "default")

  """
  @spec list_collections(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def list_collections(opts \\ []) do
    index_id = Keyword.get(opts, :index_id, "default")
    table_name = table_name(index_id)

    sql = """
    SELECT DISTINCT metadata->>'#{@collection_key}' as collection
    FROM #{table_name}
    WHERE metadata->>'#{@collection_key}' IS NOT NULL
    ORDER BY collection
    """

    case Repo.query(sql, []) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        collections = Enum.map(rows, fn [collection] -> collection end)
        {:ok, collections}

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get collection statistics.

  ## Options

    * `:index_id` - Vector store index ID (default: "default")

  """
  @spec collection_stats(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def collection_stats(collection, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, "default")
    table_name = table_name(index_id)

    sql = """
    SELECT COUNT(*) as count
    FROM #{table_name}
    WHERE metadata->>'#{@collection_key}' = $1
    """

    case Repo.query(sql, [collection]) do
      {:ok, %Postgrex.Result{rows: [[count]]}} ->
        {:ok, %{collection: collection, count: count}}

      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
        {:ok, %{collection: collection, count: 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete all vectors in a collection.

  ## Options

    * `:index_id` - Vector store index ID (default: "default")

  """
  @spec clear_collection(String.t(), keyword()) :: :ok | {:error, term()}
  def clear_collection(collection, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, "default")
    table_name = table_name(index_id)

    sql = """
    DELETE FROM #{table_name}
    WHERE metadata->>'#{@collection_key}' = $1
    """

    case Repo.query(sql, [collection]) do
      {:ok, _} -> :ok
      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if collection exists.

  Returns true if the collection has at least one vector.

  ## Options

    * `:index_id` - Vector store index ID (default: "default")

  """
  @spec collection_exists?(String.t(), keyword()) :: boolean()
  def collection_exists?(collection, opts \\ []) do
    case collection_stats(collection, opts) do
      {:ok, %{count: count}} -> count > 0
      {:error, _} -> false
    end
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp table_name(index_id) do
    safe_id =
      index_id
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.downcase()

    "vectors_#{safe_id}"
  end
end
