defmodule PortfolioIndex.VectorStore.SoftDeleteTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Adapters.VectorStore.Pgvector
  alias PortfolioIndex.Fixtures
  alias PortfolioIndex.Repo
  alias PortfolioIndex.VectorStore.SoftDelete

  @dimensions 384

  # =============================================================================
  # Integration Tests (require running PostgreSQL with pgvector)
  # Run with: mix test --include integration
  # =============================================================================

  setup tags do
    if tags[:integration] do
      pid = Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)

      # Create a test index with soft delete support
      index_id = unique_index_id()
      :ok = setup_test_index(index_id)
      on_exit(fn -> Pgvector.delete_index(index_id) end)

      %{index_id: index_id}
    else
      :ok
    end
  end

  describe "soft_delete/2" do
    @tag :integration
    test "marks item as deleted without removing", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)
      :ok = Pgvector.store(index_id, "to_delete", embedding, %{content: "hello"})

      # Soft delete
      assert :ok = SoftDelete.soft_delete(Repo, "to_delete", index_id: index_id)

      # Vector should still exist but be marked deleted
      {:ok, result} = get_vector(index_id, "to_delete")
      assert result.deleted_at != nil
    end

    @tag :integration
    test "returns error for non-existent id", %{index_id: index_id} do
      assert {:error, :not_found} =
               SoftDelete.soft_delete(Repo, "nonexistent", index_id: index_id)
    end
  end

  describe "soft_delete_where/2" do
    @tag :integration
    test "soft deletes items matching filter", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      # Insert items with different categories
      :ok = Pgvector.store(index_id, "cat_a_1", embedding, %{"category" => "a"})
      :ok = Pgvector.store(index_id, "cat_a_2", embedding, %{"category" => "a"})
      :ok = Pgvector.store(index_id, "cat_b_1", embedding, %{"category" => "b"})

      # Soft delete category a
      {:ok, count} =
        SoftDelete.soft_delete_where(Repo, [category: "a"], index_id: index_id)

      assert count == 2

      # Verify deletions
      {:ok, result_a1} = get_vector(index_id, "cat_a_1")
      assert result_a1.deleted_at != nil

      {:ok, result_b1} = get_vector(index_id, "cat_b_1")
      assert result_b1.deleted_at == nil
    end
  end

  describe "restore/2" do
    @tag :integration
    test "restores a soft-deleted item", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)
      :ok = Pgvector.store(index_id, "to_restore", embedding, %{})

      :ok = SoftDelete.soft_delete(Repo, "to_restore", index_id: index_id)
      :ok = SoftDelete.restore(Repo, "to_restore", index_id: index_id)

      {:ok, result} = get_vector(index_id, "to_restore")
      assert result.deleted_at == nil
    end

    @tag :integration
    test "returns error for non-existent id", %{index_id: index_id} do
      assert {:error, :not_found} = SoftDelete.restore(Repo, "nonexistent", index_id: index_id)
    end
  end

  describe "purge_deleted/2" do
    @tag :integration
    test "permanently deletes soft-deleted items", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      :ok = Pgvector.store(index_id, "keep", embedding, %{})
      :ok = Pgvector.store(index_id, "delete", embedding, %{})
      :ok = SoftDelete.soft_delete(Repo, "delete", index_id: index_id)

      # Purge all deleted items
      {:ok, count} = SoftDelete.purge_deleted(Repo, index_id: index_id)
      assert count == 1

      # Verify permanent deletion
      {:ok, result} = get_vector(index_id, "keep")
      assert result.id == "keep"

      {:error, :not_found} = get_vector(index_id, "delete")
    end

    @tag :integration
    test "respects older_than option", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      :ok = Pgvector.store(index_id, "recent", embedding, %{})
      :ok = SoftDelete.soft_delete(Repo, "recent", index_id: index_id)

      # Purge items older than 1 hour (none should be purged)
      {:ok, count} =
        SoftDelete.purge_deleted(Repo, index_id: index_id, older_than_seconds: 3600)

      assert count == 0

      # Item should still exist
      {:ok, result} = get_vector(index_id, "recent")
      assert result.deleted_at != nil
    end
  end

  describe "count_deleted/1" do
    @tag :integration
    test "counts soft-deleted items", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      for i <- 1..5 do
        :ok = Pgvector.store(index_id, "doc_#{i}", embedding, %{})
      end

      :ok = SoftDelete.soft_delete(Repo, "doc_1", index_id: index_id)
      :ok = SoftDelete.soft_delete(Repo, "doc_2", index_id: index_id)

      assert SoftDelete.count_deleted(Repo, index_id: index_id) == 2
    end

    @tag :integration
    test "returns zero for no deleted items", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)
      :ok = Pgvector.store(index_id, "live", embedding, %{})

      assert SoftDelete.count_deleted(Repo, index_id: index_id) == 0
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp unique_index_id do
    "test_sd_#{System.unique_integer([:positive])}"
  end

  defp setup_test_index(index_id) do
    # Create base table
    :ok = Pgvector.create_index(index_id, %{dimensions: @dimensions, metric: :cosine})

    # Add deleted_at column for soft delete support
    table_name = table_name(index_id)

    sql = """
    ALTER TABLE #{table_name}
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL
    """

    {:ok, _} = Repo.query(sql)
    :ok
  end

  defp table_name(index_id) do
    safe_id =
      index_id
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.downcase()

    "vectors_#{safe_id}"
  end

  defp get_vector(index_id, id) do
    table_name = table_name(index_id)

    sql = """
    SELECT id, metadata, deleted_at
    FROM #{table_name}
    WHERE id = $1
    """

    case Repo.query(sql, [id]) do
      {:ok, %Postgrex.Result{rows: [[id, metadata, deleted_at]]}} ->
        {:ok, %{id: id, metadata: metadata, deleted_at: deleted_at}}

      {:ok, %Postgrex.Result{rows: []}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
