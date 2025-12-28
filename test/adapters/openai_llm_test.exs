defmodule PortfolioIndex.Adapters.LLM.OpenAITest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.LLM.OpenAI

  import Mox

  setup :verify_on_exit!

  describe "complete/2" do
    test "delegates to codex_sdk" do
      expect(CodexSdkMock, :complete, fn messages, opts ->
        assert [%{role: "user", content: "Hi"}] = messages
        assert opts == []
        {:ok, %{content: "Hello!", model: "gpt-4o", usage: %{}}}
      end)

      {:ok, response} = OpenAI.complete([%{role: :user, content: "Hi"}])

      assert response.content == "Hello!"
      assert response.model == "gpt-4o"
    end

    test "passes model override via opts" do
      expect(CodexSdkMock, :complete, fn _messages, opts ->
        assert Keyword.get(opts, :model) == "o1"
        {:ok, %{content: "Hi", model: "o1", usage: %{}}}
      end)

      OpenAI.complete([%{role: :user, content: "Hi"}], model: "o1")
    end
  end

  describe "supported_models/0" do
    test "returns list of models" do
      models = OpenAI.supported_models()
      assert is_list(models)
      assert models != []
    end
  end
end
