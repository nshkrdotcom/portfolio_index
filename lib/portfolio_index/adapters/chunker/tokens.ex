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
      iex> Tokens.estimate("12345678", chars_per_token: 2)
      4
  """

  @default_chars_per_token 4

  @type text :: String.t()
  @type estimate_opts :: [chars_per_token: pos_integer()]

  @doc """
  Estimate the token count for the given text.

  Uses a heuristic of ~4 characters per token by default.
  Returns at least 1 for non-empty text, 0 for empty text.

  ## Options

    * `:chars_per_token` - Characters per token ratio (default: 4)

  ## Examples

      iex> Tokens.estimate("Hello, world!")
      3

      iex> Tokens.estimate("")
      0

      iex> Tokens.estimate("12345678", chars_per_token: 2)
      4
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

  Returns at least 1 for non-zero character counts.

  ## Examples

      iex> Tokens.from_chars(400)
      100

      iex> Tokens.from_chars(300, chars_per_token: 3)
      100

      iex> Tokens.from_chars(1)
      1
  """
  @spec from_chars(non_neg_integer(), estimate_opts()) :: non_neg_integer()
  def from_chars(char_count, opts \\ [])

  def from_chars(0, _opts), do: 0

  def from_chars(char_count, opts) do
    chars_per_token = Keyword.get(opts, :chars_per_token, @default_chars_per_token)
    max(1, div(char_count, chars_per_token))
  end
end
