# Separators Reference

## Overview

Separators define where text can be split during chunking. The recursive chunker tries separators in priority order, falling back to smaller separators when chunks exceed the size limit.

## Separator Priority

Separators are ordered from most significant (semantic boundaries) to least significant (character level):

1. **Structural** - Module/class/function definitions
2. **Logical** - Control flow statements
3. **Paragraph** - Double newlines
4. **Line** - Single newlines
5. **Word** - Spaces
6. **Character** - Empty string (last resort)

## Language Specifications

### Elixir

```elixir
[
  # Top-level declarations
  "\ndefmodule ",
  "\ndefprotocol ",
  "\ndefimpl ",
  # Nested declarations (2-space indent)
  "  defmodule ",
  "  defprotocol ",
  "  defimpl ",
  # Documentation and functions
  "@doc \"\"\"",
  "  def ",
  "  defp ",
  # Control flow
  "  with ",
  "  cond ",
  "  case ",
  "  if ",
  # Fallback
  "\n\n", "\n", " "
]
```

**Use case**: Elixir source files, ExUnit tests, mix projects.

### Ruby

```elixir
[
  # Class definitions
  "\nclass ",
  "  class ",
  # Documentation comments
  "\n##",
  "  ##",
  # Access modifiers
  "  private\n",
  # Method definitions
  "\ndef ",
  "  def ",
  # Control flow
  "  if ",
  "  unless ",
  "  while ",
  "  for ",
  "  do ",
  "  begin ",
  "  rescue ",
  # Fallback
  "\n\n", "\n", " "
]
```

**Use case**: Ruby source files, Rails applications, RSpec tests.

### PHP

```elixir
[
  # Class definitions
  "\nclass ",
  "  class ",
  # Documentation blocks
  "\n/**",
  "  /**",
  # Function definitions
  "\nfunction ",
  "  function ",
  "public function ",
  "protected function ",
  "private function ",
  # Control flow
  "  if ",
  "  foreach ",
  "  while ",
  "  do ",
  "  switch ",
  "  case ",
  # Fallback
  "\n\n", "\n", " "
]
```

**Use case**: PHP source files, Laravel/Symfony applications.

### Python

```elixir
[
  # Class definitions
  "\nclass ",
  # Function definitions
  "\ndef ",
  "\n\tdef ",  # Tab-indented (some codebases)
  # Fallback
  "\n\n", "\n", " "
]
```

**Use case**: Python source files, Django/Flask applications, Jupyter notebooks.

### JavaScript

```elixir
[
  # Class definitions
  "\nclass ",
  "  class ",
  # Function definitions
  "\nfunction ",
  "  function ",
  # Module exports
  "\nexport const ",
  "\nexport default ",
  # Variable declarations
  "\nconst ",
  "  const ",
  "  let ",
  "  var ",
  # Control flow
  "  if ",
  "  for ",
  "  while ",
  "  switch ",
  "  case ",
  "  default ",
  # Fallback
  "\n\n", "\n", " "
]
```

**Use case**: JavaScript source files, Node.js, React/Vue/Angular components.

### TypeScript

TypeScript uses the same separators as JavaScript, as the syntax is a superset.

### Vue

```elixir
[
  # Vue SFC sections
  "<script",
  "<section",
  "<table",
  "<template",
  # Plus all JavaScript separators
  ...javascript_separators()
]
```

**Use case**: Vue.js Single File Components (.vue files).

### HTML

```elixir
[
  # Heading hierarchy
  "<h1", "<h2", "<h3", "<h4", "<h5", "<h6",
  # Content elements
  "<p", "<ul", "<ol", "<li",
  # Semantic sections
  "<article", "<section", "<table",
  # Fallback
  "\n\n", "\n", " "
]
```

**Use case**: HTML files, templates, web content.

### Markdown

```elixir
[
  # Header hierarchy (H2-H6, H1 typically is title)
  "\n## ",
  "\n### ",
  "\n#### ",
  "\n##### ",
  "\n###### ",
  # Code block boundaries
  "```\n\n",
  # Horizontal rules
  "\n\n___\n\n",
  "\n\n---\n\n",
  "\n\n***\n\n",
  # Fallback
  "\n\n", "\n", " "
]
```

**Use case**: Markdown documentation, README files, blog posts.

### Plain Text

```elixir
[
  "\n\n",  # Paragraphs
  "\n",    # Lines
  " "      # Words
]
```

**Use case**: Generic text, extracted document content.

### Document Formats

The following formats use plaintext separators:

- `:doc` - Microsoft Word (.doc)
- `:docx` - Microsoft Word XML (.docx)
- `:epub` - E-book format
- `:latex` - LaTeX documents
- `:odt` - OpenDocument Text
- `:pdf` - PDF (extracted text)
- `:rtf` - Rich Text Format

## Custom Separators

Override default separators via the `:separators` config option:

```elixir
config = %{
  chunk_size: 1000,
  chunk_overlap: 100,
  separators: [
    "\n## ",      # H2 headers
    "\n### ",     # H3 headers
    "\n\n",       # Paragraphs
    "\n",         # Lines
    ". ",         # Sentences
    " "           # Words
  ]
}

{:ok, chunks} = Recursive.chunk(text, :custom, config)
```

## Separator Selection Algorithm

```
1. Get format-specific separator list
2. Find first separator that exists in text
3. Split text on that separator (lookahead, preserves separator)
4. For each split:
   a. If small enough → keep
   b. If too large → recursively split with remaining separators
5. Merge adjacent small splits to approach chunk_size
6. Apply overlap between chunks
```

## Best Practices

1. **Match format to content** - Use `:elixir` for .ex files, `:markdown` for .md
2. **Custom separators sparingly** - Built-in separators cover most cases
3. **Order matters** - Most significant separators first
4. **Include fallbacks** - Always end with `["\n\n", "\n", " "]`
