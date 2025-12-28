defmodule PortfolioIndex.Adapters.VectorStore.PgvectorTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Adapters.VectorStore.Pgvector
  alias PortfolioIndex.Fixtures

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
    test "implements VectorStore behaviour" do
      behaviours = Pgvector.__info__(:attributes)[:behaviour] || []
      assert PortfolioCore.Ports.VectorStore in behaviours
    end

    test "exposes a VectorStore.Hybrid wrapper" do
      behaviours =
        PortfolioIndex.Adapters.VectorStore.Pgvector.Hybrid.__info__(:attributes)[:behaviour] ||
          []

      assert PortfolioCore.Ports.VectorStore.Hybrid in behaviours
    end
  end

  describe "fulltext_search/4" do
    defmodule StubFullText do
      def search(_index_id, _query, _k, _opts) do
        {:ok,
         [
           %{
             id: "doc_1",
             content: "Fulltext match",
             score: 0.7,
             metadata: %{"source" => "fulltext"}
           }
         ]}
      end
    end

    test "maps fulltext results to vector store search_result format" do
      assert {:ok, [result]} =
               Pgvector.fulltext_search("idx", "query", 5, fulltext_module: StubFullText)

      assert result.id == "doc_1"
      assert result.score == 0.7
      assert result.vector == nil
      assert result.metadata["source"] == "fulltext"
      assert result.metadata["content"] == "Fulltext match"
    end
  end

  # =============================================================================
  # Integration Tests (require running PostgreSQL with pgvector)
  # Run with: mix test --include integration
  # =============================================================================

  describe "create_index/2 integration" do
    @tag :integration
    test "creates a new vector index" do
      index_id = unique_index_id()

      assert :ok =
               Pgvector.create_index(index_id, %{
                 dimensions: 768,
                 metric: :cosine
               })

      assert Pgvector.index_exists?(index_id) == true

      # Cleanup
      Pgvector.delete_index(index_id)
    end

    @tag :integration
    test "creates index with euclidean metric" do
      index_id = unique_index_id()

      assert :ok =
               Pgvector.create_index(index_id, %{
                 dimensions: 384,
                 metric: :euclidean
               })

      Pgvector.delete_index(index_id)
    end

    @tag :integration
    test "returns error for duplicate index" do
      index_id = unique_index_id()

      assert :ok = Pgvector.create_index(index_id, %{dimensions: 768})
      assert {:error, :already_exists} = Pgvector.create_index(index_id, %{dimensions: 768})

      Pgvector.delete_index(index_id)
    end
  end

  describe "store/4 integration" do
    @tag :integration
    test "stores a vector with metadata" do
      index_id = setup_test_index()
      vector = Fixtures.random_normalized_vector(768)

      assert :ok =
               Pgvector.store(index_id, "doc_1", vector, %{
                 content: "Hello, world!",
                 source: "/path/to/doc.md"
               })

      Pgvector.delete_index(index_id)
    end

    @tag :integration
    test "updates existing vector" do
      index_id = setup_test_index()
      vector1 = Fixtures.random_normalized_vector(768)
      vector2 = Fixtures.random_normalized_vector(768)

      :ok = Pgvector.store(index_id, "doc_1", vector1, %{version: 1})
      :ok = Pgvector.store(index_id, "doc_1", vector2, %{version: 2})

      {:ok, results} = Pgvector.search(index_id, vector2, 10, [])
      assert length(results) == 1
      assert hd(results).metadata["version"] == 2

      Pgvector.delete_index(index_id)
    end
  end

  describe "store_batch/2 integration" do
    @tag :integration
    test "stores multiple vectors" do
      index_id = setup_test_index()

      items =
        for i <- 1..5 do
          {
            "doc_#{i}",
            Fixtures.random_normalized_vector(768),
            %{content: "Document #{i}"}
          }
        end

      assert {:ok, 5} = Pgvector.store_batch(index_id, items)

      {:ok, stats} = Pgvector.index_stats(index_id)
      assert stats.count == 5

      Pgvector.delete_index(index_id)
    end
  end

  describe "search/4 integration" do
    @tag :integration
    test "finds similar vectors" do
      index_id = setup_test_index()

      # Store some vectors
      base_vector = Fixtures.random_normalized_vector(768)

      # Create similar and dissimilar vectors
      similar = add_noise(base_vector, 0.1)
      dissimilar = Fixtures.random_normalized_vector(768)

      :ok = Pgvector.store(index_id, "similar", similar, %{type: "similar"})
      :ok = Pgvector.store(index_id, "dissimilar", dissimilar, %{type: "dissimilar"})

      {:ok, results} = Pgvector.search(index_id, base_vector, 2, [])

      assert length(results) == 2
      # Similar should be first (higher score = more similar)
      assert hd(results).id == "similar"

      Pgvector.delete_index(index_id)
    end

    @tag :integration
    test "respects k parameter" do
      index_id = setup_test_index()

      for i <- 1..10 do
        vector = Fixtures.random_normalized_vector(768)
        :ok = Pgvector.store(index_id, "doc_#{i}", vector, %{})
      end

      {:ok, results} = Pgvector.search(index_id, Fixtures.random_normalized_vector(768), 5, [])

      assert length(results) == 5

      Pgvector.delete_index(index_id)
    end

    @tag :integration
    test "returns empty list for empty index" do
      index_id = setup_test_index()

      {:ok, results} =
        Pgvector.search(
          index_id,
          Fixtures.random_normalized_vector(768),
          10,
          []
        )

      assert results == []

      Pgvector.delete_index(index_id)
    end
  end

  describe "delete/2 integration" do
    @tag :integration
    test "deletes a vector by id" do
      index_id = setup_test_index()
      vector = Fixtures.random_normalized_vector(768)

      :ok = Pgvector.store(index_id, "to_delete", vector, %{})

      {:ok, stats_before} = Pgvector.index_stats(index_id)
      assert stats_before.count == 1

      :ok = Pgvector.delete(index_id, "to_delete")

      {:ok, stats_after} = Pgvector.index_stats(index_id)
      assert stats_after.count == 0

      Pgvector.delete_index(index_id)
    end
  end

  describe "index_stats/1 integration" do
    @tag :integration
    test "returns index statistics" do
      index_id = setup_test_index()

      for i <- 1..3 do
        vector = Fixtures.random_normalized_vector(768)
        :ok = Pgvector.store(index_id, "doc_#{i}", vector, %{})
      end

      {:ok, stats} = Pgvector.index_stats(index_id)

      assert stats.count == 3
      assert stats.dimensions == 768
      assert is_atom(stats.metric)

      Pgvector.delete_index(index_id)
    end
  end

  describe "index_exists?/1 integration" do
    @tag :integration
    test "returns true for existing index" do
      index_id = setup_test_index()

      assert Pgvector.index_exists?(index_id) == true

      Pgvector.delete_index(index_id)
    end

    @tag :integration
    test "returns false for non-existent index" do
      assert Pgvector.index_exists?("nonexistent_index_#{System.unique_integer()}") == false
    end
  end

  describe "delete_index/1 integration" do
    @tag :integration
    test "deletes an existing index" do
      index_id = unique_index_id()
      :ok = Pgvector.create_index(index_id, %{dimensions: 768})

      assert Pgvector.index_exists?(index_id) == true
      assert :ok = Pgvector.delete_index(index_id)
      assert Pgvector.index_exists?(index_id) == false
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp unique_index_id do
    "test_idx_#{System.unique_integer([:positive])}"
  end

  defp setup_test_index(opts \\ []) do
    index_id = unique_index_id()
    dimensions = Keyword.get(opts, :dimensions, 768)
    metric = Keyword.get(opts, :metric, :cosine)
    # Use :flat (exact search) for tests - IVFFlat doesn't work well with small datasets
    index_type = Keyword.get(opts, :index_type, :flat)

    :ok =
      Pgvector.create_index(index_id, %{
        dimensions: dimensions,
        metric: metric,
        index_type: index_type
      })

    index_id
  end

  defp add_noise(vector, noise_level) do
    vector
    |> Enum.map(fn x -> x + (:rand.uniform() - 0.5) * noise_level end)
    |> normalize()
  end

  defp normalize(vector) do
    magnitude = :math.sqrt(Enum.reduce(vector, 0, fn x, acc -> acc + x * x end))
    Enum.map(vector, fn x -> x / magnitude end)
  end
end
