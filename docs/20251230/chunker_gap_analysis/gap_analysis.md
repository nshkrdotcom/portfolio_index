# Chunker Gap Analysis: text_chunker_ex + Arcana vs PortfolioIndex

> **Note**: The `size_unit` type has been added to the `PortfolioCore.Ports.Chunker` port
> specification as of v0.3.1. See `../../../portfolio_core/lib/portfolio_core/ports/chunker.ex`.
> PortfolioIndex adapters need to implement support for this port-level option.

## Executive Summary

This document analyzes features present in `text_chunker_ex` (the library) combined with `Arcana` (the wrapper) that are **missing** from `PortfolioIndex`.

**Key Finding**: PortfolioIndex already has robust chunking with more strategies than text_chunker_ex. The gaps are primarily in **convenience features** and **RAG-specific integrations**.

---

## Feature Comparison Matrix

| Feature | text_chunker_ex | Arcana | PortfolioIndex | Gap? |
|---------|-----------------|--------|----------------|------|
| Recursive chunking | ✅ | via lib | ✅ | No |
| Format-specific separators | ✅ 17 formats | via lib | ✅ 17 formats | No |
| Character chunker | ❌ | ❌ | ✅ | PI ahead |
| Paragraph chunker | ❌ | ❌ | ✅ | PI ahead |
| Sentence chunker | ❌ | ❌ | ✅ | PI ahead |
| Semantic chunker | ❌ | ❌ | ✅ | PI ahead |
| Custom `get_chunk_size` | ✅ | ❌ (hardcoded) | ✅ | No |
| `size_unit: :tokens` option | ❌ | ✅ | ❌ | **Yes** |
| Built-in token estimation | ❌ | ✅ | ❌ | **Yes** |
| Byte position tracking | ✅ | ❌ (discards) | ✅ | No |
| ChunkerBehaviour | ✅ | ❌ | ✅ (via Port) | No |
| NimbleOptions validation | ✅ | ❌ | ✅ | No |
| Ecto Chunk schema | ❌ | ✅ | ❌ | **Yes** |
| Pgvector embedding field | ❌ | ✅ | ❌ | **Yes** |
| Document relationship | ❌ | ✅ | ❌ | **Yes** |
| Output: `text` key | ✅ | ✅ | ❌ (`content`) | Diff |
| Output: `token_count` | ❌ | ✅ | ❌ | **Yes** |

---

## Identified Gaps

### Gap 1: High-Level Token Sizing Option (`size_unit`)

**What Arcana has:**
```elixir
# Arcana - simple token-based sizing
Arcana.Chunker.chunk(text, size_unit: :tokens, chunk_size: 512)
```

**What PortfolioIndex requires:**
```elixir
# PortfolioIndex - must provide custom function
config = %{
  chunk_size: 512,
  get_chunk_size: fn text -> div(String.length(text), 4) end
}
Recursive.chunk(text, :plain, config)
```

**Impact**: Users must implement their own token estimation. This is a convenience gap, not a capability gap.

---

### Gap 2: Built-in Token Estimation Utility

**What Arcana has:**
```elixir
# arcana/lib/arcana/chunker.ex:75-79
defp estimate_tokens(text) do
  max(1, div(String.length(text), 4))
end
```

**What PortfolioIndex lacks:**
- No centralized `estimate_tokens/1` function
- No token count in chunk output

**Impact**: Each consumer must implement their own estimation.

---

### Gap 3: RAG-Ready Chunk Output Format

**Arcana output:**
```elixir
[
  %{text: "...", chunk_index: 0, token_count: 125},
  %{text: "...", chunk_index: 1, token_count: 118}
]
```

**PortfolioIndex output:**
```elixir
[
  %{content: "...", index: 0, start_byte: 0, end_byte: 245, ...},
  %{content: "...", index: 1, start_byte: 200, end_byte: 450, ...}
]
```

**Differences:**
| Arcana | PortfolioIndex | Notes |
|--------|----------------|-------|
| `text` | `content` | Key naming |
| `chunk_index` | `index` | Key naming |
| `token_count` | ❌ | Missing in PI |
| ❌ | `start_byte` | PI has more metadata |
| ❌ | `end_byte` | PI has more metadata |
| ❌ | `metadata` | PI has more metadata |

**Impact**: PortfolioIndex has MORE metadata, but lacks the simple `token_count` field useful for LLM context budgeting.

---

### Gap 4: Ecto Schema for Chunk Persistence

**What Arcana has (`arcana/lib/arcana/chunk.ex`):**
```elixir
schema "arcana_chunks" do
  field(:text, :string)
  field(:embedding, Pgvector.Ecto.Vector)
  field(:chunk_index, :integer, default: 0)
  field(:token_count, :integer)
  field(:metadata, :map, default: %{})
  belongs_to(:document, Arcana.Document)
  timestamps()
end
```

**What PortfolioIndex lacks:**
- No pre-built Ecto schema for chunks
- No embedded vector field in chunk model
- No document relationship

**Impact**: Users must define their own chunk persistence schema.

---

## What PortfolioIndex Has That text_chunker_ex + Arcana Lack

### 1. Multiple Chunking Strategies
- `Character` - boundary-aware character splitting (`:word`, `:sentence`, `:none`)
- `Paragraph` - paragraph-based with intelligent merging
- `Sentence` - NLP tokenization with abbreviation handling
- `Semantic` - embedding-based similarity grouping
- `Recursive` - format-aware hierarchical splitting

text_chunker_ex only has `Recursive`.

### 2. Richer Chunk Metadata
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

### 3. NimbleOptions Config Validation
Full compile-time schema validation via `Config` module.

### 4. True Custom Sizing
PortfolioIndex's `get_chunk_size` is used throughout the algorithm. Arcana's token mode just multiplies by 4 upfront.

---

## Recommendations

### Priority 1: Add Token Utilities (Low Effort, High Value)

Create `PortfolioIndex.Adapters.Chunker.Tokens` module:
```elixir
defmodule PortfolioIndex.Adapters.Chunker.Tokens do
  @moduledoc "Token estimation utilities for chunk sizing."

  @chars_per_token 4

  @doc "Estimate token count from text using ~4 chars/token heuristic."
  def estimate(text), do: max(1, div(String.length(text), @chars_per_token))

  @doc "Get a sizing function for token-based chunking."
  def sizer, do: &estimate/1
end
```

### Priority 2: Add `size_unit` Option to Config (Medium Effort)

Extend `Config` to support:
```elixir
config = Config.validate!(%{
  chunk_size: 512,
  size_unit: :tokens  # NEW - auto-sets get_chunk_size
})
```

### Priority 3: Add `token_count` to Output (Low Effort)

Include token count in chunk metadata:
```elixir
metadata: %{
  # existing...
  token_count: Tokens.estimate(content)
}
```

### Priority 4: Optional Chunk Schema (Medium Effort, Optional)

Could provide an optional `PortfolioIndex.Schemas.Chunk` for users who want it, but this is arguably out of scope for an index library.

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/portfolio_index/adapters/chunker/tokens.ex` | NEW - Token utilities |
| `lib/portfolio_index/adapters/chunker/config.ex` | Add `:size_unit` option |
| `lib/portfolio_index/adapters/chunker/recursive.ex` | Add `token_count` to output |
| `lib/portfolio_index/adapters/chunker/character.ex` | Add `token_count` to output |
| `lib/portfolio_index/adapters/chunker/paragraph.ex` | Add `token_count` to output |
| `lib/portfolio_index/adapters/chunker/sentence.ex` | Add `token_count` to output |
| `lib/portfolio_index/adapters/chunker/semantic.ex` | Add `token_count` to output |
| `test/adapters/chunker/tokens_test.exs` | NEW - Token utility tests |

---

## Conclusion

PortfolioIndex is **more capable** than text_chunker_ex + Arcana combined in terms of chunking strategies and metadata. The gaps are:

1. **Convenience**: No `size_unit: :tokens` shorthand
2. **Utility**: No built-in `estimate_tokens/1` function
3. **Output**: No `token_count` in chunk output
4. **Schema**: No pre-built Ecto model (arguably not needed)

These are all **additive enhancements** that don't require architectural changes.
