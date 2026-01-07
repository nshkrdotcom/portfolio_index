defmodule PortfolioIndex.RAG.Strategies.AgenticTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Mocks.Embedder
  alias PortfolioIndex.Mocks.LLM
  alias PortfolioIndex.Mocks.VectorStore
  alias PortfolioIndex.RAG.Pipeline.Context
  alias PortfolioIndex.RAG.Strategies.Agentic

  import Mox

  setup :verify_on_exit!

  # Mock LLM for pipeline tests
  defmodule PipelineMockLLM do
    def complete(messages, _opts) do
      prompt = messages |> List.first() |> Map.get(:content)

      cond do
        # Answer generation
        String.contains?(prompt, "Answer the following") ->
          {:ok, %{content: "Elixir is a functional programming language."}}

        # Grounding check - grounded
        String.contains?(prompt, "grounded") ->
          {:ok, %{content: ~s({"grounded": true, "score": 0.9})}}

        # Sufficiency check - sufficient
        String.contains?(prompt, "sufficient") ->
          {:ok, %{content: ~s({"sufficient": true})}}

        # Query rewrite
        String.contains?(prompt, "rewrite") or String.contains?(prompt, "clean") ->
          {:ok, %{content: "Rewritten: What is Elixir?"}}

        # Query expand
        String.contains?(prompt, "expand") or String.contains?(prompt, "synonyms") ->
          {:ok, %{content: "Elixir functional programming language BEAM Erlang"}}

        # Query decompose
        String.contains?(prompt, "decompose") or String.contains?(prompt, "sub-questions") ->
          {:ok, %{content: ~s({"sub_questions": ["What is Elixir?", "How does it work?"]})}}

        # Default
        true ->
          {:ok, %{content: "Default response"}}
      end
    end
  end

  defmodule MockSearcher do
    def search(_query, _opts) do
      {:ok,
       [
         %{id: "c1", content: "Elixir is a functional language", score: 0.9, metadata: %{}},
         %{id: "c2", content: "It runs on the BEAM VM", score: 0.85, metadata: %{}}
       ]}
    end
  end

  defmodule MockReranker do
    @behaviour PortfolioCore.Ports.Reranker

    @impl true
    def rerank(_query, docs, _opts) do
      reranked =
        docs
        |> Enum.with_index()
        |> Enum.map(fn {doc, idx} ->
          %{
            id: doc.id,
            content: doc.content,
            original_score: doc.score,
            rerank_score: 0.9 - idx * 0.1,
            metadata: doc[:metadata] || %{}
          }
        end)

      {:ok, reranked}
    end

    @impl true
    def model_name, do: "mock-reranker"
  end

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

  describe "execute_pipeline/2" do
    test "executes full pipeline with all steps" do
      opts = [
        llm: &PipelineMockLLM.complete/2,
        search_fn: &MockSearcher.search/2,
        reranker: MockReranker,
        skip: [:rewrite, :expand, :decompose]
      ]

      {:ok, result} = Agentic.execute_pipeline("What is Elixir?", opts)

      assert is_binary(result.answer)
      assert is_list(result.results)
      assert is_map(result.rerank_scores)
    end

    test "can skip specified steps" do
      opts = [
        llm: &PipelineMockLLM.complete/2,
        search_fn: &MockSearcher.search/2,
        skip: [:rewrite, :expand, :decompose, :select, :rerank]
      ]

      {:ok, result} = Agentic.execute_pipeline("What is Elixir?", opts)

      # Should still have answer and results
      assert is_binary(result.answer) or is_nil(result.answer)
      assert is_list(result.results)
    end

    test "returns error when search fails" do
      failing_search = fn _query, _opts -> {:error, :search_failed} end

      opts = [
        llm: &PipelineMockLLM.complete/2,
        search_fn: failing_search,
        skip: [:rewrite, :expand, :decompose, :select, :rerank]
      ]

      {:error, reason} = Agentic.execute_pipeline("What is Elixir?", opts)

      assert reason == :search_failed
    end
  end

  describe "with_context/2" do
    test "processes context through pipeline" do
      ctx = Context.new("What is Elixir?")

      opts = [
        llm: &PipelineMockLLM.complete/2,
        search_fn: &MockSearcher.search/2,
        skip: [:rewrite, :expand, :decompose, :select, :rerank]
      ]

      result_ctx = Agentic.with_context(ctx, opts)

      refute Context.error?(result_ctx)
      assert is_list(result_ctx.results)
    end

    test "propagates halted context" do
      ctx = Context.new("What is Elixir?") |> Context.halt(:previous_error)

      opts = [llm: &PipelineMockLLM.complete/2]

      result_ctx = Agentic.with_context(ctx, opts)

      assert Context.error?(result_ctx)
      assert result_ctx.error == :previous_error
    end

    test "handles missing llm gracefully" do
      ctx = Context.new("What is Elixir?")

      opts = [search_fn: &MockSearcher.search/2]

      result_ctx = Agentic.with_context(ctx, opts)

      # Should not error, just skip LLM-dependent steps
      refute Context.error?(result_ctx)
    end

    test "tracks correction history" do
      ctx = Context.new("What is Elixir?")

      opts = [
        llm: &PipelineMockLLM.complete/2,
        search_fn: &MockSearcher.search/2,
        skip: [:rewrite, :expand, :decompose, :select, :rerank]
      ]

      result_ctx = Agentic.with_context(ctx, opts)

      # Corrections list should exist (may be empty if answer was grounded)
      assert is_list(result_ctx.corrections)
      assert is_integer(result_ctx.correction_count)
    end
  end
end
