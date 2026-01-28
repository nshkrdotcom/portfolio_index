# Embedders

PortfolioIndex supports multiple embedding providers for converting text into
vector representations used by vector stores and RAG pipelines.

## Available Embedders

| Adapter | Provider | Default Model | Dimensions |
|---------|----------|---------------|------------|
| `Gemini` | Google | text-embedding-004 | 768 |
| `OpenAI` | OpenAI | text-embedding-3-small | 1536 |
| `Ollama` | Ollama (local) | nomic-embed-text | 768 |
| `Bumblebee` | HuggingFace (local) | BGE / MiniLM | varies |
| `Function` | Custom | user-defined | varies |

## Gemini Embedder

```elixir
alias PortfolioIndex.Adapters.Embedder.Gemini

# Single embedding
{:ok, %{vector: vec}} = Gemini.embed("Hello, world!")

# Batch embedding
{:ok, results} = Gemini.embed_batch(["Hello", "World"])
```

Requires `GEMINI_API_KEY` environment variable.

## OpenAI Embedder

```elixir
alias PortfolioIndex.Adapters.Embedder.OpenAI

{:ok, %{vector: vec}} = OpenAI.embed("Hello, world!", model: "text-embedding-3-small")

# Batch
{:ok, results} = OpenAI.embed_batch(["Hello", "World"])
```

Supported models:
- `text-embedding-3-small` (1536 dims, default)
- `text-embedding-3-large` (3072 dims)
- `text-embedding-ada-002` (1536 dims, legacy)

Requires `OPENAI_API_KEY` environment variable.

## Ollama Embedder

```elixir
alias PortfolioIndex.Adapters.Embedder.Ollama

{:ok, %{vector: vec}} = Ollama.embed("Hello, world!")
{:ok, results} = Ollama.embed_batch(["Hello", "World"])
```

Supported models:
- `nomic-embed-text` (768 dims, default)
- `mxbai-embed-large` (1024 dims)

Setup:

```bash
ollama pull nomic-embed-text
```

Or use the setup script:

```bash
mix run examples/ollama_setup.exs
```

## Bumblebee Embedder

`PortfolioIndex.Adapters.Embedder.Bumblebee` runs embeddings locally using
HuggingFace models via Nx/EXLA:

```elixir
alias PortfolioIndex.Adapters.Embedder.Bumblebee

# Add to your supervision tree
children = [
  {Bumblebee, model: "BAAI/bge-small-en-v1.5"}
]

# Then use it
{:ok, %{vector: vec}} = Bumblebee.embed("Hello, world!")
```

No API keys required -- fully local inference.

## Function Embedder

`PortfolioIndex.Adapters.Embedder.Function` wraps any function as an embedder:

```elixir
alias PortfolioIndex.Adapters.Embedder.Function

embedder = Function.new(fn text ->
  # Your custom embedding logic
  {:ok, %{vector: my_embed(text)}}
end)

{:ok, %{vector: vec}} = Function.embed("Hello, world!", embedder: embedder)
```

Useful for testing and custom integrations.

## Embedder Configuration

`PortfolioIndex.Embedder.Config` provides unified configuration with shorthand syntax:

```elixir
# config/config.exs
config :portfolio_index, :embedder, :openai

# Or with options
config :portfolio_index, :embedder, {PortfolioIndex.Adapters.Embedder.OpenAI, model: "text-embedding-3-large"}
```

Shorthand atoms: `:openai`, `:gemini`, `:ollama`, `:bumblebee`.

```elixir
alias PortfolioIndex.Embedder.Config

Config.current()              # Returns the configured embedder module
Config.current_dimensions()   # Returns dimensions for the current embedder
```

## Dimension Registry

`PortfolioIndex.Embedder.Registry` tracks known model dimensions:

```elixir
alias PortfolioIndex.Embedder.Registry

Registry.dimensions("text-embedding-3-small")  # => 1536
Registry.dimensions("nomic-embed-text")        # => 768
Registry.provider("text-embedding-3-small")    # => :openai

# Register a custom model
Registry.register("my-model", 512, :custom)
```

Pre-configured models include OpenAI, Voyage, Bumblebee, and Ollama families.

## Dimension Detection

`PortfolioIndex.Embedder.DimensionDetector` automatically detects embedding
dimensions using multiple strategies:

1. **Explicit** -- from configuration
2. **Registry** -- from known model dimensions
3. **Probe** -- by generating a test embedding

```elixir
alias PortfolioIndex.Embedder.DimensionDetector

{:ok, dims} = DimensionDetector.detect(embedder_module, opts)
```

## Telemetry Events

All embedders emit telemetry via `PortfolioIndex.Telemetry.Embedder`:

```elixir
[:portfolio_index, :embedder, :embed, :start | :stop | :exception]
[:portfolio_index, :embedder, :embed_batch, :start | :stop | :exception]
```

Measurements include duration, token count, and batch size.
