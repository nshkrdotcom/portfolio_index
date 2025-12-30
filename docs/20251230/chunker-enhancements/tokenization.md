# Tokenization Guide

## Overview

The `get_chunk_size` configuration option allows custom size measurement for chunks. By default, chunkers use character count (`String.length/1`), but you can provide any function that measures text size.

## Why Custom Tokenization?

### Character Count (Default)

```elixir
get_chunk_size: &String.length/1
```

- Simple and fast
- Language-agnostic
- Good for general text processing

### Token Count (LLM)

```elixir
get_chunk_size: &MyTokenizer.count_tokens/1
```

- Matches LLM context limits exactly
- Different models have different tokenizers
- Essential for embedding models with token limits

### Byte Size

```elixir
get_chunk_size: &byte_size/1
```

- Useful for storage constraints
- Handles multi-byte UTF-8 correctly
- Good for network transmission limits

### Word Count

```elixir
get_chunk_size: fn text ->
  text |> String.split(~r/\s+/) |> length()
end
```

- Natural language oriented
- Good for readability metrics

## Implementation

### Basic Usage

```elixir
alias PortfolioIndex.Adapters.Chunker.Recursive

# Character-based (default)
config = %{chunk_size: 1000, chunk_overlap: 200}
{:ok, chunks} = Recursive.chunk(text, :plain, config)

# Token-based
config = %{
  chunk_size: 512,  # 512 tokens
  chunk_overlap: 50,
  get_chunk_size: &MyTokenizer.count_tokens/1
}
{:ok, chunks} = Recursive.chunk(text, :plain, config)
```

### With OpenAI Tokenizer

If using an OpenAI-compatible tokenizer:

```elixir
defmodule MyApp.Tokenizer do
  @doc "Count tokens using tiktoken-compatible encoding"
  def count_tokens(text) do
    # Example using a tiktoken port/NIF
    Tiktoken.count(text, "cl100k_base")
  end
end

config = %{
  chunk_size: 8000,  # GPT-4 context window consideration
  chunk_overlap: 500,
  get_chunk_size: &MyApp.Tokenizer.count_tokens/1
}
```

### With Approximate Token Count

For a fast approximation without external dependencies:

```elixir
defmodule MyApp.Tokenizer do
  @doc """
  Approximate token count using word/character heuristics.

  Rule of thumb: ~4 characters per token for English text.
  """
  def approximate_tokens(text) do
    # Rough approximation: 1 token ≈ 4 characters
    div(String.length(text), 4)
  end

  @doc """
  Word-based approximation.

  Rule of thumb: ~0.75 tokens per word for English.
  """
  def word_based_tokens(text) do
    word_count = text |> String.split(~r/\s+/) |> length()
    round(word_count * 0.75)
  end
end
```

## Function Requirements

The `get_chunk_size` function must:

1. **Accept a string** - `(String.t() -> integer())`
2. **Return a non-negative integer** - The "size" of the text
3. **Be deterministic** - Same input always produces same output
4. **Handle empty strings** - Return 0 for empty input
5. **Be reasonably fast** - Called frequently during chunking

### Example: Valid Functions

```elixir
# Built-in functions
&String.length/1      # Character count
&byte_size/1          # Byte count

# Custom functions
fn text -> String.length(text) end
fn text -> div(byte_size(text), 4) end
fn "" -> 0; text -> MyTokenizer.count(text) end
```

### Example: Invalid Functions

```elixir
# Wrong arity
fn -> 0 end
fn text, _opts -> String.length(text) end

# Wrong return type
fn text -> "#{String.length(text)} chars" end

# Non-deterministic
fn text -> String.length(text) + :rand.uniform(10) end
```

## Performance Considerations

### Caching

For expensive tokenizers, consider caching:

```elixir
defmodule MyApp.CachedTokenizer do
  use GenServer

  def count_tokens(text) do
    case :ets.lookup(:token_cache, text) do
      [{^text, count}] -> count
      [] ->
        count = expensive_tokenize(text)
        :ets.insert(:token_cache, {text, count})
        count
    end
  end
end
```

### Batch Processing

If your tokenizer supports batching:

```elixir
# Pre-tokenize all potential chunks
defmodule MyApp.BatchTokenizer do
  def prepare(texts) do
    # Batch tokenize and cache results
    results = MyTokenizer.batch_count(texts)
    :ets.insert(:token_cache, Enum.zip(texts, results))
  end
end
```

## Comparison Table

| Method | Speed | Accuracy | Use Case |
|--------|-------|----------|----------|
| `String.length/1` | Fast | N/A | General text |
| `byte_size/1` | Fast | N/A | Storage limits |
| Approximate (~4 char) | Fast | ~80% | Quick estimates |
| tiktoken | Medium | 100% | OpenAI models |
| SentencePiece | Medium | 100% | Many models |
| Custom NIF | Fast | 100% | Production systems |

## Chunker Compatibility

All chunker adapters support `get_chunk_size`:

| Adapter | Support | Notes |
|---------|---------|-------|
| `Recursive` | Full | Primary use case |
| `Character` | Full | Used in all boundary modes |
| `Sentence` | Full | Applied to sentence groups |
| `Paragraph` | Full | Applied to paragraph groups |
| `Semantic` | Full | Used alongside `max_chars` |

## Migration from Character-Based

If migrating from character-based to token-based chunking:

```elixir
# Before: 1000 characters
old_config = %{chunk_size: 1000, chunk_overlap: 200}

# After: ~250 tokens (1000 chars ÷ 4)
new_config = %{
  chunk_size: 250,
  chunk_overlap: 50,
  get_chunk_size: &MyTokenizer.count_tokens/1
}
```

Adjust `chunk_size` based on your character-to-token ratio (typically 3-5 characters per token for English).
