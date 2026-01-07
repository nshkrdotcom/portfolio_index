# Mock LLM for query decomposer testing
defmodule PortfolioIndex.Test.QueryDecomposer.MockLLM do
  def complete([%{role: :user, content: prompt}], _opts) do
    # The prompt structure is:
    # "...Now decompose this question:\n\"{query}\"\n\nReturn JSON only: ..."
    # Extract the actual user query from between "Now decompose this question:" and "Return JSON"
    user_query = extract_user_query(prompt)

    cond do
      String.contains?(user_query, "Compare Elixir and Go") ->
        {:ok,
         %{
           content: """
           {"sub_questions": ["What are Elixir's features for web development?", "What are Go's features for web development?", "How do Elixir and Go compare in performance?"]}
           """
         }}

      String.contains?(user_query, "Phoenix") and String.contains?(user_query, "React") ->
        {:ok,
         %{
           content: """
           {"sub_questions": ["How does Phoenix LiveView handle real-time updates?", "How does React handle real-time updates?"]}
           """
         }}

      String.contains?(user_query, "What is pattern matching?") ->
        {:ok, %{content: ~s|{"sub_questions": ["What is pattern matching?"]}|}}

      String.contains?(user_query, "explain GenServer") ->
        {:ok, %{content: ~s|{"sub_questions": ["What is GenServer and how does it work?"]}|}}

      true ->
        {:ok, %{content: ~s|{"sub_questions": ["simple question"]}|}}
    end
  end

  defp extract_user_query(prompt) do
    # Extract the user query from between "Now decompose this question:" and "Return JSON"
    case Regex.run(~r/Now decompose this question:\s*"(.+?)"\s*\n\s*Return JSON/s, prompt) do
      [_, query] -> query
      _ -> ""
    end
  end
end

defmodule PortfolioIndex.Test.QueryDecomposer.FailingLLM do
  def complete(_messages, _opts) do
    {:error, :api_error}
  end
end

defmodule PortfolioIndex.Test.QueryDecomposer.InvalidJsonLLM do
  def complete(_messages, _opts) do
    {:ok, %{content: "This is not valid JSON at all"}}
  end
end

defmodule PortfolioIndex.Test.QueryDecomposer.EmptyArrayLLM do
  def complete(_messages, _opts) do
    {:ok, %{content: ~s|{"sub_questions": []}|}}
  end
end

defmodule PortfolioIndex.Test.QueryDecomposer.AlternateKeyLLM do
  def complete(_messages, _opts) do
    {:ok, %{content: ~s|{"questions": ["q1", "q2"]}|}}
  end
end

defmodule PortfolioIndex.Adapters.QueryDecomposer.LLMTest do
  use PortfolioIndex.SupertesterCase, async: true

  import ExUnit.CaptureLog

  alias PortfolioIndex.Adapters.QueryDecomposer.LLM
  alias PortfolioIndex.Test.QueryDecomposer.AlternateKeyLLM
  alias PortfolioIndex.Test.QueryDecomposer.EmptyArrayLLM
  alias PortfolioIndex.Test.QueryDecomposer.FailingLLM
  alias PortfolioIndex.Test.QueryDecomposer.InvalidJsonLLM
  alias PortfolioIndex.Test.QueryDecomposer.MockLLM

  describe "decompose/2" do
    test "decomposes comparison questions" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.decompose("Compare Elixir and Go for web services", opts)

      assert result.original == "Compare Elixir and Go for web services"
      assert result.is_complex == true
      assert length(result.sub_questions) >= 2
      assert Enum.any?(result.sub_questions, &String.contains?(&1, "Elixir"))
      assert Enum.any?(result.sub_questions, &String.contains?(&1, "Go"))
    end

    test "decomposes multi-part technical questions" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.decompose("How does Phoenix LiveView compare to React?", opts)

      assert result.is_complex == true
      assert length(result.sub_questions) >= 2
    end

    test "simple questions remain unchanged" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.decompose("What is pattern matching?", opts)

      # Single sub-question means not complex
      assert length(result.sub_questions) == 1
    end

    test "returns error on LLM failure" do
      opts = [context: %{adapters: %{llm: FailingLLM}}]

      capture_log(fn ->
        assert {:error, :api_error} = LLM.decompose("test query", opts)
      end)
    end

    test "falls back to original on invalid JSON" do
      opts = [context: %{adapters: %{llm: InvalidJsonLLM}}]
      {:ok, result} = LLM.decompose("my original question", opts)

      # Should fall back to the original as single sub-question
      assert result.sub_questions == ["my original question"]
      assert result.is_complex == false
    end

    test "falls back to original on empty sub_questions array" do
      opts = [context: %{adapters: %{llm: EmptyArrayLLM}}]
      {:ok, result} = LLM.decompose("original question", opts)

      assert result.sub_questions == ["original question"]
    end

    test "handles alternate JSON keys" do
      opts = [context: %{adapters: %{llm: AlternateKeyLLM}}]
      {:ok, result} = LLM.decompose("test", opts)

      # Should handle "questions" key as alternative to "sub_questions"
      assert result.sub_questions == ["q1", "q2"]
    end
  end

  describe "edge cases" do
    test "handles empty query" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.decompose("", opts)

      assert result.original == ""
    end

    test "handles very long query" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      long_query = String.duplicate("word ", 500)
      {:ok, result} = LLM.decompose(long_query, opts)

      assert result.original == long_query
    end

    test "handles unicode characters" do
      opts = [context: %{adapters: %{llm: MockLLM}}]
      {:ok, result} = LLM.decompose("Comparer Elixir et Go", opts)

      assert is_list(result.sub_questions)
    end
  end

  describe "custom prompt support" do
    defmodule CustomPromptLLM do
      def complete([%{role: :user, content: prompt}], _opts) do
        if String.contains?(prompt, "CUSTOM_DECOMPOSE") do
          {:ok, %{content: ~s|{"sub_questions": ["custom q1", "custom q2"]}|}}
        else
          {:ok, %{content: ~s|{"sub_questions": ["default"]}|}}
        end
      end
    end

    test "uses custom prompt when provided" do
      custom_prompt = fn query -> "CUSTOM_DECOMPOSE: #{query}" end
      opts = [context: %{adapters: %{llm: CustomPromptLLM}}, prompt: custom_prompt]

      {:ok, result} = LLM.decompose("test", opts)
      assert result.sub_questions == ["custom q1", "custom q2"]
    end
  end
end
