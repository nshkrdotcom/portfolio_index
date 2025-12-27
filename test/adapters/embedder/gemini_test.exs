defmodule PortfolioIndex.Adapters.Embedder.GeminiTest do
  use ExUnit.Case, async: true

  alias Elixir.Gemini.Config, as: GeminiConfig
  alias PortfolioIndex.Adapters.Embedder.Gemini

  # These tests use Mox to mock the Gemini API calls

  describe "dimensions/1" do
    test "returns default dimensions for registry model" do
      model = GeminiConfig.default_embedding_model()
      expected = GeminiConfig.default_embedding_dimensions(model)
      assert Gemini.dimensions(model) == expected
    end

    test "returns app default dimensions for unknown model" do
      default_dims =
        Application.get_env(:portfolio_index, :embedding, [])
        |> Keyword.get(:default_dimensions)

      assert Gemini.dimensions("unknown-model") == default_dims
    end
  end

  describe "supported_models/0" do
    test "returns list of supported models" do
      models = Gemini.supported_models()
      assert is_list(models)
      assert GeminiConfig.default_embedding_model() in models
    end
  end

  # Integration tests would require real API access
  # Run with: mix test --include integration
  describe "embed/2 integration" do
    @tag :skip
    test "generates embedding for text" do
      {:ok, result} = Gemini.embed("Hello, world!", [])

      assert is_list(result.vector)
      assert result.vector != []
      assert result.model == GeminiConfig.default_embedding_model()
      assert result.dimensions == length(result.vector)
      assert is_integer(result.token_count)
    end
  end
end
