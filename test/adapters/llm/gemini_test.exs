defmodule PortfolioIndex.Adapters.LLM.GeminiTest do
  use PortfolioIndex.SupertesterCase, async: true

  import Mox

  alias Elixir.Gemini, as: GeminiSdk
  alias Elixir.Gemini.Config, as: GeminiConfig
  alias Gemini.Types.Response.{GenerateContentResponse, UsageMetadata}
  alias PortfolioIndex.Adapters.LLM.Gemini

  setup :verify_on_exit!

  defmodule TestGeminiStream do
    def stream_generate(_prompt, opts) do
      opts[:on_chunk].("Hello")
      opts[:on_chunk].(" Gemini")
      opts[:on_complete].()
      {:ok, :stream_id}
    end
  end

  describe "supported_models/0" do
    test "returns list of supported models" do
      models = Gemini.supported_models()
      assert is_list(models)
      assert GeminiConfig.default_model() in models
    end
  end

  describe "model_info/1" do
    test "returns info for default model" do
      info = Gemini.model_info(GeminiConfig.default_model())

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

  describe "complete/2" do
    test "returns content using the configured sdk" do
      model = GeminiConfig.default_model()

      response = %GenerateContentResponse{
        candidates: [%{content: %{parts: [%{text: "Hello"}]}, finish_reason: "STOP"}],
        usage_metadata: %UsageMetadata{
          prompt_token_count: 2,
          candidates_token_count: 1,
          total_token_count: 3
        }
      }

      GeminiSdkMock
      |> expect(:generate, fn prompt, opts ->
        assert prompt == "User: Hi"
        assert Keyword.get(opts, :model) == model
        {:ok, response}
      end)
      |> expect(:extract_text, fn ^response -> {:ok, "Hello"} end)

      {:ok, result} = Gemini.complete([%{role: :user, content: "Hi"}], model: model)

      assert result.content == "Hello"
      assert result.model == model
      assert is_map(result.usage)
      assert result.finish_reason == :stop
    end
  end

  describe "stream/2" do
    test "streams chunks from the configured sdk" do
      {:ok, stream} =
        Gemini.stream([%{role: :user, content: "Hi"}],
          max_tokens: 10,
          sdk: TestGeminiStream
        )

      chunks = Enum.to_list(stream)
      assert Enum.map(chunks, & &1.delta) == ["Hello", " Gemini", ""]
      assert List.last(chunks).finish_reason == :stop
    end
  end

  # Live tests would require real API access
  # Run with: mix test --include live
  describe "complete/2 live" do
    if System.get_env("GEMINI_API_KEY") do
      @tag :live
      test "completes messages" do
        messages = [
          %{role: :user, content: "Say hello in one word"}
        ]

        {:ok, result} = Gemini.complete(messages, max_tokens: 10, sdk: GeminiSdk)

        assert is_binary(result.content)
        assert result.model == GeminiConfig.default_model()
        assert is_map(result.usage)
      end
    else
      @tag :live
      @tag skip: "GEMINI_API_KEY is not set"
      test "completes messages" do
        :ok
      end
    end
  end
end
