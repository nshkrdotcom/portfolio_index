defmodule PortfolioIndex.Adapters.DocumentStore.Postgres do
  @moduledoc """
  PostgreSQL document store adapter.

  Implements the `PortfolioCore.Ports.DocumentStore` behaviour.

  ## Features

  - Document CRUD operations
  - Content-addressable storage via SHA256 hashing
  - Metadata-based search
  - Namespace isolation via store_id

  ## Example

      {:ok, doc} = Postgres.store("my_store", "doc_1", "Hello, world!", %{author: "user"})
      {:ok, doc} = Postgres.get("my_store", "doc_1")
  """

  @behaviour PortfolioCore.Ports.DocumentStore

  alias PortfolioIndex.Repo
  require Logger

  @impl true
  def store(store_id, doc_id, content, metadata) do
    content_hash = hash_content(content)
    now = DateTime.utc_now()

    sql = """
    INSERT INTO documents (id, store_id, content, content_hash, metadata, inserted_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
    ON CONFLICT (store_id, id) DO UPDATE SET
      content = EXCLUDED.content,
      content_hash = EXCLUDED.content_hash,
      metadata = EXCLUDED.metadata,
      updated_at = EXCLUDED.updated_at
    RETURNING id, store_id, content, metadata, inserted_at, updated_at
    """

    params = [doc_id, store_id, content, content_hash, metadata, now, now]

    case Repo.query(sql, params) do
      {:ok, %Postgrex.Result{rows: [[id, _store_id, content, metadata, created_at, updated_at]]}} ->
        {:ok,
         %{
           id: id,
           content: content,
           metadata: metadata || %{},
           created_at: created_at,
           updated_at: updated_at
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get(store_id, doc_id) do
    sql = """
    SELECT id, content, metadata, inserted_at, updated_at
    FROM documents
    WHERE store_id = $1 AND id = $2
    """

    case Repo.query(sql, [store_id, doc_id]) do
      {:ok, %Postgrex.Result{rows: [[id, content, metadata, created_at, updated_at]]}} ->
        {:ok,
         %{
           id: id,
           content: content,
           metadata: metadata || %{},
           created_at: created_at,
           updated_at: updated_at
         }}

      {:ok, %Postgrex.Result{rows: []}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete(store_id, doc_id) do
    sql = "DELETE FROM documents WHERE store_id = $1 AND id = $2"

    case Repo.query(sql, [store_id, doc_id]) do
      {:ok, %Postgrex.Result{num_rows: 1}} -> :ok
      {:ok, %Postgrex.Result{num_rows: 0}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list(store_id, opts) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    order_by = Keyword.get(opts, :order_by, :updated_at)
    order_dir = Keyword.get(opts, :order_dir, :desc)

    order_clause = "ORDER BY #{order_field(order_by)} #{order_direction(order_dir)}"

    sql = """
    SELECT id, content, metadata, inserted_at, updated_at
    FROM documents
    WHERE store_id = $1
    #{order_clause}
    LIMIT $2 OFFSET $3
    """

    case Repo.query(sql, [store_id, limit, offset]) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        docs =
          Enum.map(rows, fn [id, content, metadata, created_at, updated_at] ->
            %{
              id: id,
              content: content,
              metadata: metadata || %{},
              created_at: created_at,
              updated_at: updated_at
            }
          end)

        {:ok, docs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def search_metadata(store_id, query) when is_map(query) do
    {where_clauses, params, _} =
      Enum.reduce(query, {[], [store_id], 2}, fn {key, value}, {clauses, params, idx} ->
        clause = "metadata->>$#{idx} = $#{idx + 1}"
        {[clause | clauses], params ++ [to_string(key), to_string(value)], idx + 2}
      end)

    where =
      if Enum.empty?(where_clauses) do
        "WHERE store_id = $1"
      else
        "WHERE store_id = $1 AND " <> Enum.join(Enum.reverse(where_clauses), " AND ")
      end

    sql = """
    SELECT id, content, metadata, inserted_at, updated_at
    FROM documents
    #{where}
    ORDER BY updated_at DESC
    LIMIT 100
    """

    case Repo.query(sql, params) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        docs =
          Enum.map(rows, fn [id, content, metadata, created_at, updated_at] ->
            %{
              id: id,
              content: content,
              metadata: metadata || %{},
              created_at: created_at,
              updated_at: updated_at
            }
          end)

        {:ok, docs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Additional helper functions

  @doc """
  Check if a document exists by content hash (for deduplication).
  """
  def exists_by_hash?(store_id, content) do
    content_hash = hash_content(content)

    sql = """
    SELECT EXISTS (
      SELECT 1 FROM documents
      WHERE store_id = $1 AND content_hash = $2
    )
    """

    case Repo.query(sql, [store_id, content_hash]) do
      {:ok, %Postgrex.Result{rows: [[true]]}} -> true
      _ -> false
    end
  end

  @doc """
  Get a document by content hash.
  """
  def get_by_hash(store_id, content) do
    content_hash = hash_content(content)

    sql = """
    SELECT id, content, metadata, inserted_at, updated_at
    FROM documents
    WHERE store_id = $1 AND content_hash = $2
    LIMIT 1
    """

    case Repo.query(sql, [store_id, content_hash]) do
      {:ok, %Postgrex.Result{rows: [[id, content, metadata, created_at, updated_at]]}} ->
        {:ok,
         %{
           id: id,
           content: content,
           metadata: metadata || %{},
           created_at: created_at,
           updated_at: updated_at
         }}

      {:ok, %Postgrex.Result{rows: []}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp hash_content(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp order_field(:updated_at), do: "updated_at"
  defp order_field(:created_at), do: "inserted_at"
  defp order_field(:id), do: "id"
  defp order_field(field), do: to_string(field)

  defp order_direction(:asc), do: "ASC"
  defp order_direction(:desc), do: "DESC"
  defp order_direction(_), do: "DESC"
end
