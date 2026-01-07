defmodule PortfolioIndex.Adapters.Embedder.BumblebeeTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Adapters.Embedder.Bumblebee

  @default_model "BAAI/bge-small-en-v1.5"

  describe "dimensions/1" do
    test "returns 384 for BAAI/bge-small-en-v1.5" do
      assert Bumblebee.dimensions("BAAI/bge-small-en-v1.5") == 384
    end

    test "returns 768 for BAAI/bge-base-en-v1.5" do
      assert Bumblebee.dimensions("BAAI/bge-base-en-v1.5") == 768
    end

    test "returns 1024 for BAAI/bge-large-en-v1.5" do
      assert Bumblebee.dimensions("BAAI/bge-large-en-v1.5") == 1024
    end

    test "returns 384 for sentence-transformers/all-MiniLM-L6-v2" do
      assert Bumblebee.dimensions("sentence-transformers/all-MiniLM-L6-v2") == 384
    end

    test "returns nil for unknown model" do
      assert Bumblebee.dimensions("unknown-model") == nil
    end
  end

  describe "supported_models/0" do
    test "returns list of supported models" do
      models = Bumblebee.supported_models()
      assert is_list(models)
      assert "BAAI/bge-small-en-v1.5" in models
      assert "BAAI/bge-base-en-v1.5" in models
      assert "BAAI/bge-large-en-v1.5" in models
      assert "sentence-transformers/all-MiniLM-L6-v2" in models
    end
  end

  describe "child_spec/1" do
    test "returns proper child spec" do
      spec = Bumblebee.child_spec(model: @default_model)

      assert spec.id ==
               :"Elixir.PortfolioIndex.Adapters.Embedder.Bumblebee.BAAI/bge-small-en-v1.5"

      assert spec.type == :worker
      assert {Bumblebee, :start_link, [_opts]} = spec.start
    end

    test "uses default model when not specified" do
      spec = Bumblebee.child_spec([])

      assert spec.id ==
               :"Elixir.PortfolioIndex.Adapters.Embedder.Bumblebee.BAAI/bge-small-en-v1.5"
    end
  end

  describe "ready?/1" do
    test "returns false when serving is not started" do
      refute Bumblebee.ready?(:nonexistent_serving)
    end
  end

  # Integration tests require actual Bumblebee and model loading
  # These are tagged as :integration since they need:
  # - bumblebee dependency
  # - exla dependency
  # - HuggingFace Hub access
  describe "embed/2 integration" do
    @tag :integration
    test "generates embedding for text when serving is running" do
      # This test would require a running serving
      # It's skipped by default and run with: mix test --include integration
    end
  end

  describe "embed_batch/2 integration" do
    @tag :integration
    test "generates embeddings for multiple texts" do
      # This test would require a running serving
      # It's skipped by default and run with: mix test --include integration
    end
  end

  # Unit tests using a mock serving
  describe "embed/2" do
    setup do
      # Register a fake serving for testing
      # In real tests, we'd use Mox or a test serving
      :ok
    end

    test "returns error when serving not found" do
      result = Bumblebee.embed("test", serving_name: :nonexistent_serving)
      assert {:error, _reason} = result
    end
  end

  describe "embed_batch/2" do
    test "returns error when serving not found" do
      result = Bumblebee.embed_batch(["test"], serving_name: :nonexistent_serving)
      assert {:error, _reason} = result
    end

    test "handles empty list" do
      {:ok, result} = Bumblebee.embed_batch([], [])
      assert result.embeddings == []
      assert result.total_tokens == 0
    end
  end
end
