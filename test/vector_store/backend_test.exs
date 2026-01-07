defmodule PortfolioIndex.VectorStore.BackendTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Adapters.VectorStore.Memory
  alias PortfolioIndex.Adapters.VectorStore.Pgvector
  alias PortfolioIndex.Fixtures
  alias PortfolioIndex.VectorStore.Backend

  # =============================================================================
  # resolve/1
  # =============================================================================

  describe "resolve/1" do
    test "resolves :memory alias to Memory module" do
      {module, _opts} = Backend.resolve(:memory)
      assert module == Memory
    end

    test "resolves :pgvector alias to Pgvector module" do
      {module, _opts} = Backend.resolve(:pgvector)
      assert module == Pgvector
    end

    test "resolves module directly" do
      {module, _opts} = Backend.resolve(Memory)
      assert module == Memory
    end

    test "resolves tuple with module and options" do
      {module, opts} = Backend.resolve({Memory, name: :test})
      assert module == Memory
      assert opts[:name] == :test
    end

    test "resolves nil to default backend" do
      {module, _opts} = Backend.resolve(nil)
      # Default should be Pgvector (or whatever is configured)
      assert is_atom(module)
    end
  end

  # =============================================================================
  # default/0
  # =============================================================================

  describe "default/0" do
    test "returns configured default backend" do
      {module, _opts} = Backend.default()
      assert is_atom(module)
    end
  end

  # =============================================================================
  # Integration with Memory backend
  # =============================================================================

  @moduletag :memory

  describe "operations with memory backend" do
    @dimensions 384

    setup do
      {:ok, pid} = Memory.start_link(name: nil, dimensions: @dimensions)
      %{pid: pid, backend: {Memory, store: pid}}
    end

    test "search with backend option", %{backend: backend} do
      query = Fixtures.random_normalized_vector(@dimensions)

      {:ok, results} = Backend.search(query, limit: 5, backend: backend)

      assert is_list(results)
    end

    test "insert with backend option", %{pid: pid, backend: backend} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      :ok = Backend.insert("doc_1", embedding, %{content: "hello"}, backend: backend)

      {:ok, result} = Memory.get(pid, "doc_1")
      assert result.id == "doc_1"
    end

    test "insert_batch with backend option", %{pid: pid, backend: backend} do
      items =
        for i <- 1..3 do
          {"doc_#{i}", Fixtures.random_normalized_vector(@dimensions), %{n: i}}
        end

      {:ok, 3} = Backend.insert_batch(items, backend: backend)

      stats = Memory.stats(pid)
      assert stats.count == 3
    end

    test "delete with backend option", %{pid: pid, backend: backend} do
      embedding = Fixtures.random_normalized_vector(@dimensions)
      :ok = Memory.insert(pid, "to_delete", embedding, %{})

      :ok = Backend.delete("to_delete", backend: backend)

      assert {:error, :not_found} = Memory.get(pid, "to_delete")
    end

    test "get with backend option", %{pid: pid, backend: backend} do
      embedding = Fixtures.random_normalized_vector(@dimensions)
      :ok = Memory.insert(pid, "doc_1", embedding, %{content: "hello"})

      {:ok, result} = Backend.get("doc_1", backend: backend)

      assert result.id == "doc_1"
      assert result.metadata == %{content: "hello"}
    end
  end

  # =============================================================================
  # Backend switching
  # =============================================================================

  describe "backend switching" do
    @dimensions 384

    @tag :memory
    test "different backends can be used per call" do
      {:ok, pid1} = Memory.start_link(name: nil, dimensions: @dimensions)
      {:ok, pid2} = Memory.start_link(name: nil, dimensions: @dimensions)

      embedding = Fixtures.random_normalized_vector(@dimensions)

      # Insert to first backend
      :ok = Backend.insert("doc_1", embedding, %{store: 1}, backend: {Memory, store: pid1})

      # Insert to second backend
      :ok = Backend.insert("doc_2", embedding, %{store: 2}, backend: {Memory, store: pid2})

      # Each store should only have its own vector
      {:ok, result1} = Memory.get(pid1, "doc_1")
      assert result1.metadata.store == 1

      {:ok, result2} = Memory.get(pid2, "doc_2")
      assert result2.metadata.store == 2

      # Cross-store lookups should fail
      assert {:error, :not_found} = Memory.get(pid1, "doc_2")
      assert {:error, :not_found} = Memory.get(pid2, "doc_1")
    end
  end
end
