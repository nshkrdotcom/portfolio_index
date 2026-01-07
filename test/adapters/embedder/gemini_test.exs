defmodule PortfolioIndex.Adapters.Embedder.GeminiTest do
  use PortfolioIndex.SupertesterCase, async: true

  import Mox

  alias Elixir.Gemini.Config, as: GeminiConfig
  alias Gemini.Types.Response.{ContentEmbedding, EmbedContentResponse}
  alias PortfolioIndex.Adapters.Embedder.Gemini

  # These tests use Mox to mock the Gemini API calls
  setup :verify_on_exit!

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

  describe "embed/2" do
    test "generates embedding using the configured sdk" do
      model = GeminiConfig.default_embedding_model()
      raw_vector = [0.1, 0.2, 0.3]

      GeminiSdkMock
      |> expect(:embed_content, fn text, opts ->
        assert text == "Hello, world!"
        assert Keyword.get(opts, :model) == model

        {:ok,
         %EmbedContentResponse{
           embedding: %ContentEmbedding{values: raw_vector}
         }}
      end)

      {:ok, result} = Gemini.embed("Hello, world!", model: model)

      dims =
        Application.get_env(:portfolio_index, :embedding, [])
        |> Keyword.get(:default_dimensions)
        |> case do
          nil -> GeminiConfig.default_embedding_dimensions(model) || 768
          configured -> configured
        end

      expected_vector =
        if GeminiConfig.needs_normalization?(model, dims) do
          magnitude = :math.sqrt(Enum.reduce(raw_vector, 0, fn x, acc -> acc + x * x end))
          Enum.map(raw_vector, &(&1 / magnitude))
        else
          raw_vector
        end

      assert result.vector == expected_vector
      assert result.model == model
      assert result.dimensions == 3
      assert is_integer(result.token_count)
    end
  end

  # Integration tests would require real API access
  # Run with: mix test --include live
  describe "embed/2 live" do
    if System.get_env("GEMINI_API_KEY") do
      @tag :live
      test "generates embedding for text" do
        {:ok, result} = Gemini.embed("Hello, world!", [])

        assert is_list(result.vector)
        assert result.vector != []
        assert result.model == GeminiConfig.default_embedding_model()
        assert result.dimensions == length(result.vector)
        assert is_integer(result.token_count)
      end
    else
      @tag :live
      @tag skip: "GEMINI_API_KEY is not set"
      test "generates embedding for text" do
        :ok
      end
    end
  end
end
