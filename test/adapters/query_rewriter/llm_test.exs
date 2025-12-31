# Mock LLM for query rewriter testing
defmodule PortfolioIndex.Test.QueryRewriter.MockLLM do
  def complete([%{role: :user, content: prompt}], _opts) do
    # Extract the query from the end of the prompt (after "Now rewrite this input:")
    # Need to check at end of prompt to avoid matching examples
    cond do
      String.ends_with?(String.trim(prompt), ~s|"Hey, what is Elixir?"|) ->
        {:ok, %{content: "what is Elixir"}}

      String.ends_with?(String.trim(prompt), ~s|"Hello, can you help me understand GenServer?"|) ->
        {:ok, %{content: "understand GenServer in Elixir"}}

      String.ends_with?(String.trim(prompt), ~s|"What is pattern matching?"|) ->
        {:ok, %{content: "What is pattern matching?"}}

      String.ends_with?(String.trim(prompt), ~s|"Please tell me about Phoenix LiveView"|) ->
        {:ok, %{content: "Phoenix LiveView real-time features"}}

      true ->
        # Default: return trimmed version
        {:ok, %{content: "cleaned query"}}
    end
  end
end

defmodule PortfolioIndex.Test.QueryRewriter.FailingLLM do
  def complete(_messages, _opts) do
    {:error, :api_error}
  end
end

defmodule PortfolioIndex.Test.QueryRewriter.EmptyResponseLLM do
  def complete(_messages, _opts) do
    {:ok, %{content: ""}}
  end
end

defmodule PortfolioIndex.Test.QueryRewriter.WhitespaceResponseLLM do
  def complete(_messages, _opts) do
    {:ok, %{content: "   \n\t  "}}
  end
end

defmodule PortfolioIndex.Adapters.QueryRewriter.LLMTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.QueryRewriter.LLM
  alias PortfolioIndex.Test.QueryRewriter.EmptyResponseLLM
  alias PortfolioIndex.Test.QueryRewriter.FailingLLM
  alias PortfolioIndex.Test.QueryRewriter.MockLLM
  alias PortfolioIndex.Test.QueryRewriter.WhitespaceResponseLLM

  describe "rewrite/2" do
    test "rewrites conversational query" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.rewrite("Hey, what is Elixir?", opts)

      assert result.original == "Hey, what is Elixir?"
      assert result.rewritten == "what is Elixir"
      assert is_list(result.changes_made)
    end

    test "removes greetings and politeness markers" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.rewrite("Hello, can you help me understand GenServer?", opts)

      assert result.rewritten == "understand GenServer in Elixir"
    end

    test "preserves already clean queries" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.rewrite("What is pattern matching?", opts)

      assert result.rewritten == "What is pattern matching?"
    end

    test "handles query with please prefix" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.rewrite("Please tell me about Phoenix LiveView", opts)

      assert result.rewritten == "Phoenix LiveView real-time features"
    end

    test "returns error on LLM failure" do
      opts = [context: %{adapters: %{llm: FailingLLM}}]
      result = LLM.rewrite("test query", opts)

      assert {:error, :api_error} = result
    end

    test "returns original when LLM returns empty response" do
      opts = [context: %{adapters: %{llm: EmptyResponseLLM}}]
      {:ok, result} = LLM.rewrite("original query", opts)

      # When LLM returns empty, fall back to original
      assert result.rewritten == "original query"
      assert result.original == "original query"
    end

    test "returns original when LLM returns only whitespace" do
      opts = [context: %{adapters: %{llm: WhitespaceResponseLLM}}]
      {:ok, result} = LLM.rewrite("original query", opts)

      # When LLM returns whitespace-only, fall back to original
      assert result.rewritten == "original query"
    end
  end

  describe "edge cases" do
    test "handles empty query" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.rewrite("", opts)

      assert result.original == ""
    end

    test "handles very long query" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      long_query = String.duplicate("word ", 500)
      {:ok, result} = LLM.rewrite(long_query, opts)

      assert result.original == long_query
    end

    test "handles unicode characters" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.rewrite("Qu'est-ce que l'Elixir?", opts)

      assert is_binary(result.rewritten)
    end
  end

  describe "custom prompt support" do
    defmodule CustomPromptLLM do
      def complete([%{role: :user, content: prompt}], _opts) do
        if String.contains?(prompt, "CUSTOM_MARKER") do
          {:ok, %{content: "custom prompt worked"}}
        else
          {:ok, %{content: "default prompt"}}
        end
      end
    end

    test "uses custom prompt when provided" do
      custom_prompt = fn query -> "CUSTOM_MARKER: #{query}" end
      opts = [context: %{adapters: %{llm: CustomPromptLLM}}, prompt: custom_prompt]

      {:ok, result} = LLM.rewrite("test", opts)
      assert result.rewritten == "custom prompt worked"
    end
  end
end
