defmodule PortfolioIndex.Adapters.Embedder.OpenAITest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Embedder.OpenAI

  @default_model "text-embedding-3-small"

  describe "dimensions/1" do
    test "returns 1536 for text-embedding-3-small" do
      assert OpenAI.dimensions("text-embedding-3-small") == 1536
    end

    test "returns 3072 for text-embedding-3-large" do
      assert OpenAI.dimensions("text-embedding-3-large") == 3072
    end

    test "returns 1536 for text-embedding-ada-002" do
      assert OpenAI.dimensions("text-embedding-ada-002") == 1536
    end

    test "returns nil for unknown model" do
      assert OpenAI.dimensions("unknown-model") == nil
    end
  end

  describe "supported_models/0" do
    test "returns list of supported models" do
      models = OpenAI.supported_models()
      assert is_list(models)
      assert "text-embedding-3-small" in models
      assert "text-embedding-3-large" in models
      assert "text-embedding-ada-002" in models
    end
  end

  describe "model_dimensions/1" do
    test "returns dimension for known model" do
      assert OpenAI.model_dimensions("text-embedding-3-small") == 1536
      assert OpenAI.model_dimensions("text-embedding-3-large") == 3072
    end

    test "returns nil for unknown model" do
      assert OpenAI.model_dimensions("unknown-model") == nil
    end
  end

  describe "embed/2" do
    setup do
      # Start Bypass to mock the OpenAI API
      bypass = Bypass.open()
      {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}"}
    end

    test "generates embedding for text", %{bypass: bypass, url: url} do
      embedding = List.duplicate(0.1, 1536)

      Bypass.expect(bypass, "POST", "/v1/embeddings", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == @default_model
        assert decoded["input"] == "Hello, world!"

        response = %{
          "object" => "list",
          "data" => [
            %{
              "object" => "embedding",
              "index" => 0,
              "embedding" => embedding
            }
          ],
          "model" => @default_model,
          "usage" => %{
            "prompt_tokens" => 3,
            "total_tokens" => 3
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, result} = OpenAI.embed("Hello, world!", api_url: url <> "/v1/embeddings")

      assert is_list(result.vector)
      assert length(result.vector) == 1536
      assert result.model == @default_model
      assert result.dimensions == 1536
      assert result.token_count == 3
    end

    test "uses custom model from options", %{bypass: bypass, url: url} do
      embedding = List.duplicate(0.1, 3072)
      model = "text-embedding-3-large"

      Bypass.expect(bypass, "POST", "/v1/embeddings", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == model

        response = %{
          "object" => "list",
          "data" => [
            %{
              "object" => "embedding",
              "index" => 0,
              "embedding" => embedding
            }
          ],
          "model" => model,
          "usage" => %{
            "prompt_tokens" => 2,
            "total_tokens" => 2
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, result} = OpenAI.embed("Test", model: model, api_url: url <> "/v1/embeddings")

      assert result.model == model
      assert result.dimensions == 3072
    end

    test "returns error on API failure", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/embeddings", fn conn ->
        response = %{
          "error" => %{
            "message" => "Invalid API key",
            "type" => "authentication_error",
            "code" => "invalid_api_key"
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, Jason.encode!(response))
      end)

      {:error, reason} = OpenAI.embed("Test", api_url: url <> "/v1/embeddings")
      assert reason != nil
    end

    test "returns error when API key is missing" do
      # Temporarily clear the API key
      original = Application.get_env(:portfolio_index, OpenAI)
      Application.put_env(:portfolio_index, OpenAI, api_key: nil)

      on_exit(fn ->
        if original do
          Application.put_env(:portfolio_index, OpenAI, original)
        else
          Application.delete_env(:portfolio_index, OpenAI)
        end
      end)

      {:error, reason} = OpenAI.embed("Test", api_key: nil)
      assert reason == :missing_api_key
    end
  end

  describe "embed_batch/2" do
    setup do
      bypass = Bypass.open()
      {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}"}
    end

    test "generates embeddings for multiple texts", %{bypass: bypass, url: url} do
      embedding1 = List.duplicate(0.1, 1536)
      embedding2 = List.duplicate(0.2, 1536)

      Bypass.expect(bypass, "POST", "/v1/embeddings", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["input"] == ["Hello", "World"]

        response = %{
          "object" => "list",
          "data" => [
            %{"object" => "embedding", "index" => 0, "embedding" => embedding1},
            %{"object" => "embedding", "index" => 1, "embedding" => embedding2}
          ],
          "model" => @default_model,
          "usage" => %{
            "prompt_tokens" => 4,
            "total_tokens" => 4
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      {:ok, result} =
        OpenAI.embed_batch(["Hello", "World"], api_url: url <> "/v1/embeddings")

      assert is_list(result.embeddings)
      assert length(result.embeddings) == 2
      assert result.total_tokens == 4

      [first, second] = result.embeddings
      assert length(first.vector) == 1536
      assert length(second.vector) == 1536
    end

    test "handles empty list", %{bypass: _bypass, url: _url} do
      {:ok, result} = OpenAI.embed_batch([], [])
      assert result.embeddings == []
      assert result.total_tokens == 0
    end

    test "returns error on API failure", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "POST", "/v1/embeddings", fn conn ->
        response = %{
          "error" => %{
            "message" => "Rate limit exceeded",
            "type" => "rate_limit_error"
          }
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(429, Jason.encode!(response))
      end)

      {:error, _reason} =
        OpenAI.embed_batch(["Test"], api_url: url <> "/v1/embeddings")
    end
  end
end
