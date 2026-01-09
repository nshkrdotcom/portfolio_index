defmodule PortfolioIndex.Adapters.Embedder.OllamaTest do
  use PortfolioIndex.SupertesterCase, async: true

  import ExUnit.CaptureLog

  alias PortfolioIndex.Adapters.Embedder.Ollama

  @default_model "nomic-embed-text"

  describe "dimensions/1" do
    test "returns known dimensions for Ollama models" do
      assert Ollama.dimensions("nomic-embed-text") == 768
      assert Ollama.dimensions("mxbai-embed-large") == 1024
      assert Ollama.dimensions("unknown-model") == nil
    end
  end

  describe "supported_models/0" do
    test "returns known Ollama embedding models" do
      models = Ollama.supported_models()
      assert @default_model in models
      assert "mxbai-embed-large" in models
    end
  end

  describe "embed/2" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}"}
    end

    test "generates embedding for text", %{bypass: bypass, url: url} do
      embedding = [0.1, 0.2, 0.3]

      Bypass.expect(bypass, "POST", "/api/embed", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == @default_model
        assert decoded["input"] == "Hello, world!"

        response = %{
          "model" => @default_model,
          "embeddings" => [embedding],
          "prompt_eval_count" => 5
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, result} = Ollama.embed("Hello, world!", base_url: url)

      assert result.vector == embedding
      assert result.model == @default_model
      assert result.dimensions == 3
      assert result.token_count == 5
    end

    test "returns error on API failure", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/api/embed", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "boom"}))
      end)

      capture_log(fn ->
        assert {:error, _} = Ollama.embed("Test", base_url: url)
      end)
    end
  end

  describe "embed_batch/2" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}"}
    end

    test "generates embeddings for multiple texts", %{bypass: bypass, url: url} do
      embeddings = [
        [0.1, 0.2],
        [0.3, 0.4]
      ]

      Bypass.expect(bypass, "POST", "/api/embed", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["input"] == ["Hello", "World"]

        response = %{
          "model" => @default_model,
          "embeddings" => embeddings,
          "prompt_eval_count" => 6
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, result} = Ollama.embed_batch(["Hello", "World"], base_url: url)

      assert length(result.embeddings) == 2
      assert result.total_tokens == 6
      assert Enum.all?(result.embeddings, &(&1.model == @default_model))
      assert Enum.map(result.embeddings, & &1.vector) == embeddings
    end
  end
end
