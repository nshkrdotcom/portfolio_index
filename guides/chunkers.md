# Chunkers

PortfolioIndex provides multiple text chunking strategies for splitting documents
into appropriately sized pieces for embedding and retrieval.

## Available Chunkers

| Adapter | Strategy | Best For |
|---------|----------|----------|
| `Recursive` | Recursive splitting with format-aware separators | Code, structured text |
| `Character` | Fixed-size character windows | Simple splitting |
| `Sentence` | Sentence-boundary splitting | Prose, articles |
| `Paragraph` | Paragraph-boundary splitting | Well-structured documents |
| `Semantic` | Embedding similarity grouping | Topic-coherent chunks |

All chunkers implement the `PortfolioCore.Ports.Chunker` behaviour.

## Recursive Chunker

`PortfolioIndex.Adapters.Chunker.Recursive` splits text using format-specific
separators, falling back to progressively smaller separators:

```elixir
alias PortfolioIndex.Adapters.Chunker.Recursive

chunks = Recursive.chunk(text, :elixir, %{
  chunk_size: 1000,
  chunk_overlap: 200
})
```

### Supported Formats

The `PortfolioIndex.Adapters.Chunker.Separators` module provides separators
for 17+ formats:

| Category | Formats |
|----------|---------|
| Languages | `:elixir`, `:ruby`, `:php`, `:python`, `:javascript`, `:typescript`, `:vue` |
| Markup | `:markdown`, `:html`, `:latex` |
| Documents | `:doc`, `:docx`, `:epub`, `:odt`, `:pdf`, `:rtf` |
| Plain text | `:plain` |

Markdown splitting is header-aware, preserving document structure.

## Character Chunker

`PortfolioIndex.Adapters.Chunker.Character` splits at fixed character intervals
with configurable boundary modes:

```elixir
alias PortfolioIndex.Adapters.Chunker.Character

chunks = Character.chunk(text, %{
  chunk_size: 500,
  chunk_overlap: 50,
  boundary: :word        # :word | :sentence | :none
})
```

Boundary modes:
- `:word` -- break at word boundaries (default)
- `:sentence` -- break at sentence boundaries
- `:none` -- break at exact character count

## Sentence Chunker

`PortfolioIndex.Adapters.Chunker.Sentence` splits text at sentence boundaries
using NLP tokenization:

```elixir
alias PortfolioIndex.Adapters.Chunker.Sentence

chunks = Sentence.chunk(text, %{
  chunk_size: 1000,
  chunk_overlap: 100
})
```

Handles abbreviations (Dr., Mr., etc.) and other edge cases that naive
sentence splitting misses.

## Paragraph Chunker

`PortfolioIndex.Adapters.Chunker.Paragraph` splits at paragraph boundaries
with intelligent merging of short paragraphs:

```elixir
alias PortfolioIndex.Adapters.Chunker.Paragraph

chunks = Paragraph.chunk(text, %{
  chunk_size: 1500,
  chunk_overlap: 200
})
```

Short paragraphs are merged to avoid tiny chunks; long paragraphs are split
at sentence boundaries.

## Semantic Chunker

`PortfolioIndex.Adapters.Chunker.Semantic` groups text by embedding similarity,
producing topic-coherent chunks:

```elixir
alias PortfolioIndex.Adapters.Chunker.Semantic

chunks = Semantic.chunk(text, %{
  chunk_size: 1000,
  similarity_threshold: 0.8,
  embedder: PortfolioIndex.Adapters.Embedder.Gemini
})
```

This chunker embeds each sentence and groups consecutive sentences with high
similarity into the same chunk.

## Token-Based Chunking

All chunkers support custom size measurement via the `:get_chunk_size` option
or the `:size_unit` shorthand:

```elixir
# Token-based sizing (for LLM context limits)
Recursive.chunk(text, :elixir, %{
  chunk_size: 256,
  size_unit: :tokens
})

# Custom sizing function
Recursive.chunk(text, :elixir, %{
  chunk_size: 256,
  get_chunk_size: &MyTokenizer.count_tokens/1
})

# Byte-based sizing (for storage limits)
Recursive.chunk(text, :plain, %{
  chunk_size: 4096,
  get_chunk_size: &byte_size/1
})
```

The `PortfolioIndex.Adapters.Chunker.Tokens` module provides token estimation:

```elixir
alias PortfolioIndex.Adapters.Chunker.Tokens

Tokens.estimate("Hello world")     # => ~2
Tokens.sizer(:tokens)              # => sizing function
Tokens.to_chars(256)               # => ~1024 characters
Tokens.from_chars(1000)            # => ~250 tokens
Tokens.default_ratio()             # => 4 (chars per token)
```

## Configuration

`PortfolioIndex.Adapters.Chunker.Config` validates chunker configuration using
NimbleOptions:

```elixir
alias PortfolioIndex.Adapters.Chunker.Config

{:ok, validated} = Config.validate(%{
  chunk_size: 1000,
  chunk_overlap: 200,
  size_unit: :tokens
})
```

## Chunk Metadata

All chunkers include metadata with each chunk:

- `start_char` / `end_char` -- character offsets in the original text
- `token_count` -- estimated token count (~`char_count / 4`)
- `chunk_index` -- position in the chunk sequence

Token counts are useful for LLM context window budgeting.
