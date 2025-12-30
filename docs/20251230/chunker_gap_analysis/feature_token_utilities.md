# Feature: Token Utilities Module

## Overview

Add a centralized token estimation module to provide:
1. Simple token count estimation
2. Pre-built sizing function for token-based chunking
3. Configurable chars-per-token ratio

## Source Reference

**Arcana implementation** (`arcana/lib/arcana/chunker.ex:75-79`):
```elixir
defp estimate_tokens(text) do
  # Rough estimate: ~4 chars per token for English
  # This matches typical BPE tokenizer behavior
  max(1, div(String.length(text), 4))
end
```

## Proposed Implementation

### New File: `lib/portfolio_index/adapters/chunker/tokens.ex`

```elixir
defmodule PortfolioIndex.Adapters.Chunker.Tokens do
  @moduledoc """
  Token estimation utilities for chunk sizing.

  Provides heuristic-based token counting suitable for:
  - LLM context window budgeting
  - Token-based chunk size limits
  - Cost estimation

  ## Token Estimation

  Uses the common heuristic of ~4 characters per token, which is reasonably
  accurate for English text with typical BPE tokenizers (GPT, Claude, etc.).

  For precise token counts, use an actual tokenizer library.

  ## Examples

      # Estimate tokens in text
      iex> Tokens.estimate("Hello, world!")
      3

      # Get a sizing function for chunkers
      iex> sizer = Tokens.sizer()
      iex> sizer.("The quick brown fox")
      4

      # Custom ratio for other languages
      iex> Tokens.estimate("こんにちは世界", chars_per_token: 2)
      4
  """

  @default_chars_per_token 4

  @type text :: String.t()
  @type estimate_opts :: [chars_per_token: pos_integer()]

  @doc """
  Estimate the token count for the given text.

  Uses a heuristic of ~4 characters per token by default.
  Returns at least 1 for non-empty text.

  ## Options

    * `:chars_per_token` - Characters per token ratio (default: 4)

  ## Examples

      iex> Tokens.estimate("Hello, world!")
      3

      iex> Tokens.estimate("")
      0

      iex> Tokens.estimate("Test", chars_per_token: 2)
      2
  """
  @spec estimate(text(), estimate_opts()) :: non_neg_integer()
  def estimate(text, opts \\ [])

  def estimate("", _opts), do: 0

  def estimate(text, opts) when is_binary(text) do
    chars_per_token = Keyword.get(opts, :chars_per_token, @default_chars_per_token)
    max(1, div(String.length(text), chars_per_token))
  end

  @doc """
  Returns a sizing function for token-based chunking.

  This function can be passed as the `:get_chunk_size` option to any chunker.

  ## Options

    * `:chars_per_token` - Characters per token ratio (default: 4)

  ## Examples

      # Use with recursive chunker
      config = %{
        chunk_size: 512,
        get_chunk_size: Tokens.sizer()
      }
      {:ok, chunks} = Recursive.chunk(text, :markdown, config)

      # Custom ratio
      config = %{
        chunk_size: 256,
        get_chunk_size: Tokens.sizer(chars_per_token: 2)
      }
  """
  @spec sizer(estimate_opts()) :: (text() -> non_neg_integer())
  def sizer(opts \\ []) do
    fn text -> estimate(text, opts) end
  end

  @doc """
  Returns the default characters-per-token ratio.

  ## Examples

      iex> Tokens.default_ratio()
      4
  """
  @spec default_ratio() :: pos_integer()
  def default_ratio, do: @default_chars_per_token

  @doc """
  Convert a token count to approximate character count.

  ## Examples

      iex> Tokens.to_chars(100)
      400

      iex> Tokens.to_chars(100, chars_per_token: 3)
      300
  """
  @spec to_chars(non_neg_integer(), estimate_opts()) :: non_neg_integer()
  def to_chars(token_count, opts \\ []) do
    chars_per_token = Keyword.get(opts, :chars_per_token, @default_chars_per_token)
    token_count * chars_per_token
  end

  @doc """
  Convert a character count to approximate token count.

  Alias for `estimate/2` with a character count string.

  ## Examples

      iex> Tokens.from_chars(400)
      100
  """
  @spec from_chars(non_neg_integer(), estimate_opts()) :: non_neg_integer()
  def from_chars(char_count, opts \\ []) do
    chars_per_token = Keyword.get(opts, :chars_per_token, @default_chars_per_token)
    max(1, div(char_count, chars_per_token))
  end
end
```

## Test File: `test/adapters/chunker/tokens_test.exs`

```elixir
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
      assert Tokens.estimate("こんにちは") == 1  # 5 chars / 4 = 1
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
  end

  describe "from_chars/2" do
    test "converts characters to tokens" do
      assert Tokens.from_chars(400) == 100
      assert Tokens.from_chars(300, chars_per_token: 3) == 100
    end

    test "returns at least 1" do
      assert Tokens.from_chars(1) == 1
    end
  end

  describe "default_ratio/0" do
    test "returns 4" do
      assert Tokens.default_ratio() == 4
    end
  end
end
```

## Usage Examples

### Basic Token Estimation
```elixir
alias PortfolioIndex.Adapters.Chunker.Tokens

# Estimate tokens in a document
text = File.read!("document.md")
token_count = Tokens.estimate(text)
IO.puts("Document has ~#{token_count} tokens")
```

### Token-Based Chunking
```elixir
alias PortfolioIndex.Adapters.Chunker.{Recursive, Tokens}

# Chunk with token-based sizing
config = %{
  chunk_size: 512,  # 512 tokens max
  chunk_overlap: 50,  # 50 tokens overlap
  get_chunk_size: Tokens.sizer()
}

{:ok, chunks} = Recursive.chunk(long_document, :markdown, config)
```

### LLM Context Budgeting
```elixir
alias PortfolioIndex.Adapters.Chunker.Tokens

def fits_in_context?(text, max_tokens) do
  Tokens.estimate(text) <= max_tokens
end

def truncate_to_tokens(text, max_tokens) do
  max_chars = Tokens.to_chars(max_tokens)
  String.slice(text, 0, max_chars)
end
```
