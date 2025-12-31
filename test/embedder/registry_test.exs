defmodule PortfolioIndex.Embedder.RegistryTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Embedder.Registry

  describe "get/1" do
    test "returns model info for known OpenAI model" do
      info = Registry.get("text-embedding-3-small")

      assert info.provider == :openai
      assert info.dimensions == 1536
    end

    test "returns model info for known Voyage model" do
      info = Registry.get("voyage-3")

      assert info.provider == :voyage
      assert info.dimensions == 1024
    end

    test "returns model info for known Bumblebee model" do
      info = Registry.get("BAAI/bge-small-en-v1.5")

      assert info.provider == :bumblebee
      assert info.dimensions == 384
    end

    test "returns model info for known Ollama model" do
      info = Registry.get("nomic-embed-text")

      assert info.provider == :ollama
      assert info.dimensions == 768
    end

    test "returns nil for unknown model" do
      assert Registry.get("unknown-model") == nil
    end
  end

  describe "dimensions/1" do
    test "returns dimensions for known model" do
      assert Registry.dimensions("text-embedding-3-small") == 1536
      assert Registry.dimensions("text-embedding-3-large") == 3072
      assert Registry.dimensions("BAAI/bge-small-en-v1.5") == 384
    end

    test "returns nil for unknown model" do
      assert Registry.dimensions("unknown-model") == nil
    end
  end

  describe "provider/1" do
    test "returns provider for known model" do
      assert Registry.provider("text-embedding-3-small") == :openai
      assert Registry.provider("voyage-3") == :voyage
      assert Registry.provider("BAAI/bge-small-en-v1.5") == :bumblebee
      assert Registry.provider("nomic-embed-text") == :ollama
    end

    test "returns nil for unknown model" do
      assert Registry.provider("unknown-model") == nil
    end
  end

  describe "list/0" do
    test "returns list of all known models" do
      models = Registry.list()

      assert is_list(models)
      assert "text-embedding-3-small" in models
      assert "voyage-3" in models
      assert "BAAI/bge-small-en-v1.5" in models
    end
  end

  describe "list_by_provider/1" do
    test "returns OpenAI models" do
      models = Registry.list_by_provider(:openai)

      assert "text-embedding-3-small" in models
      assert "text-embedding-3-large" in models
      assert "text-embedding-ada-002" in models
    end

    test "returns Voyage models" do
      models = Registry.list_by_provider(:voyage)

      assert "voyage-3" in models
      assert "voyage-3-lite" in models
      assert "voyage-code-3" in models
    end

    test "returns Bumblebee models" do
      models = Registry.list_by_provider(:bumblebee)

      assert "BAAI/bge-small-en-v1.5" in models
      assert "BAAI/bge-base-en-v1.5" in models
      assert "sentence-transformers/all-MiniLM-L6-v2" in models
    end

    test "returns Ollama models" do
      models = Registry.list_by_provider(:ollama)

      assert "nomic-embed-text" in models
      assert "mxbai-embed-large" in models
    end

    test "returns empty list for unknown provider" do
      assert Registry.list_by_provider(:unknown) == []
    end
  end

  describe "register/3" do
    test "registers a custom model" do
      :ok = Registry.register("my-custom-model", :custom, 512)

      info = Registry.get("my-custom-model")
      assert info.provider == :custom
      assert info.dimensions == 512

      # Clean up
      Registry.unregister("my-custom-model")
    end

    test "registered model appears in list" do
      :ok = Registry.register("test-model", :test, 256)

      assert "test-model" in Registry.list()
      assert "test-model" in Registry.list_by_provider(:test)

      # Clean up
      Registry.unregister("test-model")
    end
  end

  describe "unregister/1" do
    test "removes a registered model" do
      :ok = Registry.register("temp-model", :temp, 128)
      assert Registry.get("temp-model") != nil

      :ok = Registry.unregister("temp-model")
      assert Registry.get("temp-model") == nil
    end

    test "returns ok for non-existent model" do
      assert :ok = Registry.unregister("nonexistent-model")
    end
  end
end
