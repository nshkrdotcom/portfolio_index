defmodule PortfolioIndex.Adapters.VectorStore.MemoryTest do
  use ExUnit.Case, async: true

  # Tag for CI exclusion - HNSWLib NIFs may timeout on some runners
  @moduletag :memory

  alias PortfolioIndex.Adapters.VectorStore.Memory
  alias PortfolioIndex.Fixtures

  @default_dimensions 384

  setup do
    # Start a fresh Memory server for each test
    {:ok, pid} = Memory.start_link(name: nil, dimensions: @default_dimensions)
    %{pid: pid}
  end

  # =============================================================================
  # Module Attributes
  # =============================================================================

  describe "module attributes" do
    test "implements VectorStore behaviour" do
      behaviours = Memory.__info__(:attributes)[:behaviour] || []
      assert PortfolioCore.Ports.VectorStore in behaviours
    end
  end

  # =============================================================================
  # GenServer Lifecycle
  # =============================================================================

  describe "start_link/1" do
    test "starts with default options" do
      {:ok, pid} = Memory.start_link(name: nil)
      assert Process.alive?(pid)
    end

    test "starts with custom name" do
      {:ok, _pid} = Memory.start_link(name: :test_memory_store)
      assert Process.whereis(:test_memory_store) != nil
    end

    test "starts with custom dimensions" do
      {:ok, pid} = Memory.start_link(name: nil, dimensions: 768)
      stats = Memory.stats(pid)
      assert stats.dimensions == 768
    end

    test "starts with custom max_elements" do
      {:ok, pid} = Memory.start_link(name: nil, max_elements: 5_000)
      stats = Memory.stats(pid)
      assert stats.max_elements == 5_000
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec" do
      spec = Memory.child_spec(name: :test_child_spec)
      assert spec.id == Memory
      assert spec.start == {Memory, :start_link, [[name: :test_child_spec]]}
    end
  end

  # =============================================================================
  # insert/5
  # =============================================================================

  describe "insert/5" do
    test "inserts a vector with metadata", %{pid: pid} do
      embedding = Fixtures.random_normalized_vector(@default_dimensions)
      metadata = %{content: "hello world", source: "/path/to/file.md"}

      assert :ok = Memory.insert(pid, "doc_1", embedding, metadata)
    end

    test "updates existing vector on duplicate id", %{pid: pid} do
      embedding1 = Fixtures.random_normalized_vector(@default_dimensions)
      embedding2 = Fixtures.random_normalized_vector(@default_dimensions)

      :ok = Memory.insert(pid, "doc_1", embedding1, %{version: 1})
      :ok = Memory.insert(pid, "doc_1", embedding2, %{version: 2})

      {:ok, result} = Memory.get(pid, "doc_1")
      assert result.metadata.version == 2
    end

    test "returns error for dimension mismatch", %{pid: pid} do
      wrong_embedding = Fixtures.random_normalized_vector(@default_dimensions + 100)

      assert {:error, {:dimension_mismatch, _}} =
               Memory.insert(pid, "doc_1", wrong_embedding, %{})
    end
  end

  # =============================================================================
  # insert_batch/3
  # =============================================================================

  describe "insert_batch/3" do
    test "inserts multiple vectors", %{pid: pid} do
      items =
        for i <- 1..5 do
          {
            "doc_#{i}",
            Fixtures.random_normalized_vector(@default_dimensions),
            %{content: "Document #{i}"}
          }
        end

      assert {:ok, 5} = Memory.insert_batch(pid, items)

      stats = Memory.stats(pid)
      assert stats.count == 5
    end

    test "returns error if any dimension mismatches", %{pid: pid} do
      items = [
        {"doc_1", Fixtures.random_normalized_vector(@default_dimensions), %{}},
        {"doc_2", Fixtures.random_normalized_vector(@default_dimensions + 50), %{}},
        {"doc_3", Fixtures.random_normalized_vector(@default_dimensions), %{}}
      ]

      assert {:error, {:dimension_mismatch, _}} = Memory.insert_batch(pid, items)
    end

    test "handles empty batch", %{pid: pid} do
      assert {:ok, 0} = Memory.insert_batch(pid, [])
    end
  end

  # =============================================================================
  # search/4
  # =============================================================================

  describe "search/4" do
    test "returns empty list for empty store", %{pid: pid} do
      query = Fixtures.random_normalized_vector(@default_dimensions)

      assert {:ok, []} = Memory.search(pid, query, limit: 10)
    end

    test "finds stored vectors", %{pid: pid} do
      # Store some vectors with known similarity
      base = normalize([1.0, 0.0, 0.0] ++ List.duplicate(0.0, @default_dimensions - 3))
      similar = normalize([0.9, 0.1, 0.0] ++ List.duplicate(0.0, @default_dimensions - 3))
      dissimilar = normalize([0.0, 1.0, 0.0] ++ List.duplicate(0.0, @default_dimensions - 3))

      :ok = Memory.insert(pid, "base", base, %{type: "base"})
      :ok = Memory.insert(pid, "similar", similar, %{type: "similar"})
      :ok = Memory.insert(pid, "dissimilar", dissimilar, %{type: "dissimilar"})

      {:ok, results} = Memory.search(pid, base, limit: 2)

      assert length(results) == 2
      ids = Enum.map(results, & &1.id)
      assert "base" in ids
      assert "similar" in ids
    end

    test "respects limit option", %{pid: pid} do
      for i <- 1..10 do
        embedding = Fixtures.random_normalized_vector(@default_dimensions)
        :ok = Memory.insert(pid, "doc_#{i}", embedding, %{})
      end

      {:ok, results} =
        Memory.search(pid, Fixtures.random_normalized_vector(@default_dimensions), limit: 5)

      assert length(results) == 5
    end

    test "returns results with score", %{pid: pid} do
      embedding = normalize([1.0] ++ List.duplicate(0.0, @default_dimensions - 1))
      :ok = Memory.insert(pid, "doc_1", embedding, %{content: "hello"})

      {:ok, [result]} = Memory.search(pid, embedding, limit: 1)

      assert result.id == "doc_1"
      assert result.metadata == %{content: "hello"}
      # Score should be close to 1.0 for identical vectors
      assert result.score > 0.99
    end

    test "applies min_score threshold", %{pid: pid} do
      high = normalize([1.0, 0.0, 0.0] ++ List.duplicate(0.0, @default_dimensions - 3))
      low = normalize([0.0, 1.0, 0.0] ++ List.duplicate(0.0, @default_dimensions - 3))

      :ok = Memory.insert(pid, "high", high, %{})
      :ok = Memory.insert(pid, "low", low, %{})

      {:ok, results} = Memory.search(pid, high, limit: 10, min_score: 0.8)

      # Only "high" should pass the threshold
      assert length(results) == 1
      assert hd(results).id == "high"
    end

    test "excludes soft-deleted vectors", %{pid: pid} do
      embedding = Fixtures.random_normalized_vector(@default_dimensions)
      :ok = Memory.insert(pid, "deleted", embedding, %{})
      :ok = Memory.delete(pid, "deleted", [])

      {:ok, results} = Memory.search(pid, embedding, limit: 10)

      assert results == []
    end
  end

  # =============================================================================
  # get/3
  # =============================================================================

  describe "get/3" do
    test "returns stored vector by id", %{pid: pid} do
      embedding = Fixtures.random_normalized_vector(@default_dimensions)
      :ok = Memory.insert(pid, "doc_1", embedding, %{content: "hello"})

      {:ok, result} = Memory.get(pid, "doc_1")

      assert result.id == "doc_1"
      assert result.metadata == %{content: "hello"}
      assert length(result.vector) == @default_dimensions
    end

    test "returns error for non-existent id", %{pid: pid} do
      assert {:error, :not_found} = Memory.get(pid, "non_existent")
    end

    test "returns error for deleted id", %{pid: pid} do
      embedding = Fixtures.random_normalized_vector(@default_dimensions)
      :ok = Memory.insert(pid, "deleted", embedding, %{})
      :ok = Memory.delete(pid, "deleted", [])

      assert {:error, :not_found} = Memory.get(pid, "deleted")
    end
  end

  # =============================================================================
  # delete/3
  # =============================================================================

  describe "delete/3" do
    test "soft deletes a vector by id", %{pid: pid} do
      embedding = Fixtures.random_normalized_vector(@default_dimensions)
      :ok = Memory.insert(pid, "to_delete", embedding, %{})

      stats_before = Memory.stats(pid)
      assert stats_before.count == 1

      :ok = Memory.delete(pid, "to_delete", [])

      stats_after = Memory.stats(pid)
      # Count reflects live vectors only
      assert stats_after.count == 0
    end

    test "returns error for non-existent id", %{pid: pid} do
      assert {:error, :not_found} = Memory.delete(pid, "non_existent", [])
    end

    test "returns error for already deleted id", %{pid: pid} do
      embedding = Fixtures.random_normalized_vector(@default_dimensions)
      :ok = Memory.insert(pid, "doc_1", embedding, %{})
      :ok = Memory.delete(pid, "doc_1", [])

      assert {:error, :not_found} = Memory.delete(pid, "doc_1", [])
    end
  end

  # =============================================================================
  # save/2 and load/2
  # =============================================================================

  describe "save/2 and load/2" do
    @tag :tmp_dir
    test "persists and restores index", %{pid: pid, tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test_index")

      # Insert some vectors
      for i <- 1..3 do
        embedding = Fixtures.random_normalized_vector(@default_dimensions)
        :ok = Memory.insert(pid, "doc_#{i}", embedding, %{n: i})
      end

      # Save - creates path.hnsw and path.meta files
      assert :ok = Memory.save(pid, path)
      assert File.exists?(path <> ".hnsw")
      assert File.exists?(path <> ".meta")

      # Start a new server and load
      {:ok, pid2} = Memory.start_link(name: nil, dimensions: @default_dimensions)
      assert :ok = Memory.load(pid2, path)

      stats = Memory.stats(pid2)
      assert stats.count == 3

      {:ok, result} = Memory.get(pid2, "doc_1")
      assert result.metadata.n == 1
    end

    test "returns error for non-existent file", %{pid: pid} do
      assert {:error, :enoent} = Memory.load(pid, "/nonexistent/path.bin")
    end
  end

  # =============================================================================
  # stats/1
  # =============================================================================

  describe "stats/1" do
    test "returns index statistics", %{pid: pid} do
      for i <- 1..5 do
        embedding = Fixtures.random_normalized_vector(@default_dimensions)
        :ok = Memory.insert(pid, "doc_#{i}", embedding, %{})
      end

      stats = Memory.stats(pid)

      assert stats.count == 5
      assert stats.dimensions == @default_dimensions
      assert stats.max_elements == 10_000
      assert stats.deleted_count == 0
    end

    test "tracks deleted count", %{pid: pid} do
      for i <- 1..3 do
        embedding = Fixtures.random_normalized_vector(@default_dimensions)
        :ok = Memory.insert(pid, "doc_#{i}", embedding, %{})
      end

      :ok = Memory.delete(pid, "doc_1", [])

      stats = Memory.stats(pid)
      assert stats.count == 2
      assert stats.deleted_count == 1
    end
  end

  # =============================================================================
  # clear/1
  # =============================================================================

  describe "clear/1" do
    test "removes all vectors", %{pid: pid} do
      for i <- 1..5 do
        embedding = Fixtures.random_normalized_vector(@default_dimensions)
        :ok = Memory.insert(pid, "doc_#{i}", embedding, %{})
      end

      assert :ok = Memory.clear(pid)

      stats = Memory.stats(pid)
      assert stats.count == 0
      assert stats.deleted_count == 0
    end
  end

  # =============================================================================
  # Concurrent Access
  # =============================================================================

  describe "concurrent access" do
    test "handles concurrent inserts", %{pid: pid} do
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            embedding = Fixtures.random_normalized_vector(@default_dimensions)
            Memory.insert(pid, "doc_#{i}", embedding, %{n: i})
          end)
        end

      results = Task.await_many(tasks, 5_000)

      assert Enum.all?(results, &(&1 == :ok))

      stats = Memory.stats(pid)
      assert stats.count == 20
    end

    test "handles concurrent searches", %{pid: pid} do
      # Insert some vectors first
      for i <- 1..10 do
        embedding = Fixtures.random_normalized_vector(@default_dimensions)
        :ok = Memory.insert(pid, "doc_#{i}", embedding, %{})
      end

      # Concurrent searches
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            query = Fixtures.random_normalized_vector(@default_dimensions)
            Memory.search(pid, query, limit: 5)
          end)
        end

      results = Task.await_many(tasks, 5_000)

      assert Enum.all?(results, fn {:ok, r} -> length(r) == 5 end)
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp normalize(vector) do
    magnitude = :math.sqrt(Enum.reduce(vector, 0.0, fn x, sum -> sum + x * x end))

    if magnitude > 0 do
      Enum.map(vector, &(&1 / magnitude))
    else
      vector
    end
  end
end
