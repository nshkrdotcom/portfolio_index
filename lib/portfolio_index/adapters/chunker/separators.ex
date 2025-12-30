defmodule PortfolioIndex.Adapters.Chunker.Separators do
  @moduledoc """
  Centralized separator definitions for text chunking strategies.

  Provides format-specific separator lists optimized for intelligent text splitting.
  Separators are ordered by significance: structural boundaries first, then
  logical boundaries, paragraphs, lines, and finally character-level fallbacks.

  ## Supported Formats

  ### Programming Languages
  - `:elixir` / `:code` - Elixir/Erlang source files
  - `:ruby` - Ruby source files
  - `:php` - PHP source files
  - `:python` - Python source files
  - `:javascript` - JavaScript source files
  - `:typescript` - TypeScript source files (delegates to JavaScript)
  - `:vue` - Vue.js Single File Components

  ### Markup Languages
  - `:markdown` - Markdown documents
  - `:html` - HTML documents
  - `:plain` - Plain text (default)

  ### Document Formats
  - `:doc`, `:docx`, `:epub`, `:latex`, `:odt`, `:pdf`, `:rtf`
  - All use plaintext separators (content is typically pre-extracted)

  ## Usage

      iex> Separators.get_separators(:elixir)
      ["\\ndefmodule ", "\\ndefprotocol ", ...]

      iex> Separators.supported_formats()
      [:plain, :markdown, :elixir, :ruby, ...]
  """

  @type format ::
          :plain
          | :markdown
          | :elixir
          | :code
          | :ruby
          | :php
          | :python
          | :javascript
          | :typescript
          | :vue
          | :html
          | :doc
          | :docx
          | :epub
          | :latex
          | :odt
          | :pdf
          | :rtf

  # Document formats that use plaintext separators
  @plaintext_formats [:doc, :docx, :epub, :latex, :odt, :pdf, :rtf]

  # All supported formats
  @supported_formats [
    :plain,
    :markdown,
    :elixir,
    :code,
    :ruby,
    :php,
    :python,
    :javascript,
    :typescript,
    :vue,
    :html | @plaintext_formats
  ]

  @doc """
  Returns the list of all supported formats.

  ## Examples

      iex> :elixir in Separators.supported_formats()
      true
  """
  @spec supported_formats() :: [format()]
  def supported_formats, do: @supported_formats

  @doc """
  Returns the basic fallback separators used by all formats.

  These are: paragraph (`"\\n\\n"`), line (`"\\n"`), and word (`" "`).

  ## Examples

      iex> Separators.fallback_separators()
      ["\\n\\n", "\\n", " "]
  """
  @spec fallback_separators() :: [String.t()]
  def fallback_separators, do: ["\n\n", "\n", " "]

  @doc """
  Returns the separator list for the given format.

  Separators are ordered from most significant (structural boundaries like
  module/class definitions) to least significant (spaces). The chunking
  algorithm tries separators in order, falling back to smaller separators
  when chunks exceed the size limit.

  Unknown formats fall back to plaintext separators.

  ## Parameters

    - `format` - The content format (e.g., `:elixir`, `:markdown`, `:plain`)

  ## Examples

      iex> seps = Separators.get_separators(:elixir)
      iex> "\\ndefmodule " in seps
      true

      iex> seps = Separators.get_separators(:markdown)
      iex> "\\n## " in seps
      true
  """
  @spec get_separators(format() | atom()) :: [String.t()]
  def get_separators(:plain), do: fallback_separators()

  def get_separators(:markdown) do
    [
      # Header hierarchy (H2-H6, H1 is typically the document title)
      "\n## ",
      "\n### ",
      "\n#### ",
      "\n##### ",
      "\n###### ",
      # Code block boundaries
      "```\n\n",
      # Horizontal rules (various syntaxes)
      "\n\n___\n\n",
      "\n\n---\n\n",
      "\n\n***\n\n"
    ] ++ fallback_separators()
  end

  def get_separators(:elixir) do
    [
      # Top-level declarations
      "\ndefmodule ",
      "\ndefprotocol ",
      "\ndefimpl ",
      # Nested declarations (2-space indent, Elixir convention)
      "  defmodule ",
      "  defprotocol ",
      "  defimpl ",
      # Documentation and function definitions
      "@doc \"\"\"",
      "  def ",
      "  defp ",
      # Control flow
      "  with ",
      "  cond ",
      "  case ",
      "  if "
    ] ++ fallback_separators()
  end

  # :code is an alias for :elixir (for backwards compatibility)
  def get_separators(:code), do: get_separators(:elixir)

  def get_separators(:ruby) do
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
      "  rescue "
    ] ++ fallback_separators()
  end

  def get_separators(:php) do
    [
      # Class definitions
      "\nclass ",
      "  class ",
      # Documentation blocks
      "\n/**",
      "  /**",
      # Function definitions (various visibilities)
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
      "  case "
    ] ++ fallback_separators()
  end

  def get_separators(:python) do
    [
      # Class definitions
      "\nclass ",
      # Function definitions
      "\ndef ",
      # Tab-indented functions (some codebases use tabs)
      "\n\tdef "
    ] ++ fallback_separators()
  end

  def get_separators(:javascript) do
    [
      # Class definitions
      "\nclass ",
      "  class ",
      # Function declarations
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
      "  default "
    ] ++ fallback_separators()
  end

  # TypeScript uses the same separators as JavaScript
  def get_separators(:typescript), do: get_separators(:javascript)

  def get_separators(:vue) do
    [
      # Vue SFC section tags
      "<script",
      "<section",
      "<table",
      "<template"
    ] ++ get_separators(:javascript)
  end

  def get_separators(:html) do
    [
      # Heading hierarchy
      "<h1",
      "<h2",
      "<h3",
      "<h4",
      "<h5",
      "<h6",
      # Content elements
      "<p",
      "<ul",
      "<ol",
      "<li",
      # Semantic sections
      "<article",
      "<section",
      "<table"
    ] ++ fallback_separators()
  end

  # Document formats all use plaintext separators
  def get_separators(format) when format in @plaintext_formats do
    get_separators(:plain)
  end

  # Unknown formats fall back to plaintext
  def get_separators(_unknown), do: get_separators(:plain)
end
