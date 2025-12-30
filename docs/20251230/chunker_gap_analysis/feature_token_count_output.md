# Feature: `token_count` in Chunk Output

## Overview

Add estimated `token_count` to the metadata of all chunk outputs, providing LLM context budget information without requiring post-processing.

## Source Reference

**Arcana output format** (`arcana/lib/arcana/chunker.ex:63-69`):
```elixir
Enum.map(fn {text, index} ->
  %{
    text: text,
    chunk_index: index,
    token_count: estimate_tokens(text)  # <-- This field
  }
end)
```

## Current PortfolioIndex Output

```elixir
%{
  content: "...",
  index: 0,
  start_byte: 0,
  end_byte: 245,
  start_offset: 0,
  end_offset: 245,
  metadata: %{
    strategy: :recursive,
    format: :markdown,
    char_count: 245,
    separator_used: "\n## "
  }
}
```

## Proposed Enhancement

Add `token_count` to the metadata map of all chunker outputs:

```elixir
%{
  content: "...",
  index: 0,
  start_byte: 0,
  end_byte: 245,
  start_offset: 0,
  end_offset: 245,
  metadata: %{
    strategy: :recursive,
    format: :markdown,
    char_count: 245,
    token_count: 61,  # NEW
    separator_used: "\n## "
  }
}
```

## Implementation

### Modify Each Chunker Adapter

#### `lib/portfolio_index/adapters/chunker/recursive.ex`

```elixir
alias PortfolioIndex.Adapters.Chunker.Tokens

# In the chunk/3 function, modify the result mapping:
result =
  chunks
  |> Enum.with_index()
  |> Enum.map(fn {content, index} ->
    {start_offset, end_offset} = calculate_offsets(text, content, index, chunks)

    %{
      content: content,
      index: index,
      start_byte: start_offset,
      end_byte: end_offset,
      start_offset: start_offset,
      end_offset: end_offset,
      metadata: %{
        format: format,
        char_count: String.length(content),
        token_count: Tokens.estimate(content),  # NEW
        separator_used: find_separator_used(content, separators)
      }
    }
  end)
```

#### `lib/portfolio_index/adapters/chunker/character.ex`

```elixir
alias PortfolioIndex.Adapters.Chunker.Tokens

# In chunk/3:
%{
  content: content,
  index: index,
  start_byte: start_byte,
  end_byte: end_byte,
  start_offset: start_byte,
  end_offset: end_byte,
  metadata: %{
    strategy: :character,
    boundary: boundary,
    char_count: String.length(content),
    token_count: Tokens.estimate(content)  # NEW
  }
}
```

#### `lib/portfolio_index/adapters/chunker/paragraph.ex`

```elixir
alias PortfolioIndex.Adapters.Chunker.Tokens

# In chunk/3:
%{
  content: content,
  index: index,
  start_byte: start_byte,
  end_byte: end_byte,
  start_offset: start_byte,
  end_offset: end_byte,
  metadata: %{
    strategy: :paragraph,
    char_count: String.length(content),
    token_count: Tokens.estimate(content),  # NEW
    paragraph_count: count_paragraphs(content)
  }
}
```

#### `lib/portfolio_index/adapters/chunker/sentence.ex`

```elixir
alias PortfolioIndex.Adapters.Chunker.Tokens

# In chunk/3:
%{
  content: content,
  index: index,
  start_byte: start_byte,
  end_byte: end_byte,
  start_offset: start_byte,
  end_offset: end_byte,
  metadata: %{
    strategy: :sentence,
    char_count: String.length(content),
    token_count: Tokens.estimate(content),  # NEW
    sentence_count: sentence_count
  }
}
```

#### `lib/portfolio_index/adapters/chunker/semantic.ex`

```elixir
alias PortfolioIndex.Adapters.Chunker.Tokens

# In add_positions/2 and build_single_chunk/2:
chunk = %{
  content: content,
  index: idx,
  start_byte: start_byte,
  end_byte: end_byte,
  start_offset: start_byte,
  end_offset: end_byte,
  metadata: %{
    strategy: :semantic,
    char_count: String.length(content),
    token_count: Tokens.estimate(content),  # NEW
    sentence_count: length(sentences)
  }
}
```

## Test Updates

### Add to Each Chunker Test File

```elixir
describe "token_count in output" do
  test "includes token_count in metadata" do
    {:ok, chunks} = Chunker.chunk("This is a test sentence.", :plain, %{chunk_size: 1000})

    assert length(chunks) > 0
    chunk = hd(chunks)
    assert Map.has_key?(chunk.metadata, :token_count)
    assert is_integer(chunk.metadata.token_count)
    assert chunk.metadata.token_count > 0
  end

  test "token_count is approximately char_count / 4" do
    text = String.duplicate("a", 100)
    {:ok, [chunk]} = Chunker.chunk(text, :plain, %{chunk_size: 1000})

    assert chunk.metadata.char_count == 100
    assert chunk.metadata.token_count == 25
  end
end
```

## Usage Examples

### Filter Chunks by Token Budget
```elixir
alias PortfolioIndex.Adapters.Chunker.Recursive

{:ok, chunks} = Recursive.chunk(document, :markdown, config)

# Filter to chunks that fit in context window
max_tokens = 4096
fitting_chunks = Enum.filter(chunks, fn c ->
  c.metadata.token_count <= max_tokens
end)
```

### Calculate Total Tokens
```elixir
{:ok, chunks} = Recursive.chunk(document, :markdown, config)

total_tokens = chunks
|> Enum.map(& &1.metadata.token_count)
|> Enum.sum()

IO.puts("Document chunked into #{length(chunks)} chunks, ~#{total_tokens} tokens total")
```

### LLM Context Packing
```elixir
def pack_chunks_for_context(chunks, max_tokens) do
  {packed, _remaining} =
    Enum.reduce(chunks, {[], max_tokens}, fn chunk, {acc, budget} ->
      token_count = chunk.metadata.token_count
      if token_count <= budget do
        {[chunk | acc], budget - token_count}
      else
        {acc, budget}
      end
    end)

  Enum.reverse(packed)
end
```

## Considerations

### Performance
- `Tokens.estimate/1` is O(n) where n is string length (via `String.length/1`)
- Called once per chunk during chunking
- Negligible overhead compared to the splitting itself

### Accuracy
- The 4 chars/token heuristic is approximate
- Actual token counts vary by:
  - Language (CJK characters often 1 token each)
  - Tokenizer (GPT vs Claude vs others)
  - Content (code vs prose)
- For precise counts, users should use an actual tokenizer

### Alternative: Make Optional
Could add `:include_token_count` option to config if the overhead is ever a concern:
```elixir
config = %{chunk_size: 1000, include_token_count: false}
```

But this is probably over-engineering for a simple string length operation.
