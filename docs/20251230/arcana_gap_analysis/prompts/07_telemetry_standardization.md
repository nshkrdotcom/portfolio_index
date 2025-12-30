# Prompt 7: Telemetry Standardization Implementation

## Target Repositories
- **portfolio_core**: `/home/home/p/g/n/portfolio_core`
- **portfolio_index**: `/home/home/p/g/n/portfolio_index`

## Required Reading Before Implementation

### Reference Implementation (Arcana)
Read these files to understand the reference implementation:
```
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/telemetry.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/telemetry/logger.ex
```

### Existing Portfolio Code
Read these files to understand existing patterns:
```
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/voyage.ex (search for :telemetry)
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/vector_store/pgvector.ex (search for :telemetry)
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/evaluation.ex (search for :telemetry)
```

### Gap Analysis Documentation
```
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/06_telemetry.md
```

---

## Implementation Tasks

### Task 1: Telemetry Event Definitions (portfolio_core)

Create `/home/home/p/g/n/portfolio_core/lib/portfolio_core/telemetry.ex`:

```elixir
defmodule PortfolioCore.Telemetry do
  @moduledoc """
  Telemetry event definitions and utilities for the Portfolio libraries.

  ## Event Naming Convention

  All events follow the pattern: `[:portfolio, :component, :operation]`

  ## Standard Events

  ### Embedding Events
  - `[:portfolio, :embedder, :embed, :start]`
  - `[:portfolio, :embedder, :embed, :stop]`
  - `[:portfolio, :embedder, :embed, :exception]`

  ### Vector Store Events
  - `[:portfolio, :vector_store, :search, :start]`
  - `[:portfolio, :vector_store, :search, :stop]`
  - `[:portfolio, :vector_store, :insert, :start]`
  - `[:portfolio, :vector_store, :insert, :stop]`

  ### LLM Events
  - `[:portfolio, :llm, :complete, :start]`
  - `[:portfolio, :llm, :complete, :stop]`
  - `[:portfolio, :llm, :complete, :exception]`

  ### RAG Pipeline Events
  - `[:portfolio, :rag, :rewrite, :start/:stop/:exception]`
  - `[:portfolio, :rag, :expand, :start/:stop/:exception]`
  - `[:portfolio, :rag, :decompose, :start/:stop/:exception]`
  - `[:portfolio, :rag, :select, :start/:stop/:exception]`
  - `[:portfolio, :rag, :search, :start/:stop/:exception]`
  - `[:portfolio, :rag, :rerank, :start/:stop/:exception]`
  - `[:portfolio, :rag, :answer, :start/:stop/:exception]`

  ### Evaluation Events
  - `[:portfolio, :evaluation, :run, :start/:stop/:exception]`
  - `[:portfolio, :evaluation, :test_case, :start/:stop]`
  """

  @type event_name :: [atom()]
  @type measurements :: map()
  @type metadata :: map()

  @doc """
  Execute a function wrapped in telemetry span.
  Emits start, stop, and exception events automatically.
  """
  @spec span(event_name(), metadata(), (-> result)) :: result when result: any()
  def span(event, metadata, fun)

  @doc """
  Emit a telemetry event.
  """
  @spec emit(event_name(), measurements(), metadata()) :: :ok
  def emit(event, measurements, metadata)

  @doc """
  Get all defined event names for documentation/attachment.
  """
  @spec events() :: [event_name()]
  def events()

  @doc """
  Get events for a specific component.
  """
  @spec events_for(atom()) :: [event_name()]
  def events_for(component)
end
```

**Test file**: `/home/home/p/g/n/portfolio_core/test/telemetry_test.exs`

---

### Task 2: Telemetry Logger (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/telemetry/logger.ex`:

```elixir
defmodule PortfolioIndex.Telemetry.Logger do
  @moduledoc """
  Human-readable telemetry logger for Portfolio events.
  Provides one-line setup for development and debugging.

  ## Usage

      # In application.ex or iex
      PortfolioIndex.Telemetry.Logger.attach()

      # With options
      PortfolioIndex.Telemetry.Logger.attach(
        level: :info,
        events: [:embedder, :vector_store],
        format: :json
      )

      # Detach when done
      PortfolioIndex.Telemetry.Logger.detach()
  """

  require Logger

  @type log_level :: :debug | :info | :warning | :error
  @type format :: :text | :json

  @type opts :: [
    level: log_level(),
    events: [atom()] | :all,
    format: format(),
    handler_id: atom()
  ]

  @default_handler_id :portfolio_telemetry_logger

  @doc """
  Attach the telemetry logger to all Portfolio events.
  """
  @spec attach(opts()) :: :ok | {:error, term()}
  def attach(opts \\ [])

  @doc """
  Detach the telemetry logger.
  """
  @spec detach(atom()) :: :ok | {:error, term()}
  def detach(handler_id \\ @default_handler_id)

  @doc """
  Check if logger is attached.
  """
  @spec attached?(atom()) :: boolean()
  def attached?(handler_id \\ @default_handler_id)

  @doc """
  Format an event for logging.
  """
  @spec format_event([atom()], map(), map(), format()) :: String.t()
  def format_event(event, measurements, metadata, format)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/telemetry/logger_test.exs`

---

### Task 3: LLM Telemetry Enrichment (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/telemetry/llm.ex`:

```elixir
defmodule PortfolioIndex.Telemetry.LLM do
  @moduledoc """
  LLM-specific telemetry utilities with enriched metadata.
  """

  @doc """
  Wrap an LLM call with telemetry, including token tracking.

  Metadata includes:
  - `:model` - Model identifier
  - `:prompt_length` - Character count of prompt
  - `:prompt_tokens` - Estimated token count (if available)
  - `:response_length` - Character count of response
  - `:response_tokens` - Estimated token count (if available)
  - `:provider` - LLM provider (openai, anthropic, etc.)
  """
  @spec span(keyword(), (-> result)) :: result when result: any()
  def span(metadata, fun)

  @doc """
  Estimate token count for text.
  Uses simple heuristic: ~4 chars per token for English.
  """
  @spec estimate_tokens(String.t()) :: non_neg_integer()
  def estimate_tokens(text)

  @doc """
  Extract token usage from LLM response if available.
  """
  @spec extract_usage(map()) :: map()
  def extract_usage(response)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/telemetry/llm_test.exs`

---

### Task 4: Embedder Telemetry (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/telemetry/embedder.ex`:

```elixir
defmodule PortfolioIndex.Telemetry.Embedder do
  @moduledoc """
  Embedder-specific telemetry utilities.
  """

  @doc """
  Wrap an embedding call with telemetry.

  Metadata includes:
  - `:model` - Embedding model identifier
  - `:dimensions` - Embedding vector dimensions
  - `:text_length` - Character count of input
  - `:batch_size` - Number of texts (for batch operations)
  - `:provider` - Embedder provider
  """
  @spec span(keyword(), (-> result)) :: result when result: any()
  def span(metadata, fun)

  @doc """
  Wrap a batch embedding call with telemetry.
  """
  @spec batch_span(keyword(), (-> result)) :: result when result: any()
  def batch_span(metadata, fun)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/telemetry/embedder_test.exs`

---

### Task 5: RAG Pipeline Telemetry (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/telemetry/rag.ex`:

```elixir
defmodule PortfolioIndex.Telemetry.RAG do
  @moduledoc """
  RAG pipeline telemetry for tracking each step.
  """

  alias PortfolioIndex.RAG.Pipeline.Context

  @pipeline_steps [:rewrite, :expand, :decompose, :select, :search, :rerank, :answer]

  @doc """
  Wrap a pipeline step with telemetry.

  Metadata includes:
  - `:step` - Pipeline step name
  - `:question` - Original question
  - `:context_state` - Summary of context state
  """
  @spec step_span(atom(), Context.t(), (Context.t() -> Context.t())) :: Context.t()
  def step_span(step, ctx, fun)

  @doc """
  Emit search-specific telemetry.

  Additional metadata:
  - `:result_count` - Number of results
  - `:collections` - Collections searched
  - `:mode` - Search mode (semantic, fulltext, hybrid)
  """
  @spec search_span(Context.t(), keyword(), (-> result)) :: result when result: any()
  def search_span(ctx, opts, fun)

  @doc """
  Emit rerank-specific telemetry.

  Additional metadata:
  - `:input_count` - Chunks before reranking
  - `:output_count` - Chunks after reranking
  - `:threshold` - Score threshold used
  """
  @spec rerank_span(Context.t(), keyword(), (-> result)) :: result when result: any()
  def rerank_span(ctx, opts, fun)

  @doc """
  Emit self-correction telemetry.

  Additional metadata:
  - `:correction_count` - Number of corrections
  - `:reason` - Reason for correction
  """
  @spec correction_event(Context.t(), String.t()) :: :ok
  def correction_event(ctx, reason)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/telemetry/rag_test.exs`

---

### Task 6: Vector Store Telemetry (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/telemetry/vector_store.ex`:

```elixir
defmodule PortfolioIndex.Telemetry.VectorStore do
  @moduledoc """
  Vector store telemetry utilities.
  """

  @doc """
  Wrap a search operation with telemetry.

  Metadata includes:
  - `:backend` - Vector store backend
  - `:collection` - Collection name (if applicable)
  - `:limit` - Requested result limit
  - `:result_count` - Actual results returned
  - `:mode` - Search mode (semantic, hybrid)
  """
  @spec search_span(keyword(), (-> result)) :: result when result: any()
  def search_span(metadata, fun)

  @doc """
  Wrap an insert operation with telemetry.
  """
  @spec insert_span(keyword(), (-> result)) :: result when result: any()
  def insert_span(metadata, fun)

  @doc """
  Wrap a batch insert operation with telemetry.
  """
  @spec batch_insert_span(keyword(), (-> result)) :: result when result: any()
  def batch_insert_span(metadata, fun)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/telemetry/vector_store_test.exs`

---

### Task 7: Integrate Telemetry into Existing Adapters

Update existing adapter files to use the new telemetry utilities. This involves modifying:

1. `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/*.ex`
   - Wrap `embed/2` and `embed_batch/2` with `Telemetry.Embedder.span/2`

2. `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/vector_store/*.ex`
   - Wrap `search/3` with `Telemetry.VectorStore.search_span/2`
   - Wrap `insert/4` with `Telemetry.VectorStore.insert_span/2`

3. `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/llm/*.ex`
   - Wrap `complete/2` with `Telemetry.LLM.span/2`

4. `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/query_processor.ex` (from Prompt 1)
   - Wrap each step with `Telemetry.RAG.step_span/3`

---

## TDD Requirements

For each task:

1. **Write tests FIRST** following existing test patterns in the repos
2. Tests must cover:
   - Event emission with correct names
   - Metadata correctness
   - Exception handling in spans
   - Logger output format
   - Handler attachment/detachment
3. Run tests continuously: `mix test path/to/test_file.exs`

## Quality Gates

Before considering this prompt complete:

```bash
# In portfolio_core
cd /home/home/p/g/n/portfolio_core
mix test
mix credo --strict
mix dialyzer

# In portfolio_index
cd /home/home/p/g/n/portfolio_index
mix test
mix credo --strict
mix dialyzer
```

All must pass with zero warnings and zero errors.

## Documentation Updates

### portfolio_core
Update `/home/home/p/g/n/portfolio_core/CHANGELOG.md` - add entry to version 0.3.1:
```markdown
### Added
- `PortfolioCore.Telemetry` - Telemetry event definitions and span utilities
```

### portfolio_index
Update `/home/home/p/g/n/portfolio_index/CHANGELOG.md` - add entry to version 0.3.1:
```markdown
### Added
- `PortfolioIndex.Telemetry.Logger` - Human-readable telemetry logger with one-line attach
- `PortfolioIndex.Telemetry.LLM` - LLM-specific telemetry with token tracking
- `PortfolioIndex.Telemetry.Embedder` - Embedder telemetry utilities
- `PortfolioIndex.Telemetry.RAG` - RAG pipeline step telemetry
- `PortfolioIndex.Telemetry.VectorStore` - Vector store operation telemetry

### Changed
- All adapters now emit standardized telemetry events
```

## Verification Checklist

- [ ] All new files created in correct locations
- [ ] All tests pass in both repos
- [ ] No credo warnings
- [ ] No dialyzer errors
- [ ] Changelogs updated for both repos
- [ ] Module documentation complete
- [ ] Type specifications complete
- [ ] Existing adapters updated with telemetry
- [ ] Logger produces readable output

