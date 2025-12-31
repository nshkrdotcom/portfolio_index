# Mock LLM that generates an answer
defmodule PortfolioIndex.Test.AnswerGeneratorLLM do
  def complete(messages, _opts) do
    prompt = messages |> List.first() |> Map.get(:content)

    cond do
      # Answer generation request
      String.contains?(prompt, "Question:") and String.contains?(prompt, "Context:") and
          not String.contains?(prompt, "grounded") ->
        {:ok, %{content: "Elixir is a functional programming language built on Erlang."}}

      # Grounding evaluation - says grounded
      String.contains?(prompt, "grounded") or String.contains?(prompt, "Evaluate") ->
        {:ok, %{content: ~s({"grounded": true, "score": 0.95, "ungrounded_claims": []})}}

      # Correction request
      String.contains?(prompt, "improve") or String.contains?(prompt, "feedback") ->
        {:ok, %{content: "Corrected answer based on feedback."}}

      true ->
        {:ok, %{content: "Default answer."}}
    end
  end
end

# Mock LLM that generates ungrounded answer
defmodule PortfolioIndex.Test.UngroundedAnswerLLM do
  def complete(messages, _opts) do
    prompt = messages |> List.first() |> Map.get(:content)

    cond do
      String.contains?(prompt, "grounded") or String.contains?(prompt, "Evaluate") ->
        {:ok,
         %{
           content:
             ~s({"grounded": false, "score": 0.3, "ungrounded_claims": ["Claim 1 is not supported"], "feedback": "The answer makes claims not in context"})
         }}

      String.contains?(prompt, "improve") or String.contains?(prompt, "feedback") ->
        {:ok, %{content: "Corrected grounded answer."}}

      true ->
        {:ok, %{content: "Initial ungrounded answer with hallucinated facts."}}
    end
  end
end

# Mock LLM that fails
defmodule PortfolioIndex.Test.FailingAnswerLLM do
  def complete(_messages, _opts) do
    {:error, :api_timeout}
  end
end

defmodule PortfolioIndex.RAG.SelfCorrectingAnswerTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.RAG.Pipeline.Context
  alias PortfolioIndex.RAG.SelfCorrectingAnswer
  alias PortfolioIndex.Test.AnswerGeneratorLLM
  alias PortfolioIndex.Test.FailingAnswerLLM
  alias PortfolioIndex.Test.UngroundedAnswerLLM

  @sample_chunks [
    %{
      id: "1",
      content: "Elixir is a functional programming language.",
      score: 0.9,
      metadata: %{}
    },
    %{id: "2", content: "Elixir runs on the Erlang VM (BEAM).", score: 0.85, metadata: %{}}
  ]

  describe "answer/2" do
    test "generates answer without correction when grounded" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      opts = [llm: &AnswerGeneratorLLM.complete/2]

      result_ctx = SelfCorrectingAnswer.answer(ctx, opts)

      refute Context.error?(result_ctx)
      assert is_binary(result_ctx.answer)
      assert result_ctx.correction_count == 0
    end

    test "performs correction when answer is ungrounded" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      # Track iterations
      iteration = :counters.new(1, [:atomics])

      llm = fn messages, _opts ->
        :counters.add(iteration, 1, 1)
        count = :counters.get(iteration, 1)
        _prompt = messages |> List.first() |> Map.get(:content)

        cond do
          # First answer generation
          count == 1 ->
            {:ok, %{content: "Initial ungrounded answer."}}

          # First grounding check - not grounded
          count == 2 ->
            {:ok,
             %{
               content:
                 ~s({"grounded": false, "score": 0.3, "ungrounded_claims": ["Bad claim"], "feedback": "Needs improvement"})
             }}

          # Correction
          count == 3 ->
            {:ok, %{content: "Corrected grounded answer."}}

          # Second grounding check - now grounded
          count == 4 ->
            {:ok, %{content: ~s({"grounded": true, "score": 0.9})}}

          true ->
            {:ok, %{content: "Fallback"}}
        end
      end

      opts = [llm: llm, max_corrections: 3]

      result_ctx = SelfCorrectingAnswer.answer(ctx, opts)

      refute Context.error?(result_ctx)
      assert result_ctx.correction_count >= 1
      assert result_ctx.corrections != []
    end

    test "stops at max_corrections" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      opts = [llm: &UngroundedAnswerLLM.complete/2, max_corrections: 2]

      result_ctx = SelfCorrectingAnswer.answer(ctx, opts)

      # Should stop after max corrections
      refute Context.error?(result_ctx)
      assert result_ctx.correction_count <= 2
    end

    test "handles LLM errors gracefully" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      opts = [llm: &FailingAnswerLLM.complete/2]

      result_ctx = SelfCorrectingAnswer.answer(ctx, opts)

      assert Context.error?(result_ctx)
    end

    test "propagates halted context" do
      ctx =
        %Context{question: "What?", results: [], opts: []}
        |> Context.halt(:previous_error)

      opts = [llm: &AnswerGeneratorLLM.complete/2]

      result_ctx = SelfCorrectingAnswer.answer(ctx, opts)

      assert Context.error?(result_ctx)
      assert result_ctx.error == :previous_error
    end

    test "uses context_used from results" do
      ctx = %Context{
        question: "What is Elixir?",
        results: @sample_chunks,
        opts: []
      }

      opts = [llm: &AnswerGeneratorLLM.complete/2]

      result_ctx = SelfCorrectingAnswer.answer(ctx, opts)

      assert result_ctx.context_used == @sample_chunks
    end
  end

  describe "generate_answer/3" do
    test "generates answer from question and chunks" do
      {:ok, answer} =
        SelfCorrectingAnswer.generate_answer(
          "What is Elixir?",
          @sample_chunks,
          llm: &AnswerGeneratorLLM.complete/2
        )

      assert is_binary(answer)
    end

    test "returns error on LLM failure" do
      assert {:error, :api_timeout} =
               SelfCorrectingAnswer.generate_answer(
                 "What is Elixir?",
                 @sample_chunks,
                 llm: &FailingAnswerLLM.complete/2
               )
    end
  end

  describe "evaluate_grounding/4" do
    test "returns grounded result" do
      {:ok, result} =
        SelfCorrectingAnswer.evaluate_grounding(
          "What is Elixir?",
          "Elixir is a functional language.",
          @sample_chunks,
          llm: &AnswerGeneratorLLM.complete/2
        )

      assert result.grounded == true
      assert is_float(result.score)
    end

    test "returns ungrounded result with claims" do
      {:ok, result} =
        SelfCorrectingAnswer.evaluate_grounding(
          "What is Elixir?",
          "Ungrounded answer.",
          @sample_chunks,
          llm: &UngroundedAnswerLLM.complete/2
        )

      assert result.grounded == false
      assert is_list(result.ungrounded_claims)
      assert result.ungrounded_claims != []
    end

    test "returns error on LLM failure" do
      assert {:error, :api_timeout} =
               SelfCorrectingAnswer.evaluate_grounding(
                 "question",
                 "answer",
                 @sample_chunks,
                 llm: &FailingAnswerLLM.complete/2
               )
    end
  end

  describe "correct_answer/5" do
    test "generates corrected answer" do
      grounding_result = %{
        grounded: false,
        score: 0.3,
        ungrounded_claims: ["Claim not supported"],
        feedback: "Answer makes unsupported claims"
      }

      {:ok, corrected} =
        SelfCorrectingAnswer.correct_answer(
          "What is Elixir?",
          "Original answer",
          grounding_result,
          @sample_chunks,
          llm: &UngroundedAnswerLLM.complete/2
        )

      assert is_binary(corrected)
    end

    test "returns error on LLM failure" do
      grounding_result = %{
        grounded: false,
        score: 0.3,
        ungrounded_claims: [],
        feedback: "feedback"
      }

      assert {:error, :api_timeout} =
               SelfCorrectingAnswer.correct_answer(
                 "question",
                 "answer",
                 grounding_result,
                 @sample_chunks,
                 llm: &FailingAnswerLLM.complete/2
               )
    end
  end
end
