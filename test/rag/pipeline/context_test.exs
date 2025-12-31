defmodule PortfolioIndex.RAG.Pipeline.ContextTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.RAG.Pipeline.Context

  describe "new/2" do
    test "creates context with question" do
      ctx = Context.new("What is Elixir?")

      assert ctx.question == "What is Elixir?"
      assert ctx.opts == []
      assert ctx.halted? == false
      assert ctx.error == nil
    end

    test "creates context with question and options" do
      ctx = Context.new("What is Elixir?", max_tokens: 1000, temperature: 0.7)

      assert ctx.question == "What is Elixir?"
      assert ctx.opts == [max_tokens: 1000, temperature: 0.7]
    end

    test "initializes all fields to defaults" do
      ctx = Context.new("test")

      assert ctx.rewritten_query == nil
      assert ctx.expanded_query == nil
      assert ctx.sub_questions == []
      assert ctx.selected_indexes == []
      assert ctx.selection_reasoning == nil
      assert ctx.results == []
      assert ctx.rerank_scores == %{}
      assert ctx.answer == nil
      assert ctx.context_used == []
      assert ctx.correction_count == 0
      assert ctx.corrections == []
    end
  end

  describe "halt/2" do
    test "marks context as halted with error" do
      ctx = Context.new("test")
      halted = Context.halt(ctx, :llm_failure)

      assert halted.halted? == true
      assert halted.error == :llm_failure
    end

    test "preserves existing data when halting" do
      ctx = %{Context.new("test") | rewritten_query: "processed test"}
      halted = Context.halt(ctx, :timeout)

      assert halted.question == "test"
      assert halted.rewritten_query == "processed test"
      assert halted.halted? == true
      assert halted.error == :timeout
    end
  end

  describe "error?/1" do
    test "returns false for fresh context" do
      ctx = Context.new("test")
      refute Context.error?(ctx)
    end

    test "returns true for halted context" do
      ctx = Context.new("test") |> Context.halt(:error)
      assert Context.error?(ctx)
    end

    test "returns true when error field is set" do
      ctx = %{Context.new("test") | error: :some_error}
      assert Context.error?(ctx)
    end
  end

  describe "struct fields" do
    test "can set rewritten_query" do
      ctx = %{Context.new("hey, what is Elixir?") | rewritten_query: "what is Elixir"}
      assert ctx.rewritten_query == "what is Elixir"
    end

    test "can set expanded_query" do
      ctx = %{Context.new("ML") | expanded_query: "ML machine learning"}
      assert ctx.expanded_query == "ML machine learning"
    end

    test "can set sub_questions" do
      ctx = %{Context.new("Compare A and B") | sub_questions: ["What is A?", "What is B?"]}
      assert ctx.sub_questions == ["What is A?", "What is B?"]
    end

    test "can set selected_indexes" do
      ctx = %{Context.new("test") | selected_indexes: ["docs", "api"]}
      assert ctx.selected_indexes == ["docs", "api"]
    end

    test "can set results" do
      results = [%{content: "Result 1", score: 0.9}]
      ctx = %{Context.new("test") | results: results}
      assert ctx.results == results
    end

    test "can set rerank_scores" do
      scores = %{"chunk_1" => 0.9, "chunk_2" => 0.7}
      ctx = %{Context.new("test") | rerank_scores: scores}
      assert ctx.rerank_scores == scores
    end

    test "can set answer and context_used" do
      ctx = %{Context.new("test") | answer: "The answer is 42", context_used: [%{id: "1"}]}
      assert ctx.answer == "The answer is 42"
      assert ctx.context_used == [%{id: "1"}]
    end

    test "can track corrections" do
      ctx = %{
        Context.new("test")
        | correction_count: 2,
          corrections: [{"old answer", "feedback 1"}, {"better answer", "feedback 2"}]
      }

      assert ctx.correction_count == 2
      assert length(ctx.corrections) == 2
    end
  end

  describe "edge cases" do
    test "handles empty question" do
      ctx = Context.new("")
      assert ctx.question == ""
    end

    test "handles very long question" do
      long_question = String.duplicate("word ", 10_000)
      ctx = Context.new(long_question)
      assert ctx.question == long_question
    end

    test "handles unicode in question" do
      ctx = Context.new("Qu'est-ce que l'Elixir? ")
      assert ctx.question == "Qu'est-ce que l'Elixir? "
    end
  end
end
