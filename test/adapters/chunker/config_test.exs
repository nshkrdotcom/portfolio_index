defmodule PortfolioIndex.Adapters.Chunker.ConfigTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Config

  describe "validate/1" do
    test "returns validated config with defaults" do
      assert {:ok, config} = Config.validate(%{})

      assert config.chunk_size == 1000
      assert config.chunk_overlap == 200
      assert is_function(config.get_chunk_size, 1)
      assert config.format == :plain
      assert config.separators == nil
    end

    test "accepts valid chunk_size" do
      assert {:ok, config} = Config.validate(%{chunk_size: 500})
      assert config.chunk_size == 500
    end

    test "accepts valid chunk_overlap" do
      assert {:ok, config} = Config.validate(%{chunk_overlap: 100})
      assert config.chunk_overlap == 100
    end

    test "accepts zero chunk_overlap" do
      assert {:ok, config} = Config.validate(%{chunk_overlap: 0})
      assert config.chunk_overlap == 0
    end

    test "accepts custom get_chunk_size function" do
      custom_fn = &byte_size/1
      assert {:ok, config} = Config.validate(%{get_chunk_size: custom_fn})
      assert config.get_chunk_size == custom_fn
    end

    test "accepts valid format atom" do
      for format <- [:plain, :markdown, :elixir, :ruby, :php, :python, :javascript, :html] do
        assert {:ok, config} = Config.validate(%{format: format})
        assert config.format == format
      end
    end

    test "accepts custom separators list" do
      separators = ["\n## ", "\n\n", "\n", " "]
      assert {:ok, config} = Config.validate(%{separators: separators})
      assert config.separators == separators
    end

    test "rejects invalid chunk_size (zero)" do
      assert {:error, error} = Config.validate(%{chunk_size: 0})
      assert error =~ "chunk_size"
    end

    test "rejects invalid chunk_size (negative)" do
      assert {:error, error} = Config.validate(%{chunk_size: -1})
      assert error =~ "chunk_size"
    end

    test "rejects invalid chunk_size (non-integer)" do
      assert {:error, error} = Config.validate(%{chunk_size: "1000"})
      assert error =~ "chunk_size"
    end

    test "rejects invalid chunk_overlap (negative)" do
      assert {:error, error} = Config.validate(%{chunk_overlap: -1})
      assert error =~ "chunk_overlap"
    end

    test "rejects invalid get_chunk_size (not a function)" do
      assert {:error, error} = Config.validate(%{get_chunk_size: "not a function"})
      assert error =~ "get_chunk_size"
    end

    test "rejects invalid get_chunk_size (wrong arity)" do
      assert {:error, error} = Config.validate(%{get_chunk_size: fn -> 0 end})
      assert error =~ "get_chunk_size"
    end

    test "rejects invalid separators (not a list)" do
      assert {:error, error} = Config.validate(%{separators: "not a list"})
      assert error =~ "separators"
    end

    test "rejects invalid separators (list of non-strings)" do
      assert {:error, error} = Config.validate(%{separators: [1, 2, 3]})
      assert error =~ "separators"
    end
  end

  describe "validate!/1" do
    test "returns validated config for valid input" do
      config = Config.validate!(%{chunk_size: 500})
      assert config.chunk_size == 500
    end

    test "raises for invalid input" do
      assert_raise ArgumentError, fn ->
        Config.validate!(%{chunk_size: 0})
      end
    end
  end

  describe "validate_from_keyword/1" do
    test "accepts keyword list input" do
      assert {:ok, config} = Config.validate_from_keyword(chunk_size: 500, chunk_overlap: 100)
      assert config.chunk_size == 500
      assert config.chunk_overlap == 100
    end

    test "returns defaults for empty keyword list" do
      assert {:ok, config} = Config.validate_from_keyword([])
      assert config.chunk_size == 1000
    end
  end

  describe "get_chunk_size default function" do
    test "default function uses String.length" do
      {:ok, config} = Config.validate(%{})

      assert config.get_chunk_size.("hello") == 5
      assert config.get_chunk_size.("") == 0
      assert config.get_chunk_size.("日本語") == 3
    end
  end

  describe "config struct access" do
    test "config can be accessed with dot notation" do
      {:ok, config} = Config.validate(%{chunk_size: 800})

      assert config.chunk_size == 800
      assert config.chunk_overlap == 200
    end

    test "config can be pattern matched" do
      {:ok, %Config{chunk_size: size}} = Config.validate(%{chunk_size: 800})

      assert size == 800
    end
  end

  describe "merge_with_defaults/1" do
    test "merges user config with defaults" do
      config = Config.merge_with_defaults(%{chunk_size: 500})

      assert config.chunk_size == 500
      assert config.chunk_overlap == 200
      assert is_function(config.get_chunk_size, 1)
    end

    test "handles keyword list input" do
      config = Config.merge_with_defaults(chunk_size: 500)

      assert config.chunk_size == 500
    end

    test "returns defaults for empty map" do
      config = Config.merge_with_defaults(%{})

      assert config.chunk_size == 1000
      assert config.chunk_overlap == 200
    end
  end

  describe "backwards compatibility" do
    test "accepts map with atom keys" do
      {:ok, config} = Config.validate(%{chunk_size: 500, chunk_overlap: 100})
      assert config.chunk_size == 500
      assert config.chunk_overlap == 100
    end

    test "accepts struct-like access patterns from existing code" do
      # Existing code might do config[:chunk_size] or config.chunk_size
      {:ok, config} = Config.validate(%{chunk_size: 500})

      # Dot notation
      assert config.chunk_size == 500

      # Map access (for backwards compatibility)
      assert Map.get(config, :chunk_size) == 500
    end
  end

  describe "size_unit option" do
    test "defaults to :characters" do
      {:ok, config} = Config.validate(%{})
      assert config.size_unit == :characters
    end

    test ":characters uses String.length/1 by default" do
      {:ok, config} = Config.validate(%{size_unit: :characters})
      assert config.get_chunk_size.("test") == 4
    end

    test ":tokens auto-sets Tokens.sizer()" do
      {:ok, config} = Config.validate(%{size_unit: :tokens})
      # 8 chars / 4 = 2 tokens
      assert config.get_chunk_size.("12345678") == 2
    end

    test "explicit get_chunk_size overrides size_unit default" do
      custom_fn = fn _ -> 42 end
      {:ok, config} = Config.validate(%{size_unit: :tokens, get_chunk_size: custom_fn})
      assert config.get_chunk_size.("anything") == 42
    end

    test "rejects invalid size_unit" do
      {:error, message} = Config.validate(%{size_unit: :words})
      assert message =~ "invalid value"
    end

    test "size_unit :tokens affects chunker sizing behavior" do
      # When size_unit is :tokens, the get_chunk_size should return token estimates
      {:ok, config} = Config.validate(%{size_unit: :tokens, chunk_size: 100})

      # 400 chars should be ~100 tokens
      text = String.duplicate("a", 400)
      assert config.get_chunk_size.(text) == 100
    end

    test "default_size_unit/0 returns :characters" do
      assert Config.default_size_unit() == :characters
    end
  end
end
