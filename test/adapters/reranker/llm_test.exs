# Mock LLM for reranker testing
defmodule PortfolioIndex.Test.RerankerMockLLM do
  def complete(_messages, _opts) do
    {:ok,
     %{
       content: """
       [{"index": 0, "score": 8}, {"index": 1, "score": 5}, {"index": 2, "score": 9}]
       """
     }}
  end
end

defmodule PortfolioIndex.Test.FailingMockLLM do
  def complete(_messages, _opts) do
    {:error, :api_error}
  end
end

defmodule PortfolioIndex.Test.InvalidResponseMockLLM do
  def complete(_messages, _opts) do
    {:ok, %{content: "This is not valid JSON at all"}}
  end
end

defmodule PortfolioIndex.Adapters.Reranker.LLMTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Reranker.LLM
  alias PortfolioIndex.Test.FailingMockLLM
  alias PortfolioIndex.Test.InvalidResponseMockLLM
  alias PortfolioIndex.Test.RerankerMockLLM

  describe "rerank/3" do
    test "reranks documents by LLM scores" do
      documents = [
        %{id: "doc_0", content: "First document", score: 0.9},
        %{id: "doc_1", content: "Second document", score: 0.8},
        %{id: "doc_2", content: "Third document", score: 0.7}
      ]

      opts = [context: %{adapters: %{llm: RerankerMockLLM}}]
      {:ok, reranked} = LLM.rerank("query", documents, opts)

      assert length(reranked) == 3
      # doc_2 got score 9, doc_0 got 8, doc_1 got 5
      assert hd(reranked).id == "doc_2"
      assert Enum.at(reranked, 1).id == "doc_0"
      assert List.last(reranked).id == "doc_1"
    end

    test "respects top_n option" do
      documents = [
        %{id: "doc_0", content: "First document"},
        %{id: "doc_1", content: "Second document"},
        %{id: "doc_2", content: "Third document"}
      ]

      opts = [top_n: 2, context: %{adapters: %{llm: RerankerMockLLM}}]
      {:ok, reranked} = LLM.rerank("query", documents, opts)

      assert length(reranked) == 2
    end

    test "returns empty list for empty input" do
      opts = [context: %{adapters: %{llm: RerankerMockLLM}}]
      {:ok, reranked} = LLM.rerank("query", [], opts)
      assert reranked == []
    end

    test "falls back to passthrough on LLM error" do
      documents = [
        %{id: "doc_0", content: "First document", score: 0.9},
        %{id: "doc_1", content: "Second document", score: 0.8}
      ]

      opts = [context: %{adapters: %{llm: FailingMockLLM}}]

      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, reranked} = LLM.rerank("query", documents, opts)

        # Should return in original order with original scores
        assert length(reranked) == 2
        assert hd(reranked).id == "doc_0"
      end)
    end

    test "falls back to passthrough on invalid JSON" do
      documents = [
        %{id: "doc_0", content: "First document", score: 0.9}
      ]

      opts = [context: %{adapters: %{llm: InvalidResponseMockLLM}}]

      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, reranked} = LLM.rerank("query", documents, opts)

        assert length(reranked) == 1
      end)
    end

    test "preserves metadata in output" do
      documents = [
        %{id: "doc_0", content: "Content", metadata: %{source: "test"}}
      ]

      opts = [context: %{adapters: %{llm: RerankerMockLLM}}]
      {:ok, [result]} = LLM.rerank("query", documents, opts)

      assert result.metadata == %{source: "test"}
    end

    test "includes both original and rerank scores" do
      documents = [
        %{id: "doc_0", content: "Content", score: 0.75}
      ]

      opts = [context: %{adapters: %{llm: RerankerMockLLM}}]
      {:ok, [result]} = LLM.rerank("query", documents, opts)

      assert result.original_score == 0.75
      # Score 8 normalized to 0-1
      assert result.rerank_score == 0.8
    end
  end

  describe "model_name/0" do
    test "returns llm-reranker" do
      assert LLM.model_name() == "llm-reranker"
    end
  end

  describe "normalize_scores/1" do
    test "normalizes scores to 0-1 range" do
      items = [
        %{id: "a", rerank_score: 0.2},
        %{id: "b", rerank_score: 0.8},
        %{id: "c", rerank_score: 0.5}
      ]

      normalized = LLM.normalize_scores(items)

      assert Enum.find(normalized, &(&1.id == "a")).rerank_score == 0.0
      assert Enum.find(normalized, &(&1.id == "b")).rerank_score == 1.0
      assert_in_delta Enum.find(normalized, &(&1.id == "c")).rerank_score, 0.5, 0.001
    end

    test "handles all same scores" do
      items = [
        %{id: "a", rerank_score: 0.5},
        %{id: "b", rerank_score: 0.5}
      ]

      normalized = LLM.normalize_scores(items)

      assert Enum.all?(normalized, &(&1.rerank_score == 1.0))
    end
  end
end
