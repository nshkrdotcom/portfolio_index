# Telemetry System Gap Analysis

## Executive Summary

This document analyzes the telemetry instrumentation differences between Arcana's cohesive telemetry system and the portfolio libraries (PortfolioCore and PortfolioIndex). Arcana provides a unified, span-based telemetry approach with a built-in logger, while the portfolio libraries use a more fragmented, metrics-focused approach with less comprehensive event coverage.

---

## Arcana Telemetry Capabilities

### 1. Core Architecture

Arcana uses `:telemetry.span/3` consistently across all operations, automatically generating `:start`, `:stop`, and `:exception` event triplets. This provides:

- **Unified timing**: All operations are wrapped in spans with automatic duration tracking
- **Consistent metadata**: Start and stop events share metadata patterns
- **Exception handling**: Automatic exception event emission with stack traces

**Location**: `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/telemetry.ex`

### 2. Event Categories

#### 2.1 Ingest Events (`[:arcana, :ingest, :*]`)
| Event | Measurements | Metadata |
|-------|-------------|----------|
| `:start` | `%{system_time: integer}` | `%{text: String.t(), repo: module(), collection: String.t()}` |
| `:stop` | `%{duration: integer}` | `%{document: Document.t(), chunk_count: integer}` |
| `:exception` | `%{duration: integer}` | `%{kind: atom(), reason: term(), stacktrace: list()}` |

#### 2.2 Search Events (`[:arcana, :search, :*]`)
| Event | Measurements | Metadata |
|-------|-------------|----------|
| `:start` | `%{system_time: integer}` | `%{query: String.t(), repo: module(), mode: atom(), limit: integer}` |
| `:stop` | `%{duration: integer}` | `%{results: list(), result_count: integer}` |
| `:exception` | `%{duration: integer}` | `%{kind: atom(), reason: term(), stacktrace: list()}` |

#### 2.3 Ask/RAG Events (`[:arcana, :ask, :*]`)
| Event | Measurements | Metadata |
|-------|-------------|----------|
| `:start` | `%{system_time: integer}` | `%{question: String.t(), repo: module()}` |
| `:stop` | `%{duration: integer}` | `%{answer: String.t(), context_count: integer}` |
| `:exception` | `%{duration: integer}` | `%{kind: atom(), reason: term(), stacktrace: list()}` |

#### 2.4 Embed Events (`[:arcana, :embed, :*]`)
| Event | Measurements | Metadata |
|-------|-------------|----------|
| `:start` | `%{system_time: integer}` | `%{text: String.t()}` |
| `:stop` | `%{duration: integer}` | `%{dimensions: integer}` |
| `:exception` | `%{duration: integer}` | `%{kind: atom(), reason: term(), stacktrace: list()}` |

#### 2.5 LLM Events (`[:arcana, :llm, :complete, :*]`)
| Event | Measurements | Metadata |
|-------|-------------|----------|
| `:start` | `%{system_time: integer}` | `%{model: String.t(), prompt_length: integer, context_count: integer}` |
| `:stop` | `%{duration: integer}` | `%{success: boolean, response_length: integer}` or `%{success: false, error: String.t()}` |
| `:exception` | `%{duration: integer}` | `%{kind: atom(), reason: term(), stacktrace: list()}` |

#### 2.6 Agent Pipeline Events

All agent steps emit `:start`, `:stop`, and `:exception` events:

| Pipeline Step | Event Prefix | Stop Metadata |
|---------------|--------------|---------------|
| Query Rewrite | `[:arcana, :agent, :rewrite, :*]` | `%{query: String.t(), rewritten_query: String.t()}` |
| Collection Select | `[:arcana, :agent, :select, :*]` | `%{selected_count: integer, selected_collections: [String.t()]}` |
| Query Expand | `[:arcana, :agent, :expand, :*]` | `%{expanded_query: String.t()}` |
| Question Decompose | `[:arcana, :agent, :decompose, :*]` | `%{sub_question_count: integer}` |
| Vector Search | `[:arcana, :agent, :search, :*]` | `%{total_chunks: integer}` |
| Chunk Rerank | `[:arcana, :agent, :rerank, :*]` | `%{kept: integer, original: integer}` |
| Answer Generate | `[:arcana, :agent, :answer, :*]` | `%{}` |
| Self Correction | `[:arcana, :agent, :self_correct, :*]` | `%{attempt: integer}` |

### 3. Built-in Logger (`Arcana.Telemetry.Logger`)

**Location**: `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/telemetry/logger.ex`

Provides ready-to-use telemetry logging with:

- **One-line setup**: `Arcana.Telemetry.Logger.attach()`
- **Configurable log level**: Default `:info`, customizable
- **Custom handler ID**: For multiple handler instances
- **Human-readable output**: Duration formatting, event-specific details
- **Detach support**: Clean teardown with `detach/1`

Example output:
```
[info] [Arcana] search completed in 42ms (15 results)
[info] [Arcana] llm.complete completed in 1.23s [zai:glm-4.7] ok (156 chars) prompt=892chars
[info] [Arcana] agent.rerank completed in 312ms (10/25 kept)
```

---

## Portfolio Libraries Current State

### PortfolioCore Telemetry

**Location**: `/home/home/p/g/n/portfolio_core/lib/portfolio_core/telemetry.ex`

#### Capabilities:
1. **`with_span` macro**: Wraps operations with start/stop/exception events
2. **`emit/3` function**: Simple event emission helper
3. **`measure/3` function**: Duration measurement with status tracking
4. **`events/0` function**: Returns list of all defined events

#### Defined Event Categories:
- **Router events**: Route start/stop/exception, health check
- **Cache events**: Hit/miss/put/delete
- **Agent events**: Run start/stop, tool execute
- **Evaluation events**: RAG triad and hallucination detection
- **Graph events**: Traverse, vector search, community operations

#### Limitations:
- No built-in logger handler
- Limited metadata in events
- Manual event list maintenance
- No unified span approach across adapters

### PortfolioIndex Telemetry

**Location**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/telemetry.ex`

#### Capabilities:
1. **Supervisor-based**: Runs as part of application supervision tree
2. **Metrics definitions**: Pre-defined `telemetry_metrics` for dashboards
3. **Periodic polling**: Via `telemetry_poller` (currently empty)
4. **Basic logging handler**: `attach_default_handlers/0`

#### Defined Metrics:
- Vector store: store count, search count/duration, batch count
- Graph store: create node/edge count, query count/duration
- Embedder: embed count, batch count, tokens, duration
- LLM: complete count, input/output tokens, duration
- Pipeline: file processed count, chunks per file
- RAG: retrieve count/duration, items returned

#### Actual Telemetry Usage in Adapters:
Individual adapters emit events via `:telemetry.execute/3`:
- LLM adapters (Anthropic, Gemini, OpenAI): Basic count events
- Embedder adapters: Operation events with measurements
- Vector store (PgVector): Query events
- Graph store (Neo4j): Traversal and community events
- RAG strategies: Retrieve events

#### Limitations:
- **No span-based approach**: Uses discrete events, not spans
- **Inconsistent metadata**: Each adapter defines its own schema
- **No exception events**: Most adapters only emit success events
- **Minimal logging handler**: Only logs at debug level with limited formatting
- **No start events**: Only stop/completion events are typically emitted

---

## Identified Gaps

### Gap 1: Span-Based Telemetry Pattern

- **Arcana Feature**: Uses `:telemetry.span/3` for all operations, automatically generating `:start`, `:stop`, and `:exception` event triplets with consistent timing
- **Missing From**: PortfolioIndex (adapters use discrete events), partially in PortfolioCore (has `with_span` but not universally applied)
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Arcana wraps every operation (ingest, search, ask, embed, LLM, agent steps) in telemetry spans
  - PortfolioIndex adapters use `emit_telemetry/3` helper functions that call `:telemetry.execute/3` directly
  - No automatic exception tracking in portfolio adapters
  - Requires refactoring adapter implementations to use span pattern

### Gap 2: Built-in Telemetry Logger

- **Arcana Feature**: `Arcana.Telemetry.Logger` module with one-line attach, human-readable formatting, configurable log levels, and event-specific detail extraction
- **Missing From**: Both PortfolioCore and PortfolioIndex
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana's logger provides formatted output like `[Arcana] llm.complete completed in 1.23s [model] ok (chars)`
  - PortfolioIndex has basic `attach_default_handlers/0` but only logs at debug level with raw `inspect/1` output
  - PortfolioCore has no built-in logger handler at all
  - Should create `PortfolioIndex.Telemetry.Logger` following Arcana's pattern

### Gap 3: LLM Telemetry Enrichment

- **Arcana Feature**: LLM events include `model`, `prompt_length`, `context_count`, `success`, `response_length`, and `error` details
- **Missing From**: PortfolioIndex LLM adapters
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana's `[:arcana, :llm, :complete, :*]` events provide comprehensive LLM observability
  - PortfolioIndex Anthropic adapter only emits `%{count: 1}` measurement
  - No tracking of prompt length, response length, or success/failure status
  - No model identifier in telemetry events

### Gap 4: Agent Pipeline Telemetry

- **Arcana Feature**: Dedicated telemetry events for each agent pipeline step (rewrite, select, expand, decompose, search, rerank, answer, self_correct)
- **Missing From**: PortfolioIndex RAG strategies
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Arcana tracks 8 distinct pipeline steps with specific metadata for each
  - PortfolioIndex agentic RAG strategy has minimal telemetry (basic iterate events)
  - No visibility into individual pipeline step durations or outcomes
  - Critical for debugging and optimizing RAG pipelines

### Gap 5: Search Mode and Query Context Tracking

- **Arcana Feature**: Search events include `mode` (semantic, keyword, hybrid), `limit`, and full `query` string
- **Missing From**: PortfolioIndex vector store telemetry
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana's `[:arcana, :search, :*]` events capture search strategy used
  - PortfolioIndex only tracks generic search count/duration
  - No ability to compare performance across search modes
  - Missing query string makes debugging difficult

### Gap 6: Ingest/Chunking Telemetry

- **Arcana Feature**: Ingest events track `text`, `collection`, `document`, and `chunk_count`
- **Missing From**: PortfolioIndex ingestion pipeline
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana provides end-to-end ingest visibility
  - PortfolioIndex ingestion pipeline emits `file_processed` events but lacks document/chunk detail
  - No collection context in ingestion telemetry
  - Cannot correlate ingestion with downstream search performance

### Gap 7: Embedding Dimension Tracking

- **Arcana Feature**: Embed events include `dimensions` in stop metadata
- **Missing From**: PortfolioIndex embedder adapters
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana tracks embedding vector dimensions for observability
  - PortfolioIndex embedders track tokens but not output dimensions
  - Useful for validating embedding model configuration
  - Important when supporting multiple embedding models

### Gap 8: Exception Event Consistency

- **Arcana Feature**: All operations emit `:exception` events with `kind`, `reason`, and `stacktrace`
- **Missing From**: PortfolioIndex adapters (no exception events)
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Arcana's span pattern automatically captures exceptions
  - PortfolioIndex adapters typically return error tuples without telemetry
  - No visibility into failure rates or error patterns
  - Critical for production monitoring and alerting

### Gap 9: Reranker Telemetry

- **Arcana Feature**: `[:arcana, :agent, :rerank, :*]` events with `kept` and `original` chunk counts
- **Missing From**: PortfolioIndex reranker adapters
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana tracks reranking effectiveness (kept/original ratio)
  - PortfolioIndex LLM reranker emits basic events but no kept/original metrics
  - Cannot measure reranking impact on result quality
  - Important for tuning reranking thresholds

### Gap 10: Batch Embedding Telemetry

- **Arcana Feature**: `[:arcana, :embed_batch, :stop]` events for batch operations
- **Missing From**: PortfolioIndex embedder batch operations (partial)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana Logger handles `embed_batch` events with count extraction
  - PortfolioIndex defines `embed_batch.count` metric but implementation varies by adapter
  - Need consistent batch telemetry across all embedder implementations

### Gap 11: Self-Correction Iteration Tracking

- **Arcana Feature**: `[:arcana, :agent, :self_correct, :*]` events with `attempt` count
- **Missing From**: PortfolioIndex Self-RAG strategy
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana tracks each self-correction iteration for observability
  - PortfolioIndex Self-RAG has no iteration telemetry
  - Cannot measure correction loop depth or convergence
  - Important for understanding answer quality improvement

### Gap 12: Query Expansion/Decomposition Telemetry

- **Arcana Feature**: Separate events for query expansion (`expanded_query`) and decomposition (`sub_question_count`)
- **Missing From**: PortfolioIndex query processing
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana distinguishes between expansion (rephrasing) and decomposition (sub-questions)
  - PortfolioIndex has no dedicated query transformation telemetry
  - Cannot measure query transformation effectiveness
  - Impacts debugging of multi-step query processing

---

## Implementation Priority

### High Priority (Immediate Value)

1. **Gap 2: Built-in Telemetry Logger** - Quick win, improves debugging experience
2. **Gap 8: Exception Event Consistency** - Critical for production monitoring
3. **Gap 3: LLM Telemetry Enrichment** - High-value observability for expensive operations
4. **Gap 4: Agent Pipeline Telemetry** - Essential for RAG optimization

### Medium Priority (Significant Value)

5. **Gap 1: Span-Based Telemetry Pattern** - Architectural improvement, requires refactoring
6. **Gap 5: Search Mode Tracking** - Enables performance comparison
7. **Gap 9: Reranker Telemetry** - Measures reranking effectiveness
8. **Gap 11: Self-Correction Tracking** - Self-RAG optimization

### Lower Priority (Nice to Have)

9. **Gap 6: Ingest/Chunking Telemetry** - Improves ingestion visibility
10. **Gap 7: Embedding Dimension Tracking** - Minor observability enhancement
11. **Gap 10: Batch Embedding Telemetry** - Standardization
12. **Gap 12: Query Transformation Telemetry** - Advanced debugging

---

## Technical Dependencies

### Required Dependencies

| Gap | Dependencies |
|-----|--------------|
| Gap 1 (Spans) | Refactor of all adapter implementations |
| Gap 2 (Logger) | None - can be added independently |
| Gap 3 (LLM) | Modify LLM adapter implementations |
| Gap 4 (Pipeline) | Modify RAG strategy implementations |

### Cross-Cutting Concerns

1. **Event Naming Convention**: Adopt consistent `[:portfolio_index, :component, :operation, :phase]` pattern
2. **Metadata Schema**: Define standardized metadata structures per event type
3. **Duration Units**: Standardize on native time units with conversion helpers
4. **Error Format**: Consistent exception metadata structure

### Integration Points

- **PortfolioCore**: Leverage existing `with_span` macro, extend event definitions
- **Telemetry Libraries**: Compatible with `telemetry_metrics`, `prom_ex`, `opentelemetry`
- **Logging**: Integrate with Elixir Logger via handler module

---

## Recommendations

### Immediate Actions

1. Create `PortfolioIndex.Telemetry.Logger` module following Arcana's pattern
2. Add `:exception` events to critical paths (LLM, embedder, vector store)
3. Enrich LLM telemetry with model, prompt length, response metrics

### Short-Term (1-2 sprints)

4. Refactor RAG strategies to emit pipeline step events
5. Add reranker telemetry with kept/original metrics
6. Implement search mode tracking in vector store adapters

### Medium-Term (1-2 months)

7. Migrate adapters to span-based pattern
8. Standardize telemetry metadata schemas
9. Add comprehensive documentation with examples

---

## Appendix: File Locations

### Arcana Files
- `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/telemetry.ex`
- `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/telemetry/logger.ex`
- `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent.ex` (telemetry usage)
- `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/llm.ex` (telemetry usage)

### Portfolio Files
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/telemetry.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/telemetry.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/llm/anthropic.ex` (example adapter)
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/agentic.ex` (example strategy)
