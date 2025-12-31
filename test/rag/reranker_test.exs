# Mock reranker that scores and sorts chunks
defmodule PortfolioIndex.Test.MockReranker do
  @behaviour PortfolioCore.Ports.Reranker

  @impl true
  def rerank(_query, documents, opts) do
    top_n = Keyword.get(opts, :top_n, length(documents))

    reranked =
      documents
      |> Enum.with_index()
      |> Enum.map(fn {doc, idx} ->
        # Give higher scores to earlier documents (simulating relevance)
        score = 1.0 - idx * 0.1

        %{
          id: doc[:id] || "doc_#{idx}",
          content: doc[:content] || "",
          original_score: doc[:score] || 0.5,
          rerank_score: score,
          metadata: doc[:metadata] || %{}
        }
      end)
      |> Enum.sort_by(& &1.rerank_score, :desc)
      |> Enum.take(top_n)

    {:ok, reranked}
  end

  @impl true
  def model_name, do: "mock-reranker"
end

defmodule PortfolioIndex.Test.FailingReranker do
  @behaviour PortfolioCore.Ports.Reranker

  @impl true
  def rerank(_query, _documents, _opts) do
    {:error, :rerank_failed}
  end

  @impl true
  def model_name, do: "failing-reranker"
end

defmodule PortfolioIndex.RAG.RerankerTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.RAG.Pipeline.Context
  alias PortfolioIndex.RAG.Reranker
  alias PortfolioIndex.Test.FailingReranker
  alias PortfolioIndex.Test.MockReranker

  @sample_chunks [
    %{id: "c1", content: "First chunk content", score: 0.9, metadata: %{source: "doc1"}},
    %{id: "c2", content: "Second chunk content", score: 0.85, metadata: %{source: "doc2"}},
    %{id: "c3", content: "Third chunk content", score: 0.8, metadata: %{source: "doc1"}},
    %{id: "c4", content: "Fourth chunk content", score: 0.75, metadata: %{source: "doc3"}}
  ]

  describe "rerank/2" do
    test "reranks context results" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      opts = [reranker: MockReranker]

      result_ctx = Reranker.rerank(ctx, opts)

      refute Context.error?(result_ctx)
      assert length(result_ctx.results) == 4
    end

    test "respects limit option" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      opts = [reranker: MockReranker, limit: 2]

      result_ctx = Reranker.rerank(ctx, opts)

      assert length(result_ctx.results) <= 2
    end

    test "filters by threshold" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      opts = [reranker: MockReranker, threshold: 0.85]

      result_ctx = Reranker.rerank(ctx, opts)

      # Should filter out low-scored chunks
      Enum.each(result_ctx.results, fn chunk ->
        assert chunk.rerank_score >= 0.85
      end)
    end

    test "tracks scores when track_scores is true" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      opts = [reranker: MockReranker, track_scores: true]

      result_ctx = Reranker.rerank(ctx, opts)

      assert is_map(result_ctx.rerank_scores)
      assert map_size(result_ctx.rerank_scores) > 0
    end

    test "handles empty results" do
      ctx = %Context{
        question: "What is Elixir?",
        results: [],
        opts: []
      }

      opts = [reranker: MockReranker]

      result_ctx = Reranker.rerank(ctx, opts)

      assert result_ctx.results == []
    end

    test "handles reranker errors gracefully" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      opts = [reranker: FailingReranker]

      result_ctx = Reranker.rerank(ctx, opts)

      # Should return original results on error
      assert result_ctx.results == @sample_chunks
    end

    test "propagates halted context" do
      ctx =
        %Context{question: "What?", results: [], opts: []}
        |> Context.halt(:previous_error)

      opts = [reranker: MockReranker]

      result_ctx = Reranker.rerank(ctx, opts)

      assert Context.error?(result_ctx)
      assert result_ctx.error == :previous_error
    end
  end

  describe "rerank_chunks/3" do
    test "reranks list of chunks directly" do
      {:ok, reranked} =
        Reranker.rerank_chunks("What is Elixir?", @sample_chunks, reranker: MockReranker)

      assert is_list(reranked)
      assert length(reranked) == 4
    end

    test "respects options" do
      {:ok, reranked} =
        Reranker.rerank_chunks("What is Elixir?", @sample_chunks,
          reranker: MockReranker,
          limit: 2
        )

      assert length(reranked) == 2
    end

    test "returns error on reranker failure" do
      assert {:error, :rerank_failed} =
               Reranker.rerank_chunks("What is Elixir?", @sample_chunks,
                 reranker: FailingReranker
               )
    end
  end

  describe "deduplicate/2" do
    test "removes duplicates by id" do
      chunks = [
        %{id: "c1", content: "Content 1"},
        %{id: "c2", content: "Content 2"},
        %{id: "c1", content: "Content 1 duplicate"}
      ]

      deduped = Reranker.deduplicate(chunks, :id)

      assert length(deduped) == 2
      ids = Enum.map(deduped, & &1.id)
      assert "c1" in ids
      assert "c2" in ids
    end

    test "removes duplicates by content" do
      chunks = [
        %{id: "c1", content: "Same content"},
        %{id: "c2", content: "Different content"},
        %{id: "c3", content: "Same content"}
      ]

      deduped = Reranker.deduplicate(chunks, :content)

      assert length(deduped) == 2
    end

    test "handles empty list" do
      deduped = Reranker.deduplicate([], :id)

      assert deduped == []
    end

    test "preserves order (first occurrence kept)" do
      chunks = [
        %{id: "c1", content: "First", score: 0.9},
        %{id: "c1", content: "Duplicate", score: 0.5}
      ]

      deduped = Reranker.deduplicate(chunks, :id)

      assert length(deduped) == 1
      assert hd(deduped).content == "First"
    end
  end
end
