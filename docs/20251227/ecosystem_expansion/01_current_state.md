# Portfolio Index - Current State Analysis

## Overview

**Version:** 0.1.1
**Role:** Production adapter implementations for portfolio_core ports
**Dependencies:** portfolio_core (~0.1.1)
**Published:** Hex.pm

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      PORTFOLIO INDEX                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ADAPTERS (implementations of portfolio_core ports)     │   │
│  │                                                         │   │
│  │  VectorStore      GraphStore       DocumentStore       │   │
│  │  └─ Pgvector      └─ Neo4j         └─ Postgres         │   │
│  │                                                         │   │
│  │  Embedder         LLM              Chunker             │   │
│  │  └─ Gemini        └─ Gemini        └─ Recursive        │   │
│  │  └─ OpenAI*       └─ Anthropic*                        │   │
│  │                                                         │   │
│  │  * = placeholder/stub                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┴─────────────────────────────┐   │
│  │  RAG STRATEGIES                                         │   │
│  │  • Hybrid     - Vector + keyword with RRF               │   │
│  │  • SelfRAG    - Self-critique and refinement            │   │
│  │  • GraphRAG*  - Graph-aware retrieval (stub)            │   │
│  │  • Agentic*   - Agent-based retrieval (stub)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┴─────────────────────────────┐   │
│  │  PIPELINES (Broadway-based)                             │   │
│  │  • Ingestion  - File discovery and chunking             │   │
│  │  • Embedding  - Vector generation and storage           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Implemented Adapters

### 1. Pgvector (VectorStore)

**Status:** Complete

```elixir
# Key features
- PostgreSQL + pgvector extension
- IVFFlat and HNSW index types
- Metrics: cosine, euclidean, dot_product
- Batch operations (store_batch)
- Metadata filtering
- Dynamic index creation
- Idempotent operations
```

**Schema:**
- `vector_index_registry` - Index metadata
- Dynamic tables per index_id with vector columns

### 2. Neo4j (GraphStore)

**Status:** Complete

```elixir
# Key features
- Boltx driver for Bolt protocol
- Multi-graph isolation via _graph_id property
- Schema versioning
- Constraint and index management
- Cypher query execution
- Automatic graph_id injection
```

**Schema Management:**
- `:SchemaVersion` node for versioning
- Unique constraints on node/edge IDs
- Full-text search indexes

### 3. Postgres (DocumentStore)

**Status:** Complete

```elixir
# Key features
- Content-addressable storage (SHA256)
- Namespace isolation via store_id
- CRUD operations
- Metadata support
- Composite primary keys
```

### 4. Gemini (Embedder)

**Status:** Complete

```elixir
# Key features
- Model: text-embedding-004
- Dimensions: 768
- Batch embedding support
- Rate limiting via Hammer
- Telemetry integration
- Retry with backoff
```

### 5. OpenAI (Embedder)

**Status:** Stub

```elixir
# Placeholder only
- Returns {:error, :not_implemented}
- Model references: text-embedding-3-small/large
```

### 6. Gemini (LLM)

**Status:** Complete

```elixir
# Key features
- Model: gemini-2.0-flash-exp
- Chat completions with history
- Streaming support
- Token usage tracking
- System prompt support
- Retry with exponential backoff
```

### 7. Anthropic (LLM)

**Status:** Stub

```elixir
# Placeholder only
- Returns {:error, :not_implemented}
- Model references: claude-3-sonnet (200k context)
```

### 8. Recursive (Chunker)

**Status:** Complete

```elixir
# Key features
- Format-aware splitting
- Formats: plain, markdown, code, HTML
- Recursive separator hierarchy
- Configurable chunk size/overlap
- Respects format boundaries
- Elixir-aware code splitting
```

## RAG Strategies

### Hybrid Strategy

**Status:** Complete

```elixir
# Features
- Vector similarity search
- Keyword search
- Reciprocal Rank Fusion (RRF)
- Configurable k and rrf_k parameters
- Dynamic adapter resolution
```

### SelfRAG Strategy

**Status:** Complete

```elixir
# Features
- Self-assessment of retrieval need
- Retrieval with self-critique scoring
- Answer generation with embedded critique
- Refinement based on scores:
  - Relevance
  - Support
  - Completeness
- Tracks retrieval_used flag
- Token counting
```

### GraphRAG Strategy

**Status:** Stub

```elixir
# Current: Delegates to Hybrid
# Planned:
- Graph traversal from query entities
- Community context aggregation
- Multi-hop reasoning
```

### Agentic Strategy

**Status:** Stub

```elixir
# Current: Delegates to Hybrid
# Planned:
- Tool-based retrieval
- Iterative refinement
- Query decomposition
```

## Pipelines

### Ingestion Pipeline (Broadway)

**Status:** Complete

```elixir
# Features
- File discovery with glob patterns
- Content reading and parsing
- Chunking via configured chunker
- Queue routing to embedding pipeline
- Backpressure handling
- Enqueue function for external input
```

### Embedding Pipeline (Broadway)

**Status:** Complete

```elixir
# Features
- Consumes from ingestion queue
- Embedding generation
- Rate limiting (100 req/min default)
- Batch storage to vector store
- Telemetry for monitoring
```

### Producers

- **FileProducer:** File discovery with polling, deduplication
- **ETSProducer:** Inter-pipeline queue via ETS

## Current Gaps

### Missing Adapters (vs rag_ex)

| Adapter Type | rag_ex Has | portfolio_index Has |
|--------------|------------|---------------------|
| OpenAI Embedder | Full | Stub |
| Anthropic LLM | Full (Claude) | Stub |
| OpenAI LLM | Full (GPT-4) | None |
| Ollama | Full | None |
| Cohere Reranker | Full | None |
| Qdrant | None | None |
| Pinecone | None | None |
| RocksDB Graph | TripleStore | None |

### Missing Strategies

| Strategy | rag_ex | portfolio_index |
|----------|--------|-----------------|
| Full-text only | Yes | No |
| Graph traversal | Yes | Stub |
| Agentic | Partial | Stub |
| Semantic chunking | Yes | No |

### Missing Infrastructure

| Feature | Description |
|---------|-------------|
| Streaming LLM | Not implemented |
| Reranker port | Not implemented |
| Cost tracking | Not implemented |
| Circuit breaker | Not implemented |
| Multi-tenant | Not implemented |

## Code Metrics

| Metric | Value |
|--------|-------|
| Adapter modules | 8 |
| RAG strategies | 4 (2 complete) |
| Pipeline modules | 4 |
| Migrations | 3 |
| Test files | ~15 |

## Dependencies

```elixir
# Core
{:portfolio_core, "~> 0.1.1"}

# Database
{:ecto_sql, "~> 3.11"}
{:postgrex, "~> 0.17"}
{:pgvector, "~> 0.2"}

# Graph
{:boltx, "~> 0.0.6"}

# AI
{:gemini_ex, "~> 0.8.6"}

# Pipelines
{:broadway, "~> 1.0"}
{:gen_stage, "~> 1.2"}

# Utilities
{:hammer, "~> 6.1"}
{:req, "~> 0.4"}
{:finch, "~> 0.18"}
{:jason, "~> 1.4"}

# Telemetry
{:telemetry, "~> 1.2"}
{:telemetry_metrics, "~> 0.6"}
{:telemetry_poller, "~> 1.0"}
```

## Database Schema

### PostgreSQL Migrations

1. **Enable pgvector** - Extension setup
2. **Create documents** - Document storage table
3. **Create vector_indexes** - Index registry and dynamic tables

### Neo4j Schema

- Schema versioning via `:SchemaVersion` node
- Unique constraints per graph
- Full-text search indexes
- Property indexes for common queries
