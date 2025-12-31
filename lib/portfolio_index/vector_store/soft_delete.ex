defmodule PortfolioIndex.VectorStore.SoftDelete do
  @moduledoc """
  Soft deletion utilities for vector store items.
  Marks items as deleted without removing from storage.

  Soft deletion is useful for:
  - Recovering accidentally deleted items
  - Maintaining audit trails
  - Gradual cleanup of old data
  - Implementing trash/recycle bin functionality

  ## Usage

      # Soft delete an item
      :ok = SoftDelete.soft_delete(Repo, "doc_1", index_id: "my_index")

      # Restore a soft-deleted item
      :ok = SoftDelete.restore(Repo, "doc_1", index_id: "my_index")

      # Permanently delete items older than 30 days
      {:ok, count} = SoftDelete.purge_deleted(Repo, index_id: "my_index", older_than_seconds: 30 * 24 * 3600)

  ## Schema Requirements

  The vector store table must have a `deleted_at` column:

      ALTER TABLE vectors_my_index
      ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

  ## Search Integration

  Searches automatically exclude soft-deleted items unless `include_deleted: true`
  is specified in the search options.
  """

  @doc """
  Soft delete an item by ID.

  Sets the `deleted_at` timestamp to the current time.

  ## Options

    * `:index_id` - Vector store index ID (required)

  """
  @spec soft_delete(Ecto.Repo.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def soft_delete(repo, id, opts \\ []) do
    index_id = Keyword.fetch!(opts, :index_id)
    table_name = table_name(index_id)

    sql = """
    UPDATE #{table_name}
    SET deleted_at = NOW()
    WHERE id = $1 AND deleted_at IS NULL
    """

    case repo.query(sql, [id]) do
      {:ok, %Postgrex.Result{num_rows: 1}} -> :ok
      {:ok, %Postgrex.Result{num_rows: 0}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Soft delete items matching filter.

  ## Parameters

    * `repo` - Ecto repository
    * `filters` - Keyword list of metadata filters (e.g., `[category: "old"]`)

  ## Options

    * `:index_id` - Vector store index ID (required)

  ## Returns

    * `{:ok, count}` - Number of items soft deleted
    * `{:error, reason}` - On failure

  """
  @spec soft_delete_where(Ecto.Repo.t(), keyword(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def soft_delete_where(repo, filters, opts \\ []) do
    index_id = Keyword.fetch!(opts, :index_id)
    table_name = table_name(index_id)

    {where_clause, params} = build_filter_clause(filters)

    sql = """
    UPDATE #{table_name}
    SET deleted_at = NOW()
    WHERE deleted_at IS NULL#{where_clause}
    """

    case repo.query(sql, params) do
      {:ok, %Postgrex.Result{num_rows: count}} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Restore a soft-deleted item.

  Clears the `deleted_at` timestamp.

  ## Options

    * `:index_id` - Vector store index ID (required)

  """
  @spec restore(Ecto.Repo.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def restore(repo, id, opts \\ []) do
    index_id = Keyword.fetch!(opts, :index_id)
    table_name = table_name(index_id)

    sql = """
    UPDATE #{table_name}
    SET deleted_at = NULL
    WHERE id = $1 AND deleted_at IS NOT NULL
    """

    case repo.query(sql, [id]) do
      {:ok, %Postgrex.Result{num_rows: 1}} -> :ok
      {:ok, %Postgrex.Result{num_rows: 0}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Permanently delete soft-deleted items older than threshold.

  ## Options

    * `:index_id` - Vector store index ID (required)
    * `:older_than_seconds` - Only purge items deleted more than N seconds ago

  ## Returns

    * `{:ok, count}` - Number of items permanently deleted
    * `{:error, reason}` - On failure

  """
  @spec purge_deleted(Ecto.Repo.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def purge_deleted(repo, opts \\ []) do
    index_id = Keyword.fetch!(opts, :index_id)
    older_than = Keyword.get(opts, :older_than_seconds)
    table_name = table_name(index_id)

    {where_clause, params} =
      if older_than do
        {" AND deleted_at < NOW() - INTERVAL '#{older_than} seconds'", []}
      else
        {"", []}
      end

    sql = """
    DELETE FROM #{table_name}
    WHERE deleted_at IS NOT NULL#{where_clause}
    """

    case repo.query(sql, params) do
      {:ok, %Postgrex.Result{num_rows: count}} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Count soft-deleted items.

  ## Options

    * `:index_id` - Vector store index ID (required)

  """
  @spec count_deleted(Ecto.Repo.t(), keyword()) :: non_neg_integer()
  def count_deleted(repo, opts \\ []) do
    index_id = Keyword.fetch!(opts, :index_id)
    table_name = table_name(index_id)

    sql = """
    SELECT COUNT(*)
    FROM #{table_name}
    WHERE deleted_at IS NOT NULL
    """

    case repo.query(sql, []) do
      {:ok, %Postgrex.Result{rows: [[count]]}} -> count
      {:error, _} -> 0
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

  defp build_filter_clause([]), do: {"", []}

  defp build_filter_clause(filters) do
    {clauses, params, _} =
      Enum.reduce(filters, {[], [], 1}, fn {key, value}, {clauses, params, idx} ->
        clause = " AND metadata->>'#{key}' = $#{idx}"
        {[clause | clauses], params ++ [to_string(value)], idx + 1}
      end)

    {Enum.reverse(clauses) |> Enum.join(), params}
  end
end
