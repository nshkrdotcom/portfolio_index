defmodule PortfolioIndex.Adapters.LLM.AnthropicTest do
  use PortfolioIndex.SupertesterCase, async: true

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

  describe "stream/2" do
    test "streams chunks using the configured sdk" do
      expect(ClaudeAgentSdkMock, :stream, fn messages, _opts ->
        assert [%{role: "user", content: "Stream"}] = messages
        ["Hello", " ", "Claude"]
      end)

      {:ok, stream} = Anthropic.stream([%{role: :user, content: "Stream"}])
      chunks = Enum.to_list(stream)

      assert Enum.map(chunks, & &1.delta) == ["Hello", " ", "Claude"]
    end
  end

  describe "complete/2 live" do
    if System.get_env("ANTHROPIC_API_KEY") do
      @tag :live
      test "completes messages via Claude API" do
        original_sdk = Application.get_env(:portfolio_index, :anthropic_sdk)
        Application.put_env(:portfolio_index, :anthropic_sdk, ClaudeAgentSDK)

        on_exit(fn ->
          Application.put_env(:portfolio_index, :anthropic_sdk, original_sdk)
        end)

        {:ok, result} =
          Anthropic.complete([%{role: :user, content: "Say hello in one word"}], max_tokens: 10)

        assert is_binary(result.content)
        assert result.model != nil
      end
    else
      @tag :live
      @tag skip: "ANTHROPIC_API_KEY is not set"
      test "completes messages via Claude API" do
        :ok
      end
    end
  end
end
