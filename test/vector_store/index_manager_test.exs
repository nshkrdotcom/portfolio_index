defmodule PortfolioIndex.VectorStore.IndexManagerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Adapters.VectorStore.Memory
  alias PortfolioIndex.Adapters.VectorStore.Pgvector
  alias PortfolioIndex.VectorStore.IndexManager

  # =============================================================================
  # Unit Tests
  # =============================================================================

  describe "ensure_index/2 with memory backend" do
    @tag :memory
    test "initializes memory store" do
      {:ok, pid} = Memory.start_link(name: nil, dimensions: 384)

      assert :ok = IndexManager.ensure_index(Memory, store: pid, dimensions: 384)
    end
  end

  # =============================================================================
  # Integration Tests
  # =============================================================================

  setup tags do
    if tags[:integration] do
      pid = Sandbox.start_owner!(PortfolioIndex.Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    :ok
  end

  describe "ensure_index/2 with pgvector backend" do
    @tag :integration
    test "creates index if not exists" do
      index_id = unique_index_id()

      assert :ok =
               IndexManager.ensure_index(Pgvector,
                 index_id: index_id,
                 dimensions: 384,
                 metric: :cosine
               )

      assert IndexManager.index_exists?(Pgvector, index_id: index_id) == true

      # Cleanup
      Pgvector.delete_index(index_id)
    end

    @tag :integration
    test "returns ok if index already exists" do
      index_id = unique_index_id()

      # Create first time
      :ok = Pgvector.create_index(index_id, %{dimensions: 384, metric: :cosine})

      # Ensure again should succeed
      assert :ok =
               IndexManager.ensure_index(Pgvector,
                 index_id: index_id,
                 dimensions: 384,
                 metric: :cosine
               )

      Pgvector.delete_index(index_id)
    end
  end

  describe "index_exists?/2" do
    @tag :integration
    test "returns true for existing index" do
      index_id = unique_index_id()
      :ok = Pgvector.create_index(index_id, %{dimensions: 384})

      assert IndexManager.index_exists?(Pgvector, index_id: index_id) == true

      Pgvector.delete_index(index_id)
    end

    @tag :integration
    test "returns false for non-existent index" do
      assert IndexManager.index_exists?(Pgvector,
               index_id: "nonexistent_#{System.unique_integer()}"
             ) ==
               false
    end
  end

  describe "index_stats/2" do
    @tag :integration
    test "returns stats for existing index" do
      index_id = unique_index_id()
      :ok = Pgvector.create_index(index_id, %{dimensions: 384, metric: :cosine})

      {:ok, stats} = IndexManager.index_stats(Pgvector, index_id: index_id)

      assert stats.count == 0
      assert stats.dimensions == 384
      assert stats.metric == :cosine

      Pgvector.delete_index(index_id)
    end

    @tag :integration
    test "returns error for non-existent index" do
      assert {:error, :not_found} =
               IndexManager.index_stats(Pgvector,
                 index_id: "nonexistent_#{System.unique_integer()}"
               )
    end
  end

  describe "drop_index/2" do
    @tag :integration
    test "drops existing index" do
      index_id = unique_index_id()
      :ok = Pgvector.create_index(index_id, %{dimensions: 384})

      assert :ok = IndexManager.drop_index(Pgvector, index_id: index_id)
      assert IndexManager.index_exists?(Pgvector, index_id: index_id) == false
    end
  end

  describe "rebuild_index/2" do
    @tag :integration
    test "rebuilds existing index" do
      index_id = unique_index_id()

      :ok =
        Pgvector.create_index(index_id, %{
          dimensions: 384,
          metric: :cosine,
          index_type: :hnsw
        })

      # Store some vectors
      for i <- 1..5 do
        vector = for _ <- 1..384, do: :rand.uniform()
        :ok = Pgvector.store(index_id, "doc_#{i}", vector, %{})
      end

      # Rebuild
      assert :ok = IndexManager.rebuild_index(Pgvector, index_id: index_id)

      # Verify data still exists
      {:ok, stats} = IndexManager.index_stats(Pgvector, index_id: index_id)
      assert stats.count == 5

      Pgvector.delete_index(index_id)
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp unique_index_id do
    "test_idx_#{System.unique_integer([:positive])}"
  end
end
