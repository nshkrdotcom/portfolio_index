defmodule PortfolioIndex.Adapters.Chunker.TokensTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Tokens

  describe "estimate/2" do
    test "returns 0 for empty string" do
      assert Tokens.estimate("") == 0
    end

    test "returns at least 1 for non-empty text" do
      assert Tokens.estimate("Hi") == 1
      assert Tokens.estimate("a") == 1
    end

    test "estimates ~4 chars per token by default" do
      assert Tokens.estimate("12345678") == 2
      assert Tokens.estimate("123456789012") == 3
    end

    test "accepts custom chars_per_token ratio" do
      assert Tokens.estimate("12345678", chars_per_token: 2) == 4
      assert Tokens.estimate("12345678", chars_per_token: 8) == 1
    end

    test "handles unicode correctly" do
      # String.length counts graphemes, not bytes
      assert Tokens.estimate("hello") == 1
      assert Tokens.estimate("こんにちは") == 1
    end
  end

  describe "sizer/1" do
    test "returns a function" do
      sizer = Tokens.sizer()
      assert is_function(sizer, 1)
    end

    test "returned function estimates tokens" do
      sizer = Tokens.sizer()
      assert sizer.("12345678") == 2
    end

    test "accepts custom ratio" do
      sizer = Tokens.sizer(chars_per_token: 2)
      assert sizer.("12345678") == 4
    end
  end

  describe "to_chars/2" do
    test "converts tokens to characters" do
      assert Tokens.to_chars(100) == 400
      assert Tokens.to_chars(100, chars_per_token: 3) == 300
    end

    test "returns 0 for 0 tokens" do
      assert Tokens.to_chars(0) == 0
    end
  end

  describe "from_chars/2" do
    test "converts characters to tokens" do
      assert Tokens.from_chars(400) == 100
      assert Tokens.from_chars(300, chars_per_token: 3) == 100
    end

    test "returns at least 1 for small char counts" do
      assert Tokens.from_chars(1) == 1
      assert Tokens.from_chars(3) == 1
    end

    test "returns 0 for 0 chars" do
      assert Tokens.from_chars(0) == 0
    end
  end

  describe "default_ratio/0" do
    test "returns 4" do
      assert Tokens.default_ratio() == 4
    end
  end
end
