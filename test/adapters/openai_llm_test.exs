defmodule PortfolioIndex.Adapters.LLM.OpenAITest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Adapters.LLM.OpenAI

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
          OpenAI.complete([%{role: :user, content: "Say hello in one word"}], max_tokens: 10)

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
