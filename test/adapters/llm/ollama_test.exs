defmodule PortfolioIndex.Adapters.LLM.OllamaTest do
  use PortfolioIndex.SupertesterCase, async: true

  import Mox

  alias PortfolioIndex.Adapters.LLM.Ollama

  setup :verify_on_exit!

  describe "complete/2" do
    test "normalizes chat responses from the SDK" do
      OllamaSdkMock
      |> expect(:init, fn opts ->
        assert Keyword.get(opts, :base_url) == "http://ollama.local/api"
        :client
      end)
      |> expect(:chat, fn :client, params ->
        assert params[:model] == "llama3"
        assert params[:messages] == [%{role: "user", content: "Hi"}]

        assert params[:options] == %{
                 temperature: 0.2,
                 num_predict: 12
               }

        {:ok,
         %{
           "message" => %{"content" => "Hello from Ollama"},
           "model" => "llama3",
           "prompt_eval_count" => 4,
           "eval_count" => 6,
           "done_reason" => "stop"
         }}
      end)

      {:ok, result} =
        Ollama.complete(
          [%{role: :user, content: "Hi"}],
          model: "llama3",
          base_url: "http://ollama.local/api",
          temperature: 0.2,
          max_tokens: 12
        )

      assert result.content == "Hello from Ollama"
      assert result.model == "llama3"
      assert result.usage.input_tokens == 4
      assert result.usage.output_tokens == 6
      assert result.finish_reason == :stop
    end
  end

  describe "stream/2" do
    test "streams deltas from chat responses" do
      OllamaSdkMock
      |> expect(:init, fn _opts -> :client end)
      |> expect(:chat, fn :client, params ->
        assert params[:model] == "llama3"
        assert params[:stream] == true

        {:ok,
         [
           %{"message" => %{"content" => "Hello"}},
           %{"message" => %{"content" => " Ollama"}}
         ]}
      end)

      {:ok, stream} = Ollama.stream([%{role: :user, content: "Stream"}], model: "llama3")
      chunks = Enum.to_list(stream)

      assert Enum.map(chunks, & &1.delta) == ["Hello", " Ollama", ""]
      assert List.last(chunks).finish_reason == :stop
    end
  end

  describe "supported_models/0" do
    test "returns configured models when present" do
      original = Application.get_env(:portfolio_index, :ollama, [])

      Application.put_env(:portfolio_index, :ollama,
        model: "llama3",
        models: ["llama3", "phi4"]
      )

      on_exit(fn -> Application.put_env(:portfolio_index, :ollama, original) end)

      assert Ollama.supported_models() == ["llama3", "phi4"]
    end
  end

  describe "model_info/1" do
    test "returns configured model info when provided" do
      original = Application.get_env(:portfolio_index, :ollama, [])

      Application.put_env(:portfolio_index, :ollama,
        model_info: %{
          "llama3" => %{context_window: 8192, max_output: 2048, supports_tools: true}
        }
      )

      on_exit(fn -> Application.put_env(:portfolio_index, :ollama, original) end)

      assert Ollama.model_info("llama3") == %{
               context_window: 8192,
               max_output: 2048,
               supports_tools: true
             }
    end

    test "falls back to defaults for unknown models" do
      info = Ollama.model_info("unknown-model")
      assert info.context_window > 0
      assert info.max_output > 0
      assert is_boolean(info.supports_tools)
    end
  end
end
