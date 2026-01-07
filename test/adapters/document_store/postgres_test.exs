defmodule PortfolioIndex.Adapters.DocumentStore.PostgresTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Adapters.DocumentStore.Postgres

  # Setup sandbox for integration tests
  setup tags do
    if tags[:integration] do
      pid = Sandbox.start_owner!(PortfolioIndex.Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    :ok
  end

  # =============================================================================
  # Unit Tests (no database required)
  # =============================================================================

  describe "module attributes" do
    test "implements DocumentStore behaviour" do
      behaviours = Postgres.__info__(:attributes)[:behaviour] || []
      assert PortfolioCore.Ports.DocumentStore in behaviours
    end
  end

  # =============================================================================
  # Integration Tests (require running PostgreSQL)
  # Run with: mix test --include integration
  # =============================================================================

  describe "store/4 integration" do
    @tag :integration
    test "stores a document with content and metadata" do
      store_id = unique_store_id()
      doc_id = "doc_#{System.unique_integer([:positive])}"

      {:ok, doc} =
        Postgres.store(store_id, doc_id, "Hello, world!", %{
          author: "test",
          format: "text"
        })

      assert doc.id == doc_id
      assert doc.content == "Hello, world!"
      assert doc.metadata["author"] == "test"
      assert doc.metadata["format"] == "text"
      assert doc.created_at != nil
      assert doc.updated_at != nil

      # Cleanup
      Postgres.delete(store_id, doc_id)
    end

    @tag :integration
    test "updates existing document (upsert)" do
      store_id = unique_store_id()
      doc_id = "doc_#{System.unique_integer([:positive])}"

      {:ok, _} = Postgres.store(store_id, doc_id, "Version 1", %{version: 1})
      {:ok, doc} = Postgres.store(store_id, doc_id, "Version 2", %{version: 2})

      assert doc.content == "Version 2"
      assert doc.metadata["version"] == 2

      Postgres.delete(store_id, doc_id)
    end
  end

  describe "get/2 integration" do
    @tag :integration
    test "retrieves an existing document" do
      store_id = unique_store_id()
      doc_id = "doc_#{System.unique_integer([:positive])}"

      {:ok, _} = Postgres.store(store_id, doc_id, "Test content", %{key: "value"})
      {:ok, doc} = Postgres.get(store_id, doc_id)

      assert doc.id == doc_id
      assert doc.content == "Test content"
      assert doc.metadata["key"] == "value"

      Postgres.delete(store_id, doc_id)
    end

    @tag :integration
    test "returns error for non-existent document" do
      store_id = unique_store_id()

      assert {:error, :not_found} = Postgres.get(store_id, "nonexistent")
    end
  end

  describe "delete/2 integration" do
    @tag :integration
    test "deletes an existing document" do
      store_id = unique_store_id()
      doc_id = "doc_#{System.unique_integer([:positive])}"

      {:ok, _} = Postgres.store(store_id, doc_id, "To delete", %{})

      assert :ok = Postgres.delete(store_id, doc_id)
      assert {:error, :not_found} = Postgres.get(store_id, doc_id)
    end

    @tag :integration
    test "returns error for non-existent document" do
      store_id = unique_store_id()

      assert {:error, :not_found} = Postgres.delete(store_id, "nonexistent")
    end
  end

  describe "list/2 integration" do
    @tag :integration
    test "lists documents in a store" do
      store_id = unique_store_id()

      for i <- 1..3 do
        Postgres.store(store_id, "doc_#{i}", "Content #{i}", %{index: i})
      end

      {:ok, docs} = Postgres.list(store_id, limit: 10)

      assert length(docs) == 3

      # Cleanup
      for i <- 1..3, do: Postgres.delete(store_id, "doc_#{i}")
    end

    @tag :integration
    test "respects limit and offset" do
      store_id = unique_store_id()

      for i <- 1..5 do
        Postgres.store(store_id, "doc_#{i}", "Content #{i}", %{})
      end

      {:ok, page1} = Postgres.list(store_id, limit: 2, offset: 0)
      {:ok, page2} = Postgres.list(store_id, limit: 2, offset: 2)

      assert length(page1) == 2
      assert length(page2) == 2

      # Cleanup
      for i <- 1..5, do: Postgres.delete(store_id, "doc_#{i}")
    end

    @tag :integration
    test "returns empty list for empty store" do
      store_id = unique_store_id()

      {:ok, docs} = Postgres.list(store_id, [])

      assert docs == []
    end
  end

  describe "search_metadata/2 integration" do
    @tag :integration
    test "finds documents by metadata" do
      store_id = unique_store_id()

      Postgres.store(store_id, "doc_1", "Content 1", %{type: "article", author: "alice"})
      Postgres.store(store_id, "doc_2", "Content 2", %{type: "article", author: "bob"})
      Postgres.store(store_id, "doc_3", "Content 3", %{type: "note", author: "alice"})

      {:ok, articles} = Postgres.search_metadata(store_id, %{type: "article"})
      {:ok, alice_docs} = Postgres.search_metadata(store_id, %{author: "alice"})

      {:ok, alice_articles} =
        Postgres.search_metadata(store_id, %{type: "article", author: "alice"})

      assert length(articles) == 2
      assert length(alice_docs) == 2
      assert length(alice_articles) == 1

      # Cleanup
      for i <- 1..3, do: Postgres.delete(store_id, "doc_#{i}")
    end
  end

  describe "exists_by_hash?/2 integration" do
    @tag :integration
    test "returns true for existing content" do
      store_id = unique_store_id()
      content = "Unique content #{System.unique_integer()}"

      {:ok, _} = Postgres.store(store_id, "doc_1", content, %{})

      assert Postgres.exists_by_hash?(store_id, content) == true

      Postgres.delete(store_id, "doc_1")
    end

    @tag :integration
    test "returns false for non-existent content" do
      store_id = unique_store_id()

      assert Postgres.exists_by_hash?(store_id, "nonexistent content") == false
    end
  end

  describe "get_by_hash/2 integration" do
    @tag :integration
    test "retrieves document by content hash" do
      store_id = unique_store_id()
      content = "Unique content #{System.unique_integer()}"

      {:ok, _} = Postgres.store(store_id, "doc_1", content, %{found: true})

      {:ok, doc} = Postgres.get_by_hash(store_id, content)

      assert doc.id == "doc_1"
      assert doc.content == content
      assert doc.metadata["found"] == true

      Postgres.delete(store_id, "doc_1")
    end

    @tag :integration
    test "returns error for non-existent content" do
      store_id = unique_store_id()

      assert {:error, :not_found} = Postgres.get_by_hash(store_id, "nonexistent")
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp unique_store_id do
    "test_store_#{System.unique_integer([:positive])}"
  end
end
