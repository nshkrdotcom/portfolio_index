defmodule PortfolioIndex.VectorStore.SearchTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Adapters.VectorStore.Pgvector
  alias PortfolioIndex.Fixtures
  alias PortfolioIndex.Repo
  alias PortfolioIndex.VectorStore.Search

  @dimensions 384

  # =============================================================================
  # Unit Tests
  # =============================================================================

  describe "filter_results/2" do
    test "filters by single key" do
      results = [
        %{id: "1", metadata: %{"category" => "a"}, score: 0.9},
        %{id: "2", metadata: %{"category" => "b"}, score: 0.8},
        %{id: "3", metadata: %{"category" => "a"}, score: 0.7}
      ]

      filtered = Search.filter_results(results, category: "a")

      assert length(filtered) == 2
      assert Enum.all?(filtered, fn r -> r.metadata["category"] == "a" end)
    end

    test "filters by multiple keys" do
      results = [
        %{id: "1", metadata: %{"category" => "a", "status" => "active"}, score: 0.9},
        %{id: "2", metadata: %{"category" => "a", "status" => "inactive"}, score: 0.8},
        %{id: "3", metadata: %{"category" => "b", "status" => "active"}, score: 0.7}
      ]

      filtered = Search.filter_results(results, category: "a", status: "active")

      assert length(filtered) == 1
      assert hd(filtered).id == "1"
    end

    test "returns all results when filters empty" do
      results = [
        %{id: "1", metadata: %{}, score: 0.9},
        %{id: "2", metadata: %{}, score: 0.8}
      ]

      filtered = Search.filter_results(results, [])

      assert length(filtered) == 2
    end
  end

  describe "normalize_scores/2" do
    test "normalizes cosine scores" do
      results = [
        %{id: "1", score: 0.95},
        %{id: "2", score: 0.5},
        %{id: "3", score: 0.0}
      ]

      normalized = Search.normalize_scores(results, :cosine)

      # Cosine scores are already 0-1, should stay same
      assert Enum.at(normalized, 0).score == 0.95
      assert Enum.at(normalized, 1).score == 0.5
      assert Enum.at(normalized, 2).score == 0.0
    end

    test "normalizes euclidean distances" do
      # Lower distance = more similar
      results = [
        %{id: "1", score: 0.0},
        %{id: "2", score: 0.5},
        %{id: "3", score: 1.0}
      ]

      normalized = Search.normalize_scores(results, :euclidean)

      # Score should be inverted: 0 distance = 1.0 score
      assert Enum.at(normalized, 0).score == 1.0
      assert Enum.at(normalized, 1).score == 0.5
      assert Enum.at(normalized, 2).score == 0.0
    end
  end

  describe "deduplicate/2" do
    test "removes duplicates by id" do
      results = [
        %{id: "1", score: 0.9, metadata: %{}},
        %{id: "2", score: 0.8, metadata: %{}},
        %{id: "1", score: 0.7, metadata: %{}}
      ]

      deduped = Search.deduplicate(results, :id)

      assert length(deduped) == 2
      ids = Enum.map(deduped, & &1.id)
      assert "1" in ids
      assert "2" in ids
    end

    test "keeps highest scoring duplicate" do
      results = [
        %{id: "1", score: 0.7, metadata: %{}},
        %{id: "1", score: 0.9, metadata: %{}}
      ]

      [result] = Search.deduplicate(results, :id)

      assert result.score == 0.9
    end

    test "deduplicates by content hash" do
      results = [
        %{id: "1", score: 0.9, metadata: %{"content_hash" => "abc123"}},
        %{id: "2", score: 0.8, metadata: %{"content_hash" => "abc123"}},
        %{id: "3", score: 0.7, metadata: %{"content_hash" => "def456"}}
      ]

      deduped = Search.deduplicate(results, :content_hash)

      assert length(deduped) == 2
    end
  end

  # =============================================================================
  # Integration Tests
  # =============================================================================

  setup tags do
    if tags[:integration] do
      pid = Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)

      index_id = unique_index_id()
      :ok = Pgvector.create_index(index_id, %{dimensions: @dimensions, metric: :cosine})
      on_exit(fn -> Pgvector.delete_index(index_id) end)

      %{index_id: index_id}
    else
      :ok
    end
  end

  describe "similarity_search/2" do
    @tag :integration
    test "executes basic similarity search", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)
      :ok = Pgvector.store(index_id, "doc_1", embedding, %{content: "hello"})

      {:ok, results} =
        Search.similarity_search(embedding, limit: 10, index_id: index_id)

      assert length(results) == 1
      assert hd(results).id == "doc_1"
    end

    @tag :integration
    test "applies threshold filter", %{index_id: index_id} do
      high = normalize([1.0, 0.0, 0.0] ++ List.duplicate(0.0, @dimensions - 3))
      low = normalize([0.0, 1.0, 0.0] ++ List.duplicate(0.0, @dimensions - 3))

      :ok = Pgvector.store(index_id, "high", high, %{})
      :ok = Pgvector.store(index_id, "low", low, %{})

      {:ok, results} =
        Search.similarity_search(high, limit: 10, threshold: 0.8, index_id: index_id)

      assert length(results) == 1
      assert hd(results).id == "high"
    end

    @tag :integration
    test "applies collection filter", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      :ok = Pgvector.store(index_id, "prod_1", embedding, %{"collection" => "products"})
      :ok = Pgvector.store(index_id, "art_1", embedding, %{"collection" => "articles"})

      {:ok, results} =
        Search.similarity_search(embedding,
          limit: 10,
          collection: "products",
          index_id: index_id
        )

      assert length(results) == 1
      assert hd(results).id == "prod_1"
    end
  end

  describe "hybrid_search/3" do
    @tag :integration
    test "combines vector and keyword search", %{index_id: index_id} do
      embedding = Fixtures.random_normalized_vector(@dimensions)

      :ok = Pgvector.store(index_id, "doc_1", embedding, %{"content" => "elixir programming"})
      :ok = Pgvector.store(index_id, "doc_2", embedding, %{"content" => "python scripting"})

      {:ok, results} =
        Search.hybrid_search(embedding, "elixir", limit: 10, index_id: index_id)

      # Should prefer doc_1 due to keyword match
      assert results != []
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp unique_index_id do
    "test_search_#{System.unique_integer([:positive])}"
  end

  defp normalize(vector) do
    magnitude = :math.sqrt(Enum.reduce(vector, 0.0, fn x, sum -> sum + x * x end))

    if magnitude > 0 do
      Enum.map(vector, &(&1 / magnitude))
    else
      vector
    end
  end
end
