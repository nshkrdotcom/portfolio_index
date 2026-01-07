defmodule PortfolioIndex.VectorStore.CollectionsTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Adapters.VectorStore.Pgvector
  alias PortfolioIndex.Fixtures
  alias PortfolioIndex.VectorStore.Collections

  @dimensions 384

  # =============================================================================
  # Integration Tests (require running PostgreSQL with pgvector)
  # Run with: mix test --include integration
  # =============================================================================

  setup tags do
    if tags[:integration] do
      pid = Sandbox.start_owner!(PortfolioIndex.Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)

      # Create a test index
      index_id = unique_index_id()
      :ok = Pgvector.create_index(index_id, %{dimensions: @dimensions, metric: :cosine})
      on_exit(fn -> Pgvector.delete_index(index_id) end)

      %{index_id: index_id}
    else
      :ok
    end
  end

  describe "insert_to_collection/5" do
    @tag :integration
    test "inserts vector with collection metadata", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      assert :ok =
               Collections.insert_to_collection(
                 "products",
                 "prod_1",
                 embedding,
                 %{name: "Widget"},
                 index_id: index_id
               )

      # Verify it was stored with collection metadata
      {:ok, results} = Pgvector.search(index_id, embedding, 10, [])
      assert length(results) == 1

      result = hd(results)
      assert result.metadata["collection"] == "products"
    end
  end

  describe "search_collection/3" do
    @tag :integration
    test "searches within specific collection", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      # Insert to different collections
      :ok =
        Collections.insert_to_collection(
          "products",
          "prod_1",
          embedding,
          %{name: "Product"},
          index_id: index_id
        )

      :ok =
        Collections.insert_to_collection(
          "articles",
          "art_1",
          embedding,
          %{name: "Article"},
          index_id: index_id
        )

      # Search products collection only
      {:ok, results} =
        Collections.search_collection("products", embedding, limit: 10, index_id: index_id)

      assert length(results) == 1
      assert hd(results).id == "prod_1"
    end

    @tag :integration
    test "returns empty list for empty collection", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      {:ok, results} =
        Collections.search_collection("empty", embedding, limit: 10, index_id: index_id)

      assert results == []
    end
  end

  describe "list_collections/1" do
    @tag :integration
    test "lists all collections with vectors", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      :ok =
        Collections.insert_to_collection(
          "products",
          "prod_1",
          embedding,
          %{},
          index_id: index_id
        )

      :ok =
        Collections.insert_to_collection(
          "articles",
          "art_1",
          embedding,
          %{},
          index_id: index_id
        )

      {:ok, collections} = Collections.list_collections(index_id: index_id)

      assert "products" in collections
      assert "articles" in collections
    end
  end

  describe "collection_stats/2" do
    @tag :integration
    test "returns collection statistics", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      for i <- 1..5 do
        :ok =
          Collections.insert_to_collection(
            "products",
            "prod_#{i}",
            embedding,
            %{},
            index_id: index_id
          )
      end

      {:ok, stats} = Collections.collection_stats("products", index_id: index_id)

      assert stats.count == 5
      assert stats.collection == "products"
    end

    @tag :integration
    test "returns zero count for empty collection", %{index_id: index_id} do
      {:ok, stats} = Collections.collection_stats("empty", index_id: index_id)

      assert stats.count == 0
    end
  end

  describe "clear_collection/2" do
    @tag :integration
    test "deletes all vectors in collection", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      for i <- 1..3 do
        :ok =
          Collections.insert_to_collection(
            "to_clear",
            "doc_#{i}",
            embedding,
            %{},
            index_id: index_id
          )
      end

      :ok =
        Collections.insert_to_collection(
          "keep",
          "keep_1",
          embedding,
          %{},
          index_id: index_id
        )

      # Clear one collection
      assert :ok = Collections.clear_collection("to_clear", index_id: index_id)

      # Verify to_clear is empty
      {:ok, stats} = Collections.collection_stats("to_clear", index_id: index_id)
      assert stats.count == 0

      # Verify keep collection is intact
      {:ok, keep_stats} = Collections.collection_stats("keep", index_id: index_id)
      assert keep_stats.count == 1
    end
  end

  describe "collection_exists?/2" do
    @tag :integration
    test "returns true for collection with vectors", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      :ok =
        Collections.insert_to_collection(
          "exists",
          "doc_1",
          embedding,
          %{},
          index_id: index_id
        )

      assert Collections.collection_exists?("exists", index_id: index_id) == true
    end

    @tag :integration
    test "returns false for empty collection", %{index_id: index_id} do
      assert Collections.collection_exists?("nonexistent", index_id: index_id) == false
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp unique_index_id do
    "test_coll_#{System.unique_integer([:positive])}"
  end
end
