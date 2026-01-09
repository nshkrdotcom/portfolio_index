defmodule PortfolioIndex.Adapters.LLM.VLLMTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Adapters.LLM.VLLM

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}"}
  end

  describe "complete/2" do
    test "returns completion response", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "llama3"
        assert decoded["messages"] == [%{"role" => "user", "content" => "Hi"}]

        response = %{
          "id" => "chatcmpl_vllm_test",
          "object" => "chat.completion",
          "created" => 1_700_000_000,
          "model" => "llama3",
          "choices" => [
            %{
              "index" => 0,
              "message" => %{"role" => "assistant", "content" => "Hello from vLLM"},
              "finish_reason" => "stop"
            }
          ],
          "usage" => %{"prompt_tokens" => 2, "completion_tokens" => 3}
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, response} =
        VLLM.complete(
          [%{role: :user, content: "Hi"}],
          model: "llama3",
          base_url: url <> "/v1"
        )

      assert response.content == "Hello from vLLM"
      assert response.model == "llama3"
      assert response.usage.input_tokens == 2
      assert response.usage.output_tokens == 3
    end

    test "passes model override via opts", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "mistral"

        response = %{
          "id" => "chatcmpl_vllm_override",
          "object" => "chat.completion",
          "created" => 1_700_000_001,
          "model" => "mistral",
          "choices" => [
            %{
              "index" => 0,
              "message" => %{"role" => "assistant", "content" => "Hi"},
              "finish_reason" => "stop"
            }
          ],
          "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, response} =
        VLLM.complete(
          [%{role: :user, content: "Hi"}],
          model: "mistral",
          base_url: url <> "/v1"
        )

      assert response.model == "mistral"
    end
  end

  describe "stream/2" do
    test "streams completion response", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "llama3"

        conn =
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_chunked(200)

        {:ok, conn} =
          Plug.Conn.chunk(
            conn,
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n"
          )

        {:ok, conn} =
          Plug.Conn.chunk(
            conn,
            "data: {\"choices\":[{\"delta\":{\"content\":\" vLLM\"}}]}\n\n"
          )

        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      {:ok, stream} =
        VLLM.stream(
          [%{role: :user, content: "Hi"}],
          model: "llama3",
          base_url: url <> "/v1"
        )

      chunks = Enum.to_list(stream)
      assert Enum.map(chunks, & &1.delta) == ["Hello", " vLLM", ""]
      assert List.last(chunks).finish_reason == :stop
    end
  end

  describe "supported_models/0" do
    test "returns configured models when present" do
      original = Application.get_env(:portfolio_index, :vllm, [])

      Application.put_env(:portfolio_index, :vllm,
        model: "llama3",
        models: ["llama3", "mistral"]
      )

      on_exit(fn -> Application.put_env(:portfolio_index, :vllm, original) end)

      assert VLLM.supported_models() == ["llama3", "mistral"]
    end
  end

  describe "model_info/1" do
    test "returns configured model info when provided" do
      original = Application.get_env(:portfolio_index, :vllm, [])

      Application.put_env(:portfolio_index, :vllm,
        model_info: %{
          "llama3" => %{context_window: 32_768, max_output: 4096, supports_tools: true}
        }
      )

      on_exit(fn -> Application.put_env(:portfolio_index, :vllm, original) end)

      assert VLLM.model_info("llama3") == %{
               context_window: 32_768,
               max_output: 4096,
               supports_tools: true
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
