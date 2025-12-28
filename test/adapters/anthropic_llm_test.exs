defmodule PortfolioIndex.Adapters.LLM.AnthropicTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.LLM.Anthropic

  import Mox

  setup :verify_on_exit!

  describe "complete/2" do
    test "delegates to claude_agent_sdk" do
      expect(ClaudeAgentSdkMock, :complete, fn messages, opts ->
        assert [%{role: "user", content: "Hi"}] = messages
        assert opts == []
        {:ok, %{content: "Hello!", model: "claude-sonnet-4-20250514", usage: %{}}}
      end)

      {:ok, response} = Anthropic.complete([%{role: :user, content: "Hi"}])

      assert response.content == "Hello!"
      assert response.model == "claude-sonnet-4-20250514"
    end

    test "passes model override via opts" do
      expect(ClaudeAgentSdkMock, :complete, fn _messages, opts ->
        assert Keyword.get(opts, :model) == "claude-opus-4-20250514"
        {:ok, %{content: "Hi", model: "claude-opus-4-20250514", usage: %{}}}
      end)

      Anthropic.complete([%{role: :user, content: "Hi"}], model: "claude-opus-4-20250514")
    end
  end

  describe "supported_models/0" do
    test "returns list of models" do
      models = Anthropic.supported_models()
      assert is_list(models)
      assert models != []
    end
  end
end
