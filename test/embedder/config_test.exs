defmodule PortfolioIndex.Embedder.ConfigTest do
  use ExUnit.Case, async: false

  alias PortfolioIndex.Adapters.Embedder
  alias PortfolioIndex.Embedder.Config

  setup do
    # Save and restore app config
    original = Application.get_env(:portfolio_index, :embedder)

    on_exit(fn ->
      if original do
        Application.put_env(:portfolio_index, :embedder, original)
      else
        Application.delete_env(:portfolio_index, :embedder)
      end
    end)

    :ok
  end

  describe "resolve/1" do
    test "resolves :openai atom to OpenAI module" do
      {:ok, {module, opts}} = Config.resolve(:openai)

      assert module == Embedder.OpenAI
      assert opts == []
    end

    test "resolves :bumblebee atom to Bumblebee module" do
      {:ok, {module, opts}} = Config.resolve(:bumblebee)

      assert module == Embedder.Bumblebee
      assert opts == []
    end

    test "resolves {:openai, opts} tuple" do
      {:ok, {module, opts}} = Config.resolve({:openai, model: "text-embedding-3-large"})

      assert module == Embedder.OpenAI
      assert opts[:model] == "text-embedding-3-large"
    end

    test "resolves module directly" do
      {:ok, {module, opts}} = Config.resolve(Embedder.OpenAI)

      assert module == Embedder.OpenAI
      assert opts == []
    end

    test "resolves {module, opts} tuple" do
      {:ok, {module, opts}} = Config.resolve({Embedder.OpenAI, api_key: "test"})

      assert module == Embedder.OpenAI
      assert opts[:api_key] == "test"
    end

    test "resolves function to Function adapter" do
      embed_fn = fn _text -> {:ok, List.duplicate(0.1, 768)} end

      {:ok, {module, opts}} = Config.resolve({embed_fn, dimensions: 768})

      assert module == Embedder.Function
      assert is_function(opts[:embed_fn], 1)
      assert opts[:dimensions] == 768
    end

    test "returns error for unknown provider" do
      {:error, reason} = Config.resolve(:unknown_provider)

      assert reason == {:unknown_provider, :unknown_provider}
    end
  end

  describe "current/0" do
    test "returns configured embedder" do
      Application.put_env(:portfolio_index, :embedder, :openai)

      {module, opts} = Config.current()

      assert module == Embedder.OpenAI
      assert opts == []
    end

    test "returns configured embedder with options" do
      Application.put_env(:portfolio_index, :embedder, {:openai, model: "text-embedding-3-large"})

      {module, opts} = Config.current()

      assert module == Embedder.OpenAI
      assert opts[:model] == "text-embedding-3-large"
    end

    test "returns default when not configured" do
      Application.delete_env(:portfolio_index, :embedder)

      {module, _opts} = Config.current()

      # Default should be OpenAI
      assert module == Embedder.OpenAI
    end
  end

  describe "current_dimensions/0" do
    test "returns dimensions for configured model" do
      Application.put_env(:portfolio_index, :embedder, {:openai, model: "text-embedding-3-large"})

      dims = Config.current_dimensions()

      assert dims == 3072
    end

    test "returns default dimensions when model not specified" do
      Application.put_env(:portfolio_index, :embedder, :openai)

      dims = Config.current_dimensions()

      # Default OpenAI model is text-embedding-3-small with 1536 dims
      assert dims == 1536
    end
  end

  describe "validate/1" do
    test "validates known provider" do
      assert :ok = Config.validate(:openai)
      assert :ok = Config.validate(:bumblebee)
    end

    test "validates provider with options" do
      assert :ok = Config.validate({:openai, model: "text-embedding-3-large"})
    end

    test "validates module" do
      assert :ok = Config.validate(Embedder.OpenAI)
    end

    test "validates module with options" do
      assert :ok = Config.validate({Embedder.OpenAI, api_key: "test"})
    end

    test "returns error for invalid config" do
      {:error, _} = Config.validate(:invalid_provider)
    end
  end
end
