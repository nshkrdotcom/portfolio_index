# Chunker Enhancements v0.3.1

## Overview

This release enhances the chunker adapters with features from `text_chunker_ex`, providing:

1. **Language-Specific Separators** - Intelligent splitting for 10+ programming languages
2. **Pluggable Tokenization** - Custom `get_chunk_size` function for token-based chunking
3. **NimbleOptions Validation** - Schema-based configuration validation
4. **Extended Format Support** - Document formats (doc, docx, epub, latex, odt, pdf, rtf)

## Architecture

### Module Structure

```
lib/portfolio_index/adapters/chunker/
├── character.ex      # Character-based chunking with boundary modes
├── config.ex         # NEW: NimbleOptions configuration validation
├── paragraph.ex      # Paragraph-based chunking
├── recursive.ex      # Format-aware recursive chunking (enhanced)
├── semantic.ex       # Embedding-based semantic chunking
├── sentence.ex       # Sentence-based chunking
└── separators.ex     # NEW: Centralized separator definitions
```

### Design Principles

1. **Single Responsibility** - Separators module handles only separator definitions
2. **Open/Closed** - New formats added without modifying existing code
3. **Dependency Inversion** - Chunkers depend on abstractions (config schema), not concretions
4. **Backwards Compatibility** - All existing APIs continue to work unchanged

## Supported Formats

### Programming Languages

| Format | Description | Key Separators |
|--------|-------------|----------------|
| `:elixir` | Elixir/Erlang | defmodule, def, defp, case, cond |
| `:ruby` | Ruby | class, def, if, unless, begin |
| `:php` | PHP | class, function, public/private/protected |
| `:python` | Python | class, def |
| `:javascript` | JavaScript | class, function, const, let, var |
| `:typescript` | TypeScript | Same as JavaScript |
| `:vue` | Vue.js SFC | template, script, section + JS |

### Markup Languages

| Format | Description | Key Separators |
|--------|-------------|----------------|
| `:markdown` | Markdown | Headers (##), code blocks, horizontal rules |
| `:html` | HTML | Heading tags, semantic elements |
| `:plain` | Plain text | Paragraphs, lines, spaces |

### Document Formats

| Format | Description | Notes |
|--------|-------------|-------|
| `:doc` | Microsoft Word | Uses plaintext separators |
| `:docx` | Word (XML) | Uses plaintext separators |
| `:epub` | E-book | Uses plaintext separators |
| `:latex` | LaTeX | Uses plaintext separators |
| `:odt` | OpenDocument | Uses plaintext separators |
| `:pdf` | PDF | Uses plaintext separators |
| `:rtf` | Rich Text | Uses plaintext separators |

## Configuration

### Basic Usage

```elixir
alias PortfolioIndex.Adapters.Chunker.Recursive

config = %{
  chunk_size: 1000,
  chunk_overlap: 200
}

{:ok, chunks} = Recursive.chunk(code, :elixir, config)
```

### With Custom Tokenizer

```elixir
# Token-based chunking (for LLM context limits)
config = %{
  chunk_size: 512,  # tokens, not characters
  chunk_overlap: 50,
  get_chunk_size: &MyTokenizer.count_tokens/1
}

{:ok, chunks} = Recursive.chunk(text, :plain, config)
```

### With Custom Separators

```elixir
config = %{
  chunk_size: 1000,
  chunk_overlap: 100,
  separators: ["\n## ", "\n### ", "\n\n", "\n", " "]
}

{:ok, chunks} = Recursive.chunk(markdown, :markdown, config)
```

## Migration Guide

### From v0.3.0

No breaking changes. Existing code continues to work:

```elixir
# This still works exactly as before
config = %{chunk_size: 1000, chunk_overlap: 200}
{:ok, chunks} = Recursive.chunk(text, :markdown, config)
```

### New Features

To use new features, simply add the new config options:

```elixir
# Add get_chunk_size for token-based chunking
config = %{
  chunk_size: 1000,
  chunk_overlap: 200,
  get_chunk_size: &byte_size/1  # or custom tokenizer
}
```

## Performance Considerations

1. **Separator Lookup** - O(1) via compile-time maps
2. **Custom Tokenizers** - Called once per size check; ensure efficiency
3. **Large Documents** - Recursive splitting is O(n) where n = document size

## Related Documentation

- [Separators Reference](separators.md)
- [Tokenization Guide](tokenization.md)
