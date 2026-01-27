defmodule PortfolioIndex.Adapters.LLM.VLLMTest do
  use PortfolioIndex.SupertesterCase, async: true

  import Mox

  alias PortfolioIndex.Adapters.LLM.VLLM

  setup :verify_on_exit!

  describe "complete/2" do
    test "returns completion response" do
      VLLMSdkMock
      |> expect(:run, fn fun, opts ->
        assert opts == []
        fun.()
      end)
      |> expect(:llm!, fn model, opts ->
        assert model == "Qwen/Qwen2-0.5B-Instruct"
        assert Keyword.get(opts, :max_model_len) == 2048
        assert Keyword.get(opts, :gpu_memory_utilization) == 0.8
        :llm
      end)
      |> expect(:sampling_params!, fn params ->
        assert params[:max_tokens] == 12
        :params
      end)
      |> expect(:chat!, fn :llm, messages, opts ->
        assert messages == [[%{"role" => "user", "content" => "Hi"}]]
        assert opts[:sampling_params] == :params

        [
          %{
            "outputs" => [
              %{
                "text" => "Hello from vLLM",
                "token_ids" => [10, 20, 30],
                "finish_reason" => "stop"
              }
            ],
            "prompt_token_ids" => [1, 2],
            "model" => "Qwen/Qwen2-0.5B-Instruct"
          }
        ]
      end)

      {:ok, response} = VLLM.complete([%{role: :user, content: "Hi"}], max_tokens: 12)

      assert response.content == "Hello from vLLM"
      assert response.model == "Qwen/Qwen2-0.5B-Instruct"
      assert response.usage.input_tokens == 2
      assert response.usage.output_tokens == 3
      assert response.finish_reason == :stop
    end
  end

  describe "stream/2" do
    test "streams completion response" do
      VLLMSdkMock
      |> expect(:run, fn fun, _opts -> fun.() end)
      |> expect(:llm!, fn _model, _opts -> :llm end)
      |> expect(:sampling_params!, fn _params -> :params end)
      |> expect(:chat!, fn :llm, _messages, _opts ->
        [
          %{
            "outputs" => [%{"text" => "Hello vLLM", "token_ids" => [1, 2]}],
            "prompt_token_ids" => [1]
          }
        ]
      end)

      {:ok, stream} = VLLM.stream([%{role: :user, content: "Hi"}], max_tokens: 12)
      chunks = Enum.to_list(stream)
      assert Enum.map(chunks, & &1.delta) == ["Hello vLLM", ""]
      assert List.last(chunks).finish_reason == :stop
    end
  end

  describe "supported_models/0" do
    test "returns configured models when present" do
      original = Application.get_env(:portfolio_index, :vllm, [])

      Application.put_env(:portfolio_index, :vllm,
        model: "Qwen/Qwen2-0.5B-Instruct",
        models: ["Qwen/Qwen2-0.5B-Instruct", "TinyLlama/TinyLlama-1.1B-Chat-v1.0"]
      )

      on_exit(fn -> Application.put_env(:portfolio_index, :vllm, original) end)

      assert VLLM.supported_models() == [
               "Qwen/Qwen2-0.5B-Instruct",
               "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
             ]
    end
  end

  describe "model_info/1" do
    test "returns configured model info when provided" do
      original = Application.get_env(:portfolio_index, :vllm, [])

      Application.put_env(:portfolio_index, :vllm,
        model_info: %{
          "Qwen/Qwen2-0.5B-Instruct" => %{
            context_window: 2048,
            max_output: 2048,
            supports_tools: false
          }
        }
      )

      on_exit(fn -> Application.put_env(:portfolio_index, :vllm, original) end)

      assert VLLM.model_info("Qwen/Qwen2-0.5B-Instruct") == %{
               context_window: 2048,
               max_output: 2048,
               supports_tools: false
             }
    end

    test "falls back to defaults for unknown models" do
      info = VLLM.model_info("unknown-model")
      assert info.context_window > 0
      assert info.max_output > 0
      assert is_boolean(info.supports_tools)
    end
  end
end
