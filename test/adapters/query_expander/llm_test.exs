# Mock LLM for query expander testing
defmodule PortfolioIndex.Test.QueryExpander.MockLLM do
  def complete([%{role: :user, content: prompt}], _opts) do
    # The prompt ends with: "Now expand this query:\n\"{query}\"\n"
    cond do
      String.contains?(prompt, ~s|"ML models"|) ->
        {:ok, %{content: "ML machine learning models neural networks deep learning"}}

      String.contains?(prompt, ~s|"GenServer"|) ->
        {:ok, %{content: "GenServer gen_server OTP server process Elixir"}}

      String.contains?(prompt, ~s|"API endpoints"|) ->
        {:ok,
         %{content: "API endpoints application programming interface REST web service routes"}}

      String.contains?(prompt, ~s|"Phoenix LiveView"|) ->
        {:ok,
         %{
           content:
             "Phoenix LiveView real-time live updates websocket server-rendered interactive"
         }}

      true ->
        # Default: return original query
        {:ok, %{content: "expanded query terms"}}
    end
  end
end

defmodule PortfolioIndex.Test.QueryExpander.FailingLLM do
  def complete(_messages, _opts) do
    {:error, :api_error}
  end
end

defmodule PortfolioIndex.Test.QueryExpander.EmptyResponseLLM do
  def complete(_messages, _opts) do
    {:ok, %{content: ""}}
  end
end

defmodule PortfolioIndex.Adapters.QueryExpander.LLMTest do
  use PortfolioIndex.SupertesterCase, async: true

  import ExUnit.CaptureLog

  alias PortfolioIndex.Adapters.QueryExpander.LLM
  alias PortfolioIndex.Test.QueryExpander.EmptyResponseLLM
  alias PortfolioIndex.Test.QueryExpander.FailingLLM
  alias PortfolioIndex.Test.QueryExpander.MockLLM

  describe "expand/2" do
    test "expands abbreviations" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.expand("ML models", opts)

      assert result.original == "ML models"
      assert String.contains?(result.expanded, "machine")
      assert String.contains?(result.expanded, "learning")
      # Terms are split by whitespace, so "machine" and "learning" are separate
      assert "machine" in result.added_terms
      assert "learning" in result.added_terms
    end

    test "expands technical terms" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.expand("GenServer", opts)

      assert String.contains?(result.expanded, "OTP")
      assert "OTP" in result.added_terms
    end

    test "expands API terminology" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.expand("API endpoints", opts)

      assert String.contains?(result.expanded, "REST") or
               String.contains?(result.expanded, "application")
    end

    test "expands Phoenix framework terms" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.expand("Phoenix LiveView", opts)

      assert String.contains?(result.expanded, "real-time") or
               String.contains?(result.expanded, "websocket")
    end

    test "returns error on LLM failure" do
      opts = [context: %{adapters: %{llm: FailingLLM}}]

      capture_log(fn ->
        assert {:error, :api_error} = LLM.expand("test query", opts)
      end)
    end

    test "returns original when LLM returns empty response" do
      opts = [context: %{adapters: %{llm: EmptyResponseLLM}}]
      {:ok, result} = LLM.expand("original query", opts)

      # When LLM returns empty, fall back to original
      assert result.expanded == "original query"
      assert result.added_terms == []
    end

    test "identifies added terms correctly" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.expand("ML models", opts)

      # Should identify that machine learning, neural networks, deep learning were added
      assert result.added_terms != []

      # Original terms should not be in added_terms
      refute "ML" in result.added_terms
      refute "models" in result.added_terms
    end
  end

  describe "edge cases" do
    test "handles empty query" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.expand("", opts)

      assert result.original == ""
    end

    test "handles very long query" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      long_query = String.duplicate("word ", 500)
      {:ok, result} = LLM.expand(long_query, opts)

      assert result.original == long_query
    end

    test "handles unicode characters" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.expand("apprentissage automatique", opts)

      assert is_binary(result.expanded)
    end
  end

  describe "custom prompt support" do
    defmodule CustomPromptLLM do
      def complete([%{role: :user, content: prompt}], _opts) do
        if String.contains?(prompt, "CUSTOM_EXPANSION") do
          {:ok, %{content: "test custom expanded synonyms"}}
        else
          {:ok, %{content: "default expansion"}}
        end
      end
    end

    test "uses custom prompt when provided" do
      custom_prompt = fn query -> "CUSTOM_EXPANSION: #{query}" end
      opts = [context: %{adapters: %{llm: CustomPromptLLM}}, prompt: custom_prompt]

      {:ok, result} = LLM.expand("test", opts)
      assert String.contains?(result.expanded, "custom")
    end
  end
end
