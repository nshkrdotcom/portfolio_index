defmodule PortfolioIndex.Embedder.DimensionDetectorTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Adapters.Embedder
  alias PortfolioIndex.Embedder.DimensionDetector
  alias PortfolioIndex.Embedder.Registry

  describe "detect/2" do
    test "returns explicit dimensions from options" do
      {:ok, dims} = DimensionDetector.detect(Embedder.OpenAI, dimensions: 1024)

      assert dims == 1024
    end

    test "looks up dimensions in registry for known model" do
      {:ok, dims} = DimensionDetector.detect(Embedder.OpenAI, model: "text-embedding-3-small")

      assert dims == 1536
    end

    test "returns nil when model unknown and no explicit dimensions" do
      {:ok, dims} = DimensionDetector.detect(Embedder.OpenAI, model: "unknown-model")

      assert dims == nil
    end

    test "falls back to module's dimensions function" do
      {:ok, dims} = DimensionDetector.detect(Embedder.OpenAI, model: "text-embedding-3-large")

      assert dims == 3072
    end
  end

  describe "probe/2" do
    test "probes embedder by generating test embedding" do
      # Create a mock embedder function
      embed_fn = fn _text -> {:ok, List.duplicate(0.1, 512)} end
      embedder = Embedder.Function.new(embed_fn, dimensions: 512)

      {:ok, dims} = DimensionDetector.probe(embedder, [])

      assert dims == 512
    end

    test "returns error when probe fails" do
      embed_fn = fn _text -> {:error, :probe_failed} end
      embedder = Embedder.Function.new(embed_fn, dimensions: 768)

      {:error, _reason} = DimensionDetector.probe(embedder, [])
    end
  end

  describe "validate_dimensions/2" do
    test "returns ok when dimensions match" do
      embedding = List.duplicate(0.1, 768)

      assert :ok = DimensionDetector.validate_dimensions(embedding, 768)
    end

    test "returns error when dimensions don't match" do
      embedding = List.duplicate(0.1, 512)

      {:error, {:dimension_mismatch, expected, actual}} =
        DimensionDetector.validate_dimensions(embedding, 768)

      assert expected == 768
      assert actual == 512
    end
  end

  describe "detect_from_registry/1" do
    test "returns dimensions for known model" do
      {:ok, dims} = DimensionDetector.detect_from_registry("text-embedding-3-small")

      assert dims == 1536
    end

    test "returns nil for unknown model" do
      {:ok, dims} = DimensionDetector.detect_from_registry("unknown-model")

      assert dims == nil
    end

    test "works with custom registered models" do
      Registry.register("test-detector-model", :test, 999)

      {:ok, dims} = DimensionDetector.detect_from_registry("test-detector-model")
      assert dims == 999

      Registry.unregister("test-detector-model")
    end
  end
end
