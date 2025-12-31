# Mock LLM that says results are sufficient
defmodule PortfolioIndex.Test.SufficientResultsLLM do
  def complete(_messages, _opts) do
    {:ok,
     %{
       content: ~s({"sufficient": true, "reasoning": "Results contain relevant information"})
     }}
  end
end

# Mock LLM that says results are insufficient and provides rewritten query
defmodule PortfolioIndex.Test.InsufficientResultsLLM do
  def complete(messages, _opts) do
    # Determine which prompt this is (sufficiency check or rewrite)
    prompt = messages |> List.first() |> Map.get(:content)

    # Sufficiency prompts contain "Evaluate" and "sufficient"
    is_sufficiency =
      String.contains?(prompt, "Evaluate") and String.contains?(prompt, "sufficient")

    if is_sufficiency do
      {:ok,
       %{
         content:
           ~s({"sufficient": false, "reasoning": "Results don't address the core question"})
       }}
    else
      # This is a rewrite request
      {:ok, %{content: ~s({"query": "improved search query"})}}
    end
  end
end

# Mock LLM that fails
defmodule PortfolioIndex.Test.FailingSearchLLM do
  def complete(_messages, _opts) do
    {:error, :api_error}
  end
end

# Mock search function that returns results
defmodule PortfolioIndex.Test.MockSearcher do
  def search(_query, _opts) do
    {:ok,
     [
       %{id: "chunk1", content: "Result 1 content", score: 0.9, metadata: %{}},
       %{id: "chunk2", content: "Result 2 content", score: 0.8, metadata: %{}}
     ]}
  end

  def search_empty(_query, _opts) do
    {:ok, []}
  end
end

defmodule PortfolioIndex.RAG.SelfCorrectingSearchTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.RAG.Pipeline.Context
  alias PortfolioIndex.RAG.SelfCorrectingSearch
  alias PortfolioIndex.Test.FailingSearchLLM
  alias PortfolioIndex.Test.InsufficientResultsLLM
  alias PortfolioIndex.Test.MockSearcher
  alias PortfolioIndex.Test.SufficientResultsLLM

  describe "search/2" do
    test "returns results when LLM says sufficient" do
      ctx = Context.new("What is Elixir?")

      opts = [
        llm: &SufficientResultsLLM.complete/2,
        search_fn: &MockSearcher.search/2,
        max_iterations: 3
      ]

      result_ctx = SelfCorrectingSearch.search(ctx, opts)

      refute Context.error?(result_ctx)
      assert length(result_ctx.results) == 2
      assert result_ctx.correction_count == 0
    end

    test "iterates when results are insufficient" do
      ctx = Context.new("Complex multi-part question")

      call_count = :counters.new(1, [:atomics])

      search_fn = fn _query, _opts ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        # After a few iterations, return better results
        if count >= 2 do
          {:ok, [%{id: "good", content: "Good result", score: 0.95, metadata: %{}}]}
        else
          {:ok, [%{id: "poor", content: "Poor result", score: 0.3, metadata: %{}}]}
        end
      end

      # Use LLM that toggles between insufficient and sufficient
      iteration = :counters.new(1, [:atomics])

      llm = fn messages, _opts ->
        :counters.add(iteration, 1, 1)
        count = :counters.get(iteration, 1)

        prompt = messages |> List.first() |> Map.get(:content)

        if String.contains?(prompt, "sufficient") do
          if count > 2 do
            {:ok, %{content: ~s({"sufficient": true})}}
          else
            {:ok, %{content: ~s({"sufficient": false, "reasoning": "Need more"})}}
          end
        else
          {:ok, %{content: ~s({"query": "rewritten query #{count}"})}}
        end
      end

      opts = [llm: llm, search_fn: search_fn, max_iterations: 5]

      result_ctx = SelfCorrectingSearch.search(ctx, opts)

      refute Context.error?(result_ctx)
      assert result_ctx.correction_count > 0
    end

    test "stops at max_iterations" do
      ctx = Context.new("Impossible query")

      opts = [
        llm: &InsufficientResultsLLM.complete/2,
        search_fn: &MockSearcher.search/2,
        max_iterations: 2
      ]

      result_ctx = SelfCorrectingSearch.search(ctx, opts)

      # Should stop without error after max iterations
      refute Context.error?(result_ctx)
      assert result_ctx.correction_count <= 2
    end

    test "handles search function errors gracefully" do
      ctx = Context.new("Query")

      failing_search = fn _query, _opts -> {:error, :search_failed} end

      opts = [
        llm: &SufficientResultsLLM.complete/2,
        search_fn: failing_search,
        max_iterations: 3
      ]

      result_ctx = SelfCorrectingSearch.search(ctx, opts)

      assert Context.error?(result_ctx)
      assert result_ctx.error == :search_failed
    end

    test "handles LLM errors gracefully" do
      ctx = Context.new("Query")

      opts = [
        llm: &FailingSearchLLM.complete/2,
        search_fn: &MockSearcher.search/2,
        max_iterations: 3
      ]

      result_ctx = SelfCorrectingSearch.search(ctx, opts)

      # Should return results even if LLM fails (assuming sufficient)
      refute Context.error?(result_ctx)
    end

    test "propagates halted context" do
      ctx = Context.new("Query") |> Context.halt(:previous_error)

      opts = [
        llm: &SufficientResultsLLM.complete/2,
        search_fn: &MockSearcher.search/2
      ]

      result_ctx = SelfCorrectingSearch.search(ctx, opts)

      assert Context.error?(result_ctx)
      assert result_ctx.error == :previous_error
    end

    test "respects min_results option" do
      ctx = Context.new("Query")

      empty_search = fn _query, _opts -> {:ok, []} end

      call_count = :counters.new(1, [:atomics])

      llm = fn messages, _opts ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        prompt = messages |> List.first() |> Map.get(:content)

        if String.contains?(prompt, "sufficient") do
          {:ok, %{content: ~s({"sufficient": false, "reasoning": "No results"})}}
        else
          {:ok, %{content: ~s({"query": "attempt #{count}"})}}
        end
      end

      opts = [
        llm: llm,
        search_fn: empty_search,
        max_iterations: 3,
        min_results: 1
      ]

      _result_ctx = SelfCorrectingSearch.search(ctx, opts)

      # Should try multiple times due to no results meeting min_results
      assert :counters.get(call_count, 1) > 1
    end
  end

  describe "evaluate_sufficiency/3" do
    test "returns true when LLM says sufficient" do
      results = [%{id: "1", content: "Result", score: 0.9, metadata: %{}}]

      {:ok, sufficient, reasoning} =
        SelfCorrectingSearch.evaluate_sufficiency(
          "question",
          results,
          llm: &SufficientResultsLLM.complete/2
        )

      assert sufficient == true
      assert is_binary(reasoning)
    end

    test "returns false when LLM says insufficient" do
      results = [%{id: "1", content: "Result", score: 0.9, metadata: %{}}]

      {:ok, sufficient, reasoning} =
        SelfCorrectingSearch.evaluate_sufficiency(
          "question",
          results,
          llm: &InsufficientResultsLLM.complete/2
        )

      assert sufficient == false
      assert is_binary(reasoning) or is_nil(reasoning)
    end

    test "returns error on LLM failure" do
      results = [%{id: "1", content: "Result", score: 0.9, metadata: %{}}]

      assert {:error, :api_error} =
               SelfCorrectingSearch.evaluate_sufficiency(
                 "question",
                 results,
                 llm: &FailingSearchLLM.complete/2
               )
    end
  end

  describe "rewrite_query/4" do
    test "returns rewritten query" do
      results = [%{id: "1", content: "Result", score: 0.9, metadata: %{}}]
      feedback = "Results don't address the core question"

      {:ok, rewritten} =
        SelfCorrectingSearch.rewrite_query(
          "original query",
          results,
          feedback,
          llm: &InsufficientResultsLLM.complete/2
        )

      assert is_binary(rewritten)
      assert rewritten == "improved search query"
    end

    test "returns error on LLM failure" do
      results = []

      assert {:error, :api_error} =
               SelfCorrectingSearch.rewrite_query(
                 "query",
                 results,
                 "feedback",
                 llm: &FailingSearchLLM.complete/2
               )
    end
  end
end
