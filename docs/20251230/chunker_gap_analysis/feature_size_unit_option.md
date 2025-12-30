# Feature: `size_unit` Configuration Option

> **Port Updated**: The `size_unit` type has been added to `PortfolioCore.Ports.Chunker`
> as of v0.3.1. The port now defines:
> ```elixir
> @type size_unit :: :characters | :tokens
> @type chunk_config :: %{
>   chunk_size: pos_integer(),
>   chunk_overlap: non_neg_integer(),
>   size_unit: size_unit() | nil,
>   separators: [String.t()] | nil
> }
> ```
> This document describes the PortfolioIndex adapter implementation of this port feature.

## Overview

Add a `:size_unit` option to the chunker Config that automatically configures token-based sizing without requiring users to provide a custom `get_chunk_size` function.

## Source Reference

**Arcana implementation** (`arcana/lib/arcana/chunker.ex:38-50`):
```elixir
def chunk(text, opts) do
  chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
  chunk_overlap = Keyword.get(opts, :chunk_overlap, @default_chunk_overlap)
  format = Keyword.get(opts, :format, @default_format)
  size_unit = Keyword.get(opts, :size_unit, @default_size_unit)

  # Convert token-based sizes to character-based for text_chunker
  {effective_chunk_size, effective_overlap} =
    case size_unit do
      :tokens -> {chunk_size * 4, chunk_overlap * 4}
      :characters -> {chunk_size, chunk_overlap}
    end
  # ...
end
```

## Current PortfolioIndex Behavior

Users must manually provide a sizing function:
```elixir
config = %{
  chunk_size: 512,
  chunk_overlap: 50,
  get_chunk_size: fn text -> div(String.length(text), 4) end
}
```

## Proposed Enhancement

### Option 1: Add `size_unit` to Config (Recommended)

Extend `Config` schema to support `:size_unit`:

```elixir
# In config.ex
@schema [
  # ... existing options ...
  size_unit: [
    type: {:in, [:characters, :tokens]},
    default: :characters,
    doc: "Unit for chunk_size/chunk_overlap: :characters or :tokens"
  ]
]
```

When `:size_unit` is `:tokens`:
- If no `get_chunk_size` provided, auto-set to `Tokens.sizer()`
- Keep `chunk_size` and `chunk_overlap` as-is (they represent tokens)

### Option 2: Arcana-Style Conversion

Convert token counts to character counts upfront:
```elixir
{effective_size, effective_overlap} =
  case config.size_unit do
    :tokens -> {config.chunk_size * 4, config.chunk_overlap * 4}
    :characters -> {config.chunk_size, config.chunk_overlap}
  end
```

**Recommendation**: Option 1 is better because it uses the proper `get_chunk_size` mechanism rather than a multiplication hack.

## Implementation

### Modified `lib/portfolio_index/adapters/chunker/config.ex`

```elixir
defmodule PortfolioIndex.Adapters.Chunker.Config do
  @moduledoc """
  Configuration validation for chunker adapters using NimbleOptions.
  ...
  """

  alias PortfolioIndex.Adapters.Chunker.{Separators, Tokens}

  @default_chunk_size 1000
  @default_chunk_overlap 200
  @default_size_unit :characters

  @supported_formats Separators.supported_formats()

  @schema [
    chunk_size: [
      type: :pos_integer,
      default: @default_chunk_size,
      doc: "Target size for each chunk (in units specified by size_unit)."
    ],
    chunk_overlap: [
      type: :non_neg_integer,
      default: @default_chunk_overlap,
      doc: "Overlap between adjacent chunks (in units specified by size_unit)."
    ],
    size_unit: [
      type: {:in, [:characters, :tokens]},
      default: @default_size_unit,
      doc: "Unit for chunk_size/chunk_overlap: :characters or :tokens"
    ],
    get_chunk_size: [
      type: {:or, [nil, {:fun, 1}]},
      default: nil,
      doc: "Function to measure chunk size. Auto-set based on size_unit if nil."
    ],
    format: [
      type: {:in, @supported_formats},
      default: :plain,
      doc: "Content format hint for separator selection."
    ],
    separators: [
      type: {:or, [nil, {:list, :string}]},
      default: nil,
      doc: "Custom separator list. Overrides format-based separators if provided."
    ]
  ]

  @type t :: %__MODULE__{
          chunk_size: pos_integer(),
          chunk_overlap: non_neg_integer(),
          size_unit: :characters | :tokens,
          get_chunk_size: (String.t() -> non_neg_integer()),
          format: atom(),
          separators: [String.t()] | nil
        }

  defstruct [
    :chunk_size,
    :chunk_overlap,
    :size_unit,
    :get_chunk_size,
    :format,
    :separators
  ]

  # ... existing schema/0, default_chunk_size/0, default_chunk_overlap/0 ...

  @doc """
  Returns the default size unit.
  """
  @spec default_size_unit() :: :characters | :tokens
  def default_size_unit, do: @default_size_unit

  @spec validate(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def validate(opts) when is_map(opts) do
    opts
    |> Map.to_list()
    |> validate_from_keyword()
  end

  def validate(opts) when is_list(opts) do
    validate_from_keyword(opts)
  end

  @spec validate_from_keyword(keyword()) :: {:ok, t()} | {:error, String.t()}
  def validate_from_keyword(opts) do
    case NimbleOptions.validate(opts, @schema) do
      {:ok, validated} ->
        config = struct(__MODULE__, validated)
        {:ok, resolve_get_chunk_size(config)}

      {:error, %NimbleOptions.ValidationError{message: message}} ->
        {:error, message}
    end
  end

  # Auto-set get_chunk_size based on size_unit if not provided
  defp resolve_get_chunk_size(%{get_chunk_size: nil, size_unit: :tokens} = config) do
    %{config | get_chunk_size: Tokens.sizer()}
  end

  defp resolve_get_chunk_size(%{get_chunk_size: nil, size_unit: :characters} = config) do
    %{config | get_chunk_size: &String.length/1}
  end

  defp resolve_get_chunk_size(config), do: config

  # ... rest of existing functions ...
end
```

## Test Cases

```elixir
describe "size_unit option" do
  test "defaults to :characters" do
    {:ok, config} = Config.validate(%{})
    assert config.size_unit == :characters
  end

  test ":characters uses String.length/1 by default" do
    {:ok, config} = Config.validate(%{size_unit: :characters})
    assert config.get_chunk_size.("test") == 4
  end

  test ":tokens uses Tokens.sizer() by default" do
    {:ok, config} = Config.validate(%{size_unit: :tokens})
    # 8 chars / 4 = 2 tokens
    assert config.get_chunk_size.("12345678") == 2
  end

  test "explicit get_chunk_size overrides size_unit default" do
    custom_fn = fn _ -> 42 end
    {:ok, config} = Config.validate(%{size_unit: :tokens, get_chunk_size: custom_fn})
    assert config.get_chunk_size.("anything") == 42
  end

  test "rejects invalid size_unit" do
    {:error, message} = Config.validate(%{size_unit: :words})
    assert message =~ "invalid value"
  end
end
```

## Usage Examples

### Simple Token-Based Chunking
```elixir
alias PortfolioIndex.Adapters.Chunker.{Recursive, Config}

# NEW: Just specify size_unit: :tokens
config = Config.validate!(%{
  chunk_size: 512,
  chunk_overlap: 50,
  size_unit: :tokens,
  format: :markdown
})

{:ok, chunks} = Recursive.chunk(document, :markdown, config)
```

### Explicit Character Sizing (Default Behavior)
```elixir
config = Config.validate!(%{
  chunk_size: 2000,
  chunk_overlap: 200,
  size_unit: :characters  # explicit, same as default
})
```

### Custom Tokenizer (Override size_unit)
```elixir
config = Config.validate!(%{
  chunk_size: 512,
  size_unit: :tokens,
  get_chunk_size: &MyApp.Tokenizer.count/1  # overrides default
})
```

## Migration Notes

- Existing code using `get_chunk_size` explicitly will continue to work
- Default behavior is unchanged (`:characters` with `String.length/1`)
- New `:size_unit` option is purely additive
