defmodule PortfolioIndex.RAG.Strategies.AgenticTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Mocks.Embedder
  alias PortfolioIndex.Mocks.LLM
  alias PortfolioIndex.Mocks.VectorStore
  alias PortfolioIndex.RAG.Strategies.Agentic

  import Mox

  setup :verify_on_exit!

  describe "retrieve/3" do
    test "uses tools to gather results" do
      expect(LLM, :complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"tool": "semantic_search", "args": {"query": "test query"}})}}
      end)

      expect(LLM, :complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"done": true})}}
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
          llm: LLM
        }
      }

      {:ok, result} = Agentic.retrieve("test query", context, k: 5, max_iterations: 2)

      assert is_list(result.items)
      assert result.items != []
      assert result.strategy == :agentic
    end
  end

  describe "name/0" do
    test "returns :agentic" do
      assert Agentic.name() == :agentic
    end
  end

  describe "required_adapters/0" do
    test "requires all necessary adapters" do
      adapters = Agentic.required_adapters()

      assert :vector_store in adapters
      assert :embedder in adapters
      assert :llm in adapters
    end
  end
end
