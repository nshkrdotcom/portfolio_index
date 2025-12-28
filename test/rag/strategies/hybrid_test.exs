defmodule PortfolioIndex.RAG.Strategies.HybridTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Fixtures
  alias PortfolioIndex.Mocks.Embedder
  alias PortfolioIndex.Mocks.VectorStore
  alias PortfolioIndex.RAG.Strategies.Hybrid

  import Mox

  setup :verify_on_exit!

  describe "name/0" do
    test "returns :hybrid" do
      assert Hybrid.name() == :hybrid
    end
  end

  describe "required_adapters/0" do
    test "returns vector_store and embedder" do
      adapters = Hybrid.required_adapters()
      assert :vector_store in adapters
      assert :embedder in adapters
    end
  end

  describe "retrieve/3" do
    test "merges vector and keyword results" do
      expect(Embedder, :embed, fn "Elixir", _opts ->
        {:ok, %{vector: [0.1, 0.2], token_count: 2}}
      end)

      expect(VectorStore, :search, 2, fn "idx", query, _limit, opts ->
        case {query, Keyword.get(opts, :mode)} do
          {[_ | _], nil} ->
            {:ok,
             [
               %{
                 id: "doc_v",
                 score: 0.9,
                 metadata: %{"content" => "Vector match", "source" => "vector"}
               }
             ]}

          {"Elixir", :keyword} ->
            {:ok,
             [
               %{
                 id: "doc_k",
                 score: 1.0,
                 metadata: %{"content" => "Keyword match", "source" => "keyword"}
               }
             ]}

          other ->
            flunk("unexpected search call: #{inspect(other)}")
        end
      end)

      context = %{
        index_id: "idx",
        adapters: %{embedder: Embedder, vector_store: VectorStore}
      }

      {:ok, result} = Hybrid.retrieve("Elixir", context, k: 2, rrf_k: 60)

      assert Enum.any?(result.items, &(&1.content == "Vector match"))
      assert Enum.any?(result.items, &(&1.content == "Keyword match"))
    end
  end

  describe "reciprocal_rank_fusion/2" do
    test "merges single result list" do
      results = Fixtures.sample_search_results(5)
      merged = Hybrid.reciprocal_rank_fusion([{:vector, results}], k: 60)

      assert length(merged) == 5
      # Scores should be in descending order
      scores = Enum.map(merged, & &1.score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "merges multiple result lists" do
      vector_results = [
        %{id: "doc_1", score: 0.9, metadata: %{}},
        %{id: "doc_2", score: 0.8, metadata: %{}},
        %{id: "doc_3", score: 0.7, metadata: %{}}
      ]

      keyword_results = [
        %{id: "doc_2", score: 0.95, metadata: %{}},
        %{id: "doc_4", score: 0.85, metadata: %{}},
        %{id: "doc_1", score: 0.75, metadata: %{}}
      ]

      merged =
        Hybrid.reciprocal_rank_fusion(
          [
            {:vector, vector_results},
            {:keyword, keyword_results}
          ],
          k: 60
        )

      # doc_1 and doc_2 appear in both lists, should have higher RRF scores
      ids = Enum.map(merged, & &1.id)
      assert "doc_1" in ids
      assert "doc_2" in ids

      # doc_2 is rank 1 in keyword and rank 2 in vector, should score high
      doc2 = Enum.find(merged, &(&1.id == "doc_2"))
      doc4 = Enum.find(merged, &(&1.id == "doc_4"))
      assert doc2.score > doc4.score
    end

    test "handles empty lists" do
      merged = Hybrid.reciprocal_rank_fusion([{:vector, []}], k: 60)
      assert merged == []
    end
  end
end
