defmodule PortfolioIndex.RAG.Strategies.SelfRAGTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias Elixir.Gemini, as: GeminiSdk
  alias PortfolioIndex.Adapters.VectorStore.Pgvector
  alias PortfolioIndex.DataCase
  alias PortfolioIndex.RAG.Strategies.SelfRAG

  @test_index_id "test_index"

  setup tags do
    if tags[:integration] do
      DataCase.setup_sandbox(tags)

      # Create test index before running integration tests
      # Use :flat index type for small test datasets
      :ok =
        Pgvector.create_index(@test_index_id, %{
          dimensions: 768,
          metric: :cosine,
          index_type: :flat
        })

      on_exit(fn -> Pgvector.delete_index(@test_index_id) end)
    end

    :ok
  end

  describe "name/0" do
    test "returns :self_rag" do
      assert SelfRAG.name() == :self_rag
    end
  end

  describe "required_adapters/0" do
    test "returns required adapters" do
      adapters = SelfRAG.required_adapters()
      assert :vector_store in adapters
      assert :embedder in adapters
      assert :llm in adapters
    end
  end

  # Integration tests would require real API access
  # Run with: mix test --include integration --include live
  describe "retrieve/3 integration" do
    if System.get_env("GEMINI_API_KEY") do
      @tag :integration
      @tag :live
      test "retrieves with self-critique" do
        context = %{
          index_id: @test_index_id,
          adapters: %{
            llm: {PortfolioIndex.Adapters.LLM.Gemini, [sdk: GeminiSdk]},
            embedder: {PortfolioIndex.Adapters.Embedder.Gemini, [sdk: GeminiSdk]},
            vector_store: {PortfolioIndex.Adapters.VectorStore.Pgvector, []}
          }
        }

        opts = [k: 3]

        {:ok, result} = SelfRAG.retrieve("What is GenServer?", context, opts)

        assert is_list(result.items)
        assert is_binary(result.answer) or is_nil(result.answer)
        assert result.strategy == :self_rag
        assert is_integer(result.timing_ms)
        assert is_map(result.critique)
      end
    else
      @tag :integration
      @tag :live
      @tag skip: "GEMINI_API_KEY is not set"
      test "retrieves with self-critique" do
        :ok
      end
    end
  end
end
