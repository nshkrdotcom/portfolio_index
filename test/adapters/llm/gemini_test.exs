defmodule PortfolioIndex.Adapters.LLM.GeminiTest do
  use ExUnit.Case, async: true

  alias Elixir.Gemini.Config, as: GeminiConfig
  alias PortfolioIndex.Adapters.LLM.Gemini

  describe "supported_models/0" do
    test "returns list of supported models" do
      models = Gemini.supported_models()
      assert is_list(models)
      assert GeminiConfig.get_model(:flash_2_5) in models
    end
  end

  describe "model_info/1" do
    test "returns info for gemini-2.5-flash" do
      info = Gemini.model_info(GeminiConfig.get_model(:flash_2_5))

      assert is_map(info)
      assert info.context_window > 0
      assert info.max_output > 0
      assert is_boolean(info.supports_tools)
    end

    test "returns default info for unknown model" do
      info = Gemini.model_info("unknown-model")

      assert is_map(info)
      assert info.context_window > 0
    end
  end

  # Integration tests would require real API access
  # Run with: mix test --include integration
  describe "complete/2 integration" do
    @tag :skip
    test "completes messages" do
      messages = [
        %{role: :user, content: "Say hello in one word"}
      ]

      {:ok, result} = Gemini.complete(messages, max_tokens: 10)

      assert is_binary(result.content)
      assert result.model == GeminiConfig.default_model()
      assert is_map(result.usage)
    end
  end
end
