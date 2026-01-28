# Telemetry

PortfolioIndex instruments all major operations with
[`:telemetry`](https://hex.pm/packages/telemetry) events for observability,
monitoring, and debugging.

## Event Overview

| Component | Event Prefix | Key Events |
|-----------|-------------|------------|
| Vector Store | `[:portfolio_index, :vector_store, ...]` | store, store_batch, search |
| Graph Store | `[:portfolio_index, :graph_store, ...]` | create_node, create_edge, query |
| Embedder | `[:portfolio_index, :embedder, ...]` | embed, embed_batch |
| LLM | `[:portfolio_index, :llm, ...]` | complete, stream |
| RAG | `[:portfolio_index, :rag, ...]` | step, search, rerank, correction |
| Agent Session | `[:portfolio_index, :agent_session, ...]` | start_session, execute, cancel, end_session |
| VCS | `[:portfolio_index, :vcs, ...]` | status, commit, diff, push, pull |

All span events follow the `:start | :stop | :exception` convention.

## Telemetry Logger

`PortfolioIndex.Telemetry.Logger` provides one-line setup for human-readable
telemetry output:

```elixir
# Attach all portfolio_index telemetry handlers
PortfolioIndex.Telemetry.Logger.attach()

# With options
PortfolioIndex.Telemetry.Logger.attach(
  format: :json,                        # :text (default) or :json
  components: [:llm, :embedder, :rag]   # filter by component
)
```

Output example (text format):

```
[portfolio_index] llm.complete model=gpt-5-nano tokens=150/42 duration=1.2s
[portfolio_index] embedder.embed_batch count=50 duration=850ms
[portfolio_index] rag.step step=rewrite duration=120ms
```

## Telemetry Modules

### LLM Telemetry

`PortfolioIndex.Telemetry.LLM` wraps LLM calls with detailed metadata:

```elixir
alias PortfolioIndex.Telemetry.LLM

LLM.span(metadata, fn ->
  # LLM call here
  {:ok, result}
end)
```

Utilities:
- `LLM.estimate_tokens/1` -- estimate token count from text
- `LLM.extract_usage/1` -- parse provider-specific usage data

### Embedder Telemetry

`PortfolioIndex.Telemetry.Embedder`:

```elixir
alias PortfolioIndex.Telemetry.Embedder

Embedder.span(metadata, fn -> embed(text) end)
Embedder.batch_span(metadata, fn -> embed_batch(texts) end)
```

### RAG Telemetry

`PortfolioIndex.Telemetry.RAG`:

```elixir
alias PortfolioIndex.Telemetry.RAG

RAG.step_span(:rewrite, metadata, fn -> rewrite(query) end)
RAG.search_span(:vector, metadata, fn -> search(query) end)
RAG.rerank_span(metadata, fn -> rerank(results) end)
RAG.correction_event(metadata, correction_details)
```

### Vector Store Telemetry

`PortfolioIndex.Telemetry.VectorStore`:

```elixir
alias PortfolioIndex.Telemetry.VectorStore

VectorStore.search_span(metadata, fn -> search(query) end)
VectorStore.insert_span(metadata, fn -> insert(item) end)
VectorStore.batch_insert_span(metadata, fn -> insert_batch(items) end)
```

## Lineage Context

`PortfolioIndex.Telemetry.Context` propagates tracing context through telemetry:

```elixir
alias PortfolioIndex.Telemetry.Context

context = %{
  trace_id: "abc-123",
  work_id: "work-456",
  plan_id: "plan-789",
  step_id: "step-1"
}

# Merge context into telemetry metadata
metadata = Context.merge(context, %{model: "gpt-5-nano"})
```

Standard context keys:
- `trace_id` -- distributed trace identifier
- `work_id` -- work unit identifier
- `plan_id` -- execution plan identifier
- `step_id` -- pipeline step identifier

All LLM adapters propagate lineage context from `opts` to telemetry metadata.

## Attaching Custom Handlers

```elixir
:telemetry.attach(
  "my-handler",
  [:portfolio_index, :llm, :complete, :stop],
  fn _event, measurements, metadata, _config ->
    Logger.info("LLM #{metadata.model}: #{measurements.duration}ns, " <>
      "#{metadata.input_tokens} in / #{metadata.output_tokens} out")
  end,
  nil
)
```

## Application Setup

`PortfolioIndex.Telemetry` configures default telemetry polling and metrics:

```elixir
# In your application supervision tree
children = [
  PortfolioIndex.Telemetry
]
```

This starts a `telemetry_poller` for periodic measurements and defines
standard metrics for dashboards.
