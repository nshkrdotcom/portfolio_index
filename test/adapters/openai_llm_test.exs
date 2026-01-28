defmodule PortfolioIndex.Adapters.LLM.OpenAITest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Adapters.LLM.OpenAI

  defmodule TelemetryHandler do
    def handle_event(event, measurements, metadata, %{parent: parent}) do
      send(parent, {:telemetry, event, measurements, metadata})
    end
  end

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}"}
  end

  describe "complete/2" do
    test "returns completion response", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "gpt-4o-mini"
        assert decoded["messages"] == [%{"role" => "user", "content" => "Hi"}]

        response = %{
          "id" => "chatcmpl_test",
          "object" => "chat.completion",
          "created" => 1_700_000_000,
          "model" => "gpt-4o-mini",
          "choices" => [
            %{
              "index" => 0,
              "message" => %{"role" => "assistant", "content" => "Hello!"},
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
        OpenAI.complete(
          [%{role: :user, content: "Hi"}],
          api_key: "test-key",
          base_url: url <> "/v1"
        )

      assert response.content == "Hello!"
      assert response.model == "gpt-4o-mini"
    end

    test "passes model override via opts", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "gpt-3.5-turbo"

        response = %{
          "id" => "chatcmpl_test_override",
          "object" => "chat.completion",
          "created" => 1_700_000_001,
          "model" => "gpt-3.5-turbo",
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
        OpenAI.complete(
          [%{role: :user, content: "Hi"}],
          model: "gpt-3.5-turbo",
          api_key: "test-key",
          base_url: url <> "/v1"
        )

      assert response.model == "gpt-3.5-turbo"
    end

    test "honors api override to chat completions for gpt-5 models", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "gpt-5-nano"
        assert decoded["max_completion_tokens"] == 10
        assert decoded["max_output_tokens"] == nil

        response = %{
          "id" => "chatcmpl_test_chat_override",
          "object" => "chat.completion",
          "created" => 1_700_000_004,
          "model" => "gpt-5-nano",
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
        OpenAI.complete(
          [%{role: :user, content: "Hi"}],
          model: "gpt-5-nano",
          max_tokens: 10,
          api: :chat_completions,
          api_key: "test-key",
          base_url: url <> "/v1"
        )

      assert response.model == "gpt-5-nano"
      assert response.response_id == nil
    end

    test "maps max_tokens to max_output_tokens for gpt-5 models via Responses API", %{
      bypass: bypass,
      url: url
    } do
      Bypass.expect(bypass, "POST", "/v1/responses", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "gpt-5-nano"
        assert decoded["max_output_tokens"] == 10
        assert decoded["input"] == [%{"role" => "user", "content" => "Hi"}]

        response = %{
          "id" => "resp_test_completion_tokens",
          "object" => "response",
          "created" => 1_700_000_003,
          "model" => "gpt-5-nano",
          "status" => "completed",
          "output" => [
            %{
              "type" => "message",
              "role" => "assistant",
              "content" => [%{"type" => "output_text", "text" => "Hi"}]
            }
          ],
          "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, response} =
        OpenAI.complete(
          [%{role: :user, content: "Hi"}],
          model: "gpt-5-nano",
          max_tokens: 10,
          api_key: "test-key",
          base_url: url <> "/v1"
        )

      assert response.model == "gpt-5-nano"
      assert response.content == "Hi"
      assert response.response_id == "resp_test_completion_tokens"
    end

    test "includes lineage context in telemetry metadata", %{bypass: bypass, url: url} do
      ref = make_ref()

      :telemetry.attach_many(
        "openai-telemetry-#{inspect(ref)}",
        [[:portfolio_index, :llm, :openai, :complete]],
        &TelemetryHandler.handle_event/4,
        %{parent: self()}
      )

      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "gpt-4o-mini"

        response = %{
          "id" => "chatcmpl_test_context",
          "object" => "chat.completion",
          "created" => 1_700_000_002,
          "model" => "gpt-4o-mini",
          "choices" => [
            %{
              "index" => 0,
              "message" => %{"role" => "assistant", "content" => "Hello!"},
              "finish_reason" => "stop"
            }
          ],
          "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1}
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, _response} =
        OpenAI.complete(
          [%{role: :user, content: "Hi"}],
          api_key: "test-key",
          base_url: url <> "/v1",
          trace_id: "trace-123",
          work_id: "work-456",
          plan_id: "plan-789",
          step_id: "step-101"
        )

      assert_receive {:telemetry, [:portfolio_index, :llm, :openai, :complete], _, meta}
      assert meta.trace_id == "trace-123"
      assert meta.work_id == "work-456"
      assert meta.plan_id == "plan-789"
      assert meta.step_id == "step-101"

      :telemetry.detach("openai-telemetry-#{inspect(ref)}")
    end
  end

  describe "supported_models/0" do
    test "returns list of models" do
      models = OpenAI.supported_models()
      assert is_list(models)
      assert models != []
    end
  end

  describe "stream/2" do
    test "streams completion response", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "gpt-4o-mini"

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
            "data: {\"choices\":[{\"delta\":{\"content\":\"!\"}}]}\n\n"
          )

        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      {:ok, stream} =
        OpenAI.stream(
          [%{role: :user, content: "Hi"}],
          api_key: "test-key",
          base_url: url <> "/v1"
        )

      chunks = Enum.to_list(stream)
      assert Enum.map(chunks, & &1.delta) == ["Hello", "!", ""]
      assert List.last(chunks).finish_reason == :stop
    end

    test "streams responses API output for gpt-5 models", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/responses", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "gpt-5-nano"
        refute Map.has_key?(decoded, "stream_options")

        conn =
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_chunked(200)

        {:ok, conn} =
          Plug.Conn.chunk(
            conn,
            "event: response.output_text.delta\ndata: {\"delta\":\"Hello\"}\n\n"
          )

        {:ok, conn} =
          Plug.Conn.chunk(conn, "event: response.completed\ndata: {}\n\n")

        conn
      end)

      {:ok, stream} =
        OpenAI.stream(
          [%{role: :user, content: "Hi"}],
          model: "gpt-5-nano",
          api: :responses,
          max_tokens: 10,
          api_key: "test-key",
          base_url: url <> "/v1"
        )

      chunks = Enum.to_list(stream)
      assert Enum.map(chunks, & &1.delta) == ["Hello", ""]
      assert List.last(chunks).finish_reason == :stop
    end
  end

  describe "complete/2 live" do
    if System.get_env("OPENAI_API_KEY") do
      @tag :live
      test "completes messages via OpenAI API" do
        original = Application.get_env(:portfolio_index, :openai, [])

        Application.put_env(
          :portfolio_index,
          :openai,
          Keyword.put(original, :allow_live_api, true)
        )

        on_exit(fn ->
          Application.put_env(:portfolio_index, :openai, original)
        end)

        {:ok, result} =
          OpenAI.complete(
            [%{role: :user, content: "Say hello in one word"}],
            max_tokens: 10,
            model: "gpt-5-nano"
          )

        assert is_binary(result.content)
        assert result.model != nil
      end
    else
      @tag :live
      @tag skip: "OPENAI_API_KEY is not set"
      test "completes messages via OpenAI API" do
        :ok
      end
    end
  end
end
