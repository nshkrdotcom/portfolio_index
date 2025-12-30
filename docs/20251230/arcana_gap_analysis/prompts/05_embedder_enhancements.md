# Prompt 5: Embedder Enhancements Implementation

## Target Repository
- **portfolio_index**: `/home/home/p/g/n/portfolio_index`

## Required Reading Before Implementation

### Reference Implementation (Arcana)
Read these files to understand the reference implementation:
```
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/embedder.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/embedder/local.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/embedder/openai.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/config.ex
```

### Existing Portfolio Code
Read these files to understand existing patterns:
```
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/embedder.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/voyage.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/instructor.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/ollama.ex
```

### Gap Analysis Documentation
```
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/02_embedder_system.md
```

---

## Implementation Tasks

### Task 1: OpenAI Embedder Adapter

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/openai.ex`:

```elixir
defmodule PortfolioIndex.Adapters.Embedder.OpenAI do
  @moduledoc """
  OpenAI embeddings adapter using the text-embedding API.

  ## Configuration

  Set the API key via environment variable or config:

      config :portfolio_index, PortfolioIndex.Adapters.Embedder.OpenAI,
        api_key: System.get_env("OPENAI_API_KEY"),
        model: "text-embedding-3-small"

  ## Models

  - `text-embedding-3-small` - 1536 dimensions (default)
  - `text-embedding-3-large` - 3072 dimensions
  - `text-embedding-ada-002` - 1536 dimensions (legacy)
  """

  @behaviour PortfolioCore.Ports.Embedder

  @default_model "text-embedding-3-small"
  @api_url "https://api.openai.com/v1/embeddings"

  @model_dimensions %{
    "text-embedding-3-small" => 1536,
    "text-embedding-3-large" => 3072,
    "text-embedding-ada-002" => 1536
  }

  @impl true
  def embed(text, opts \\ [])

  @impl true
  def embed_batch(texts, opts \\ [])

  @impl true
  def dimensions(opts \\ [])

  @impl true
  def supported_models do
    Map.keys(@model_dimensions)
  end

  @doc "Get dimension for a specific model"
  @spec model_dimensions(String.t()) :: pos_integer() | nil
  def model_dimensions(model)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/embedder/openai_test.exs`

---

### Task 2: Local Bumblebee Embedder Adapter

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/bumblebee.ex`:

```elixir
defmodule PortfolioIndex.Adapters.Embedder.Bumblebee do
  @moduledoc """
  Local embeddings using Bumblebee and Nx.Serving.
  Runs HuggingFace models locally without API calls.

  ## Configuration

      config :portfolio_index, PortfolioIndex.Adapters.Embedder.Bumblebee,
        model: "BAAI/bge-small-en-v1.5",
        serving_name: PortfolioIndex.EmbeddingServing

  ## Models

  - `BAAI/bge-small-en-v1.5` - 384 dimensions (default, fast)
  - `BAAI/bge-base-en-v1.5` - 768 dimensions
  - `BAAI/bge-large-en-v1.5` - 1024 dimensions
  - `sentence-transformers/all-MiniLM-L6-v2` - 384 dimensions

  ## Setup

  Add to your supervision tree:

      children = [
        {PortfolioIndex.Adapters.Embedder.Bumblebee, name: PortfolioIndex.EmbeddingServing}
      ]
  """

  @behaviour PortfolioCore.Ports.Embedder

  use GenServer

  @default_model "BAAI/bge-small-en-v1.5"

  @model_dimensions %{
    "BAAI/bge-small-en-v1.5" => 384,
    "BAAI/bge-base-en-v1.5" => 768,
    "BAAI/bge-large-en-v1.5" => 1024,
    "sentence-transformers/all-MiniLM-L6-v2" => 384
  }

  # GenServer callbacks for Nx.Serving management
  def start_link(opts)
  def init(opts)
  def child_spec(opts)

  @impl PortfolioCore.Ports.Embedder
  def embed(text, opts \\ [])

  @impl PortfolioCore.Ports.Embedder
  def embed_batch(texts, opts \\ [])

  @impl PortfolioCore.Ports.Embedder
  def dimensions(opts \\ [])

  @impl PortfolioCore.Ports.Embedder
  def supported_models do
    Map.keys(@model_dimensions)
  end

  @doc "Check if the serving is ready"
  @spec ready?(atom()) :: boolean()
  def ready?(serving_name \\ __MODULE__)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/embedder/bumblebee_test.exs`

---

### Task 3: Custom Function Embedder

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/function.ex`:

```elixir
defmodule PortfolioIndex.Adapters.Embedder.Function do
  @moduledoc """
  Wrapper adapter that delegates to a custom function.
  Useful for quick integration of custom embedding logic.

  ## Usage

      # With a function
      embedder = PortfolioIndex.Adapters.Embedder.Function.new(
        fn text -> MyEmbedder.embed(text) end,
        dimensions: 768
      )

      # Use in pipeline
      PortfolioIndex.RAG.search(query, embedder: embedder)
  """

  @behaviour PortfolioCore.Ports.Embedder

  @type t :: %__MODULE__{
    embed_fn: (String.t() -> {:ok, [float()]} | {:error, term()}),
    batch_fn: ([String.t()] -> {:ok, [[float()]]} | {:error, term()}) | nil,
    dimensions: pos_integer()
  }

  defstruct [:embed_fn, :batch_fn, :dimensions]

  @doc "Create a new function embedder"
  @spec new((String.t() -> {:ok, [float()]} | {:error, term()}), keyword()) :: t()
  def new(embed_fn, opts \\ [])

  @impl true
  def embed(%__MODULE__{} = embedder, text, opts \\ [])

  @impl true
  def embed_batch(%__MODULE__{} = embedder, texts, opts \\ [])

  @impl true
  def dimensions(%__MODULE__{} = embedder, _opts \\ [])

  @impl true
  def supported_models, do: ["custom"]
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/embedder/function_test.exs`

---

### Task 4: Model Dimension Registry

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/embedder/registry.ex`:

```elixir
defmodule PortfolioIndex.Embedder.Registry do
  @moduledoc """
  Registry of known embedding models and their dimensions.
  Used for auto-detection and validation.
  """

  @models %{
    # OpenAI
    "text-embedding-3-small" => %{provider: :openai, dimensions: 1536},
    "text-embedding-3-large" => %{provider: :openai, dimensions: 3072},
    "text-embedding-ada-002" => %{provider: :openai, dimensions: 1536},

    # Voyage
    "voyage-3" => %{provider: :voyage, dimensions: 1024},
    "voyage-3-lite" => %{provider: :voyage, dimensions: 512},
    "voyage-code-3" => %{provider: :voyage, dimensions: 1024},

    # Bumblebee/HuggingFace
    "BAAI/bge-small-en-v1.5" => %{provider: :bumblebee, dimensions: 384},
    "BAAI/bge-base-en-v1.5" => %{provider: :bumblebee, dimensions: 768},
    "BAAI/bge-large-en-v1.5" => %{provider: :bumblebee, dimensions: 1024},
    "sentence-transformers/all-MiniLM-L6-v2" => %{provider: :bumblebee, dimensions: 384},

    # Ollama
    "nomic-embed-text" => %{provider: :ollama, dimensions: 768},
    "mxbai-embed-large" => %{provider: :ollama, dimensions: 1024}
  }

  @doc "Get model info by name"
  @spec get(String.t()) :: map() | nil
  def get(model_name)

  @doc "Get dimensions for a model"
  @spec dimensions(String.t()) :: pos_integer() | nil
  def dimensions(model_name)

  @doc "Get provider for a model"
  @spec provider(String.t()) :: atom() | nil
  def provider(model_name)

  @doc "List all known models"
  @spec list() :: [String.t()]
  def list()

  @doc "List models by provider"
  @spec list_by_provider(atom()) :: [String.t()]
  def list_by_provider(provider)

  @doc "Register a custom model"
  @spec register(String.t(), atom(), pos_integer()) :: :ok
  def register(model_name, provider, dimensions)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/embedder/registry_test.exs`

---

### Task 5: Unified Embedder Configuration

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/embedder/config.ex`:

```elixir
defmodule PortfolioIndex.Embedder.Config do
  @moduledoc """
  Unified configuration for embedder selection and initialization.
  Supports shorthand syntax and automatic adapter resolution.

  ## Configuration Examples

      # Shorthand - provider atom
      config :portfolio_index, :embedder, :openai

      # Shorthand with model
      config :portfolio_index, :embedder, {:openai, model: "text-embedding-3-large"}

      # Full module specification
      config :portfolio_index, :embedder, PortfolioIndex.Adapters.Embedder.OpenAI

      # Custom function
      config :portfolio_index, :embedder, fn text -> MyEmbed.embed(text) end
  """

  alias PortfolioIndex.Adapters.Embedder

  @type embedder_config ::
    atom()
    | {atom(), keyword()}
    | module()
    | (String.t() -> {:ok, [float()]} | {:error, term()})

  @provider_modules %{
    openai: Embedder.OpenAI,
    voyage: Embedder.Voyage,
    bumblebee: Embedder.Bumblebee,
    ollama: Embedder.Ollama,
    instructor: Embedder.Instructor
  }

  @doc "Resolve embedder config to a module and options"
  @spec resolve(embedder_config()) :: {:ok, {module(), keyword()}} | {:error, term()}
  def resolve(config)

  @doc "Get the current embedder from application config"
  @spec current() :: {module(), keyword()}
  def current()

  @doc "Get dimensions for current embedder"
  @spec current_dimensions() :: pos_integer()
  def current_dimensions()

  @doc "Validate embedder configuration"
  @spec validate(embedder_config()) :: :ok | {:error, term()}
  def validate(config)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/embedder/config_test.exs`

---

### Task 6: Auto Dimension Detection

Update the existing embedder adapters to support dimension auto-detection:

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/embedder/dimension_detector.ex`:

```elixir
defmodule PortfolioIndex.Embedder.DimensionDetector do
  @moduledoc """
  Utilities for detecting embedding dimensions from various sources.
  """

  alias PortfolioIndex.Embedder.Registry

  @doc """
  Detect dimensions for an embedder configuration.

  Tries in order:
  1. Explicit :dimensions option
  2. Model registry lookup
  3. Probe embedding (embed empty string and measure)
  """
  @spec detect(module() | map(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def detect(embedder, opts \\ [])

  @doc """
  Probe an embedder by generating an embedding and measuring dimensions.
  This is a fallback when dimensions aren't known statically.
  """
  @spec probe(module(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  def probe(embedder, opts \\ [])

  @doc """
  Validate that an embedding has the expected dimensions.
  """
  @spec validate_dimensions([float()], pos_integer()) :: :ok | {:error, term()}
  def validate_dimensions(embedding, expected_dimensions)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/embedder/dimension_detector_test.exs`

---

## TDD Requirements

For each task:

1. **Write tests FIRST** following existing test patterns in the repo
2. Tests must cover:
   - Happy path embedding
   - Batch embedding
   - Error handling (API errors, invalid input)
   - Dimension detection and validation
   - Configuration resolution
   - Mock external APIs in tests
3. Run tests continuously: `mix test path/to/test_file.exs`

## Quality Gates

Before considering this prompt complete:

```bash
cd /home/home/p/g/n/portfolio_index
mix test
mix credo --strict
mix dialyzer
```

All must pass with zero warnings and zero errors.

## Documentation Updates

### portfolio_index
Update `/home/home/p/g/n/portfolio_index/CHANGELOG.md` - add entry to version 0.3.1:
```markdown
### Added
- `PortfolioIndex.Adapters.Embedder.OpenAI` - OpenAI text-embedding API adapter
- `PortfolioIndex.Adapters.Embedder.Bumblebee` - Local Bumblebee/Nx.Serving embeddings
- `PortfolioIndex.Adapters.Embedder.Function` - Custom function wrapper adapter
- `PortfolioIndex.Embedder.Registry` - Model dimension registry
- `PortfolioIndex.Embedder.Config` - Unified embedder configuration
- `PortfolioIndex.Embedder.DimensionDetector` - Automatic dimension detection
```

## Verification Checklist

- [ ] All new files created in correct locations
- [ ] All tests pass
- [ ] No credo warnings
- [ ] No dialyzer errors
- [ ] Changelog updated
- [ ] Module documentation complete with @moduledoc and @doc
- [ ] Type specifications complete with @type and @spec
- [ ] External API calls properly mocked in tests

