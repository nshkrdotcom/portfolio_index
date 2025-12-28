# Portfolio Index - Expansion Roadmap

## Overview

This document outlines the adapter and infrastructure expansion plan for portfolio_index, focusing on feature parity with rag_ex while maintaining clean architecture.

**Note:** The `portfolio_core` dependency is already updated to v0.2.0 in mix.exs.

## Priority Tiers

### Tier 1: Complete Existing Stubs

#### 1.1 Anthropic LLM (via claude_agent_sdk)

**Goal:** Full Claude integration using the official `claude_agent_sdk` Hex library

```elixir
# Target capabilities
- Uses claude_agent_sdk from Hex (latest version)
- Default model with configurable override
- Streaming support (SDK-native)
- System prompt support
- Tool use (function calling)
- Token counting via SDK
```

**Implementation:**
- Add `{:claude_agent_sdk, "~> 0.1"}` to dependencies
- Create thin wrapper implementing `PortfolioCore.Ports.LLM` behavior
- Delegate to SDK for all API interactions
- Expose model configuration via opts (defaults to SDK default)
- Add telemetry hooks around SDK calls

#### 1.2 GraphRAG Strategy

**Goal:** Complete graph-aware retrieval

```elixir
# Target flow
1. Extract entities from query
2. Find matching nodes in graph
3. Traverse to related entities (configurable depth)
4. Aggregate community context
5. Combine with vector search results
6. Generate with full context
```

**Implementation:**
- Entity extraction via LLM
- Graph traversal utilities
- Community detection (label propagation)
- Context aggregation and ranking

#### 1.3 Agentic Strategy

**Goal:** Tool-based retrieval with iteration

```elixir
# Target flow
1. Analyze query complexity
2. Decompose into sub-queries if needed
3. Use tools to gather information:
   - Search (vector, keyword, graph)
   - Read (file contents)
   - Analyze (code structure)
4. Synthesize results
5. Self-critique and refine
6. Generate final answer
```

**Implementation:**
- Tool registry and execution
- Query decomposition
- Iteration loop with termination
- Result synthesis

### Tier 2: New Adapters

#### 2.1 OpenAI LLM (via codex_sdk)

**Goal:** GPT-4 and o1/o3 support using the official `codex_sdk` Hex library

```elixir
# Target capabilities
- Uses codex_sdk from Hex (latest version)
- Default model with configurable override
- Streaming via SDK-native support
- Function calling
- JSON mode
- Token counting via SDK
```

**Implementation:**
- Add `{:codex_sdk, "~> 0.1"}` to dependencies
- Create thin wrapper implementing `PortfolioCore.Ports.LLM` behavior
- Delegate to SDK for all API interactions
- Expose model configuration via opts (defaults to SDK default)
- Add telemetry hooks around SDK calls

#### 2.2 Ollama Adapter

**Goal:** Local inference support

```elixir
# Target capabilities
- Local model execution
- Embeddings (nomic-embed-text, etc.)
- Completions (llama, mistral, etc.)
- Streaming
- GPU acceleration support
- Model management
```

**Implementation:**
- HTTP API integration
- Model availability checking
- Graceful fallback when unavailable

#### 2.3 Cohere Reranker

**Goal:** Dedicated reranking capability

```elixir
# Target capabilities
- Model: rerank-english-v2.0, rerank-multilingual-v2.0
- Score-based reranking
- Batch processing
- Configurable top_n
```

**Implementation:**
- Implement Reranker port from portfolio_core
- Add to manifest schema
- Integrate with RAG strategies

#### 2.4 Qdrant VectorStore

**Goal:** Alternative high-performance vector DB

```elixir
# Target capabilities
- HTTP and gRPC clients
- Collection management
- Payload filtering
- Quantization support
- Clustering
```

**Implementation:**
- Use qdrant-client or HTTP API
- Implement VectorStore behavior
- Add migration utilities from pgvector

### Tier 3: Advanced Features

#### 3.1 Streaming Support

**Goal:** Stream LLM responses through the stack

```elixir
# Target API
PortfolioIndex.Adapters.LLM.Gemini.stream(messages, callback)
PortfolioIndex.RAG.Strategies.Hybrid.stream_query(question, callback)
```

**Implementation:**
- SSE parsing for all LLM adapters
- Callback-based streaming
- Chunked response handling

#### 3.2 Cost Tracking

**Goal:** Track API costs across all adapters

```elixir
# Target telemetry events
[:portfolio_index, :cost, :embedding, :tokens]
[:portfolio_index, :cost, :llm, :tokens]
[:portfolio_index, :cost, :api_call]

# Aggregation
PortfolioIndex.Costs.total(since: DateTime.utc_now() |> DateTime.add(-24, :hour))
PortfolioIndex.Costs.by_adapter(:embedder)
```

**Implementation:**
- Token counting for all adapters
- Cost configuration per model
- Telemetry event emission
- Aggregation utilities

#### 3.3 Circuit Breaker

**Goal:** Graceful degradation on failures

```elixir
# Target behavior
- Track failure rate per adapter
- Open circuit on threshold exceeded
- Half-open state for recovery testing
- Closed on success streak
- Telemetry events for state changes
```

**Implementation:**
- GenServer for state management
- Configurable thresholds
- Integration with registry health status

#### 3.4 Multi-Tenant Isolation

**Goal:** Complete tenant separation

```elixir
# Target isolation
- Vector indexes per tenant
- Graph namespaces per tenant
- Document stores per tenant
- Resource quotas
- Cost tracking per tenant
```

**Implementation:**
- Tenant context threading
- Prefixed resource names
- Quota checking middleware

### Tier 4: Additional Chunking Strategies

**Goal:** Port chunking strategies from rag_ex

| Strategy | Description |
|----------|-------------|
| Character | Fixed-size with smart boundaries |
| Sentence | Sentence-boundary preservation |
| Paragraph | Topic-structure preservation |
| Semantic | Embedding-based similarity grouping |
| Code | Language-aware AST-based splitting |

**Implementation:**
- Add Chunker behavior implementations
- Configurable via manifest
- Integration with ingestion pipeline

## Implementation Phases

### Phase 1: Complete Stubs (Q1)

```
Week 1-2: Anthropic LLM (claude_agent_sdk wrapper)
Week 3-4: OpenAI LLM (codex_sdk wrapper)
Week 5-6: GraphRAG strategy
Week 7-8: Agentic strategy
```

### Phase 2: New Adapters (Q2)

```
Week 1-2: Ollama adapter (embedder + LLM)
Week 3-4: Cohere reranker
Week 5-6: Testing and docs
Week 7-8: Infrastructure (streaming polish)
```

### Phase 3: Infrastructure (Q3)

```
Week 1-2: Streaming support
Week 3-4: Cost tracking
Week 5-6: Circuit breaker
Week 7-8: Multi-tenant
```

### Phase 4: Chunking (Q4)

```
Week 1-2: Character + Sentence
Week 3-4: Paragraph + Semantic
Week 5-6: Code (multi-language)
Week 7-8: Integration testing
```

## Success Metrics

| Feature | Metric | Target |
|---------|--------|--------|
| LLM Adapters | Count | 4 (Gemini, Anthropic via SDK, OpenAI via SDK, Ollama) |
| Embedder Adapters | Count | 2 (Gemini, Ollama) |
| RAG Strategies | Complete | 4/4 |
| Streaming | Latency to first token | <500ms |
| Cost tracking | Accuracy | 99%+ |
| Chunking strategies | Count | 5 |

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| API changes | Version pin SDKs, integration tests |
| Rate limiting | Hammer with adaptive backoff |
| Cost overruns | Budget alerts, circuit breakers |
| Complexity | Module boundaries, comprehensive tests |
