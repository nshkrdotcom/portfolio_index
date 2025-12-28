defmodule PortfolioIndex.RAG.Strategies.GraphRAGTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Mocks.Embedder
  alias PortfolioIndex.Mocks.GraphStore
  alias PortfolioIndex.Mocks.LLM
  alias PortfolioIndex.Mocks.VectorStore
  alias PortfolioIndex.RAG.Strategies.GraphRAG

  import Mox

  setup :verify_on_exit!

  describe "retrieve/3" do
    test "combines graph and vector results" do
      expect(LLM, :complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"entities": []}), usage: %{input_tokens: 1, output_tokens: 1}}}
      end)

      expect(Embedder, :embed, fn "test query", _opts ->
        {:ok, %{vector: [0.1, 0.2, 0.3], token_count: 3}}
      end)

      expect(VectorStore, :search, fn "default", _vec, 5, _opts ->
        {:ok, [%{id: "v1", content: "Vector result", score: 0.9, metadata: %{}}]}
      end)

      context = %{
        index_id: "default",
        adapters: %{
          embedder: Embedder,
          vector_store: VectorStore,
          graph_store: GraphStore,
          llm: LLM
        }
      }

      {:ok, result} = GraphRAG.retrieve("test query", context, k: 5)

      assert is_list(result.items)
      assert Enum.any?(result.items, &(&1.source == :vector))
    end
  end

  describe "name/0" do
    test "returns :graph_rag" do
      assert GraphRAG.name() == :graph_rag
    end
  end

  describe "required_adapters/0" do
    test "requires all necessary adapters" do
      adapters = GraphRAG.required_adapters()

      assert :vector_store in adapters
      assert :embedder in adapters
      assert :graph_store in adapters
      assert :llm in adapters
    end
  end
end
