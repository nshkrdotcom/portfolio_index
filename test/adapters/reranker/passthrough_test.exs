defmodule PortfolioIndex.Adapters.Reranker.PassthroughTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Reranker.Passthrough

  describe "rerank/3" do
    test "returns documents in original order" do
      documents = [
        %{id: "doc_1", content: "First document", score: 0.9},
        %{id: "doc_2", content: "Second document", score: 0.8},
        %{id: "doc_3", content: "Third document", score: 0.7}
      ]

      {:ok, reranked} = Passthrough.rerank("query", documents, [])

      assert length(reranked) == 3
      assert Enum.at(reranked, 0).id == "doc_1"
      assert Enum.at(reranked, 1).id == "doc_2"
      assert Enum.at(reranked, 2).id == "doc_3"
    end

    test "preserves original scores as rerank scores" do
      documents = [
        %{id: "doc_1", content: "Content", score: 0.95}
      ]

      {:ok, [result]} = Passthrough.rerank("query", documents, [])

      assert result.original_score == 0.95
      assert result.rerank_score == 0.95
    end

    test "handles documents without scores" do
      documents = [
        %{id: "doc_1", content: "Content"},
        %{id: "doc_2", content: "Other content"}
      ]

      {:ok, reranked} = Passthrough.rerank("query", documents, [])

      assert length(reranked) == 2
      # Should have decreasing default scores
      assert hd(reranked).rerank_score > List.last(reranked).rerank_score
    end

    test "returns empty list for empty input" do
      {:ok, reranked} = Passthrough.rerank("query", [], [])
      assert reranked == []
    end

    test "includes metadata in output" do
      documents = [
        %{id: "doc_1", content: "Content", metadata: %{source: "test"}}
      ]

      {:ok, [result]} = Passthrough.rerank("query", documents, [])

      assert result.metadata == %{source: "test"}
    end
  end

  describe "model_name/0" do
    test "returns passthrough" do
      assert Passthrough.model_name() == "passthrough"
    end
  end
end
