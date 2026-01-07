# Mock LLMs for query processor testing
defmodule PortfolioIndex.Test.QueryProcessor.RewriterMockLLM do
  def complete([%{role: :user, content: prompt}], _opts) do
    cond do
      String.contains?(prompt, ~s|"Hey, what is Elixir?"|) ->
        {:ok, %{content: "what is Elixir"}}

      String.contains?(prompt, ~s|"Hello, can you explain"|) ->
        {:ok, %{content: "explain GenServer"}}

      true ->
        {:ok, %{content: "rewritten query"}}
    end
  end
end

defmodule PortfolioIndex.Test.QueryProcessor.ExpanderMockLLM do
  def complete([%{role: :user, content: prompt}], _opts) do
    cond do
      String.contains?(prompt, ~s|"ML models"|) ->
        {:ok, %{content: "ML machine learning models neural networks"}}

      String.contains?(prompt, ~s|"GenServer"|) ->
        {:ok, %{content: "GenServer gen_server OTP process"}}

      true ->
        {:ok, %{content: "expanded query terms"}}
    end
  end
end

defmodule PortfolioIndex.Test.QueryProcessor.DecomposerMockLLM do
  def complete([%{role: :user, content: prompt}], _opts) do
    if String.contains?(prompt, ~s|"Compare|) do
      {:ok,
       %{content: ~s|{"sub_questions": ["What is A?", "What is B?", "How do they compare?"]}|}}
    else
      # Extract and return as single question
      {:ok, %{content: ~s|{"sub_questions": ["simple question"]}|}}
    end
  end
end

defmodule PortfolioIndex.Test.QueryProcessor.FailingLLM do
  def complete(_messages, _opts) do
    {:error, :api_error}
  end
end

defmodule PortfolioIndex.Test.QueryProcessor.AllInOneMockLLM do
  def complete([%{role: :user, content: prompt}], _opts) do
    cond do
      # Rewriter detection
      String.contains?(prompt, "rewrite") or String.contains?(prompt, "optimizer") ->
        {:ok, %{content: "clean query"}}

      # Expander detection
      String.contains?(prompt, "expand") or String.contains?(prompt, "synonyms") ->
        {:ok, %{content: "expanded query terms"}}

      # Decomposer detection
      String.contains?(prompt, "decompose") or String.contains?(prompt, "sub-questions") ->
        {:ok, %{content: ~s|{"sub_questions": ["q1"]}|}}

      true ->
        {:ok, %{content: "processed"}}
    end
  end
end

defmodule PortfolioIndex.RAG.QueryProcessorTest do
  use PortfolioIndex.SupertesterCase, async: true

  import ExUnit.CaptureLog

  alias PortfolioIndex.RAG.Pipeline.Context
  alias PortfolioIndex.RAG.QueryProcessor
  alias PortfolioIndex.Test.QueryProcessor.AllInOneMockLLM
  alias PortfolioIndex.Test.QueryProcessor.DecomposerMockLLM
  alias PortfolioIndex.Test.QueryProcessor.ExpanderMockLLM
  alias PortfolioIndex.Test.QueryProcessor.FailingLLM
  alias PortfolioIndex.Test.QueryProcessor.RewriterMockLLM

  describe "rewrite/2" do
    test "rewrites query in context" do
      ctx = Context.new("Hey, what is Elixir?")
      opts = [context: %{adapters: %{llm: RewriterMockLLM}}]

      result = QueryProcessor.rewrite(ctx, opts)

      assert result.rewritten_query == "what is Elixir"
      assert result.question == "Hey, what is Elixir?"
    end

    test "skips if context is halted" do
      ctx = Context.new("test") |> Context.halt(:error)
      opts = [context: %{adapters: %{llm: RewriterMockLLM}}]

      result = QueryProcessor.rewrite(ctx, opts)

      assert result.halted? == true
      assert result.rewritten_query == nil
    end

    test "does not halt on rewrite failure" do
      ctx = Context.new("test")
      opts = [context: %{adapters: %{llm: FailingLLM}}]

      capture_log(fn ->
        result = QueryProcessor.rewrite(ctx, opts)

        # Failure is graceful - context continues without rewrite
        refute result.halted?
        assert result.rewritten_query == nil
      end)
    end
  end

  describe "expand/2" do
    test "expands query in context" do
      ctx = Context.new("ML models")
      opts = [context: %{adapters: %{llm: ExpanderMockLLM}}]

      result = QueryProcessor.expand(ctx, opts)

      assert String.contains?(result.expanded_query, "machine learning")
    end

    test "uses rewritten_query if available" do
      ctx = %{Context.new("original") | rewritten_query: "GenServer"}
      opts = [context: %{adapters: %{llm: ExpanderMockLLM}}]

      result = QueryProcessor.expand(ctx, opts)

      # The expander expands "GenServer" which matches the mock
      assert String.contains?(result.expanded_query, "gen_server") or
               String.contains?(result.expanded_query, "OTP")
    end

    test "skips if context is halted" do
      ctx = Context.new("test") |> Context.halt(:error)
      opts = [context: %{adapters: %{llm: ExpanderMockLLM}}]

      result = QueryProcessor.expand(ctx, opts)

      assert result.halted? == true
      assert result.expanded_query == nil
    end
  end

  describe "decompose/2" do
    test "decomposes complex query in context" do
      ctx = Context.new("Compare Elixir and Go")
      opts = [context: %{adapters: %{llm: DecomposerMockLLM}}]

      result = QueryProcessor.decompose(ctx, opts)

      assert length(result.sub_questions) >= 2
    end

    test "simple questions get single sub_question" do
      ctx = Context.new("What is pattern matching?")
      opts = [context: %{adapters: %{llm: DecomposerMockLLM}}]

      result = QueryProcessor.decompose(ctx, opts)

      assert length(result.sub_questions) == 1
    end

    test "skips if context is halted" do
      ctx = Context.new("test") |> Context.halt(:error)
      opts = [context: %{adapters: %{llm: DecomposerMockLLM}}]

      result = QueryProcessor.decompose(ctx, opts)

      assert result.halted? == true
      assert result.sub_questions == []
    end
  end

  describe "process/2 - full pipeline" do
    test "runs all processing steps" do
      ctx = Context.new("Hey, what is Elixir?")
      opts = [context: %{adapters: %{llm: AllInOneMockLLM}}]

      result = QueryProcessor.process(ctx, opts)

      assert result.rewritten_query != nil
      assert result.expanded_query != nil
      assert result.sub_questions != []
    end

    test "can skip steps with options" do
      ctx = Context.new("test query")
      opts = [context: %{adapters: %{llm: AllInOneMockLLM}}, skip: [:expand, :decompose]]

      result = QueryProcessor.process(ctx, opts)

      assert result.rewritten_query != nil
      # These should be skipped
      assert result.expanded_query == nil
      assert result.sub_questions == []
    end

    test "halts immediately if context is halted" do
      ctx = Context.new("test") |> Context.halt(:initial_error)
      opts = [context: %{adapters: %{llm: AllInOneMockLLM}}]

      result = QueryProcessor.process(ctx, opts)

      assert result.halted? == true
      assert result.error == :initial_error
    end
  end

  describe "effective_query/1" do
    test "returns expanded_query if present" do
      ctx = %{Context.new("original") | expanded_query: "expanded", rewritten_query: "rewritten"}
      assert QueryProcessor.effective_query(ctx) == "expanded"
    end

    test "returns rewritten_query if no expanded_query" do
      ctx = %{Context.new("original") | rewritten_query: "rewritten"}
      assert QueryProcessor.effective_query(ctx) == "rewritten"
    end

    test "returns question if no processing done" do
      ctx = Context.new("original")
      assert QueryProcessor.effective_query(ctx) == "original"
    end
  end

  describe "pipe composition" do
    test "supports pipe operator for composition" do
      opts = [context: %{adapters: %{llm: AllInOneMockLLM}}]

      result =
        Context.new("Hey, tell me about Elixir")
        |> QueryProcessor.rewrite(opts)
        |> QueryProcessor.expand(opts)
        |> QueryProcessor.decompose(opts)

      refute result.halted?
      assert result.rewritten_query != nil
      assert result.expanded_query != nil
      assert is_list(result.sub_questions)
    end
  end
end
