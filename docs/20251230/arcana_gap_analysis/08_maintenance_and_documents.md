# Maintenance, Documents, and Pipeline Features Gap Analysis

## Executive Summary

This document analyzes the gap between Arcana's maintenance, rewriter, parser, document/collection/chunk model systems and the equivalent functionality in the Portfolio libraries (portfolio_core, portfolio_index, portfolio_manager). The analysis focuses exclusively on RAG functionality.

Arcana provides a unified, Ecto-backed document management system with built-in maintenance operations, while Portfolio takes a more distributed approach with Broadway pipelines and adapter-based architecture. Key gaps include production maintenance utilities, Ecto schema-backed document models, unified collection management, and LLM-based query rewriting.

---

## Arcana Capabilities

### Maintenance Features

**File**: `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/maintenance.ex`

Arcana provides production-ready maintenance functions callable from releases:

1. **Re-embedding System** (`reembed/2`)
   - Batch re-embeds all chunks when switching embedding models
   - Rechunks documents that have no chunks (status: pending or chunk_count: 0)
   - Configurable batch size and progress callbacks
   - Runs within Ecto transactions for consistency
   - Streaming support for large datasets via `repo.stream/2`

2. **Embedding Diagnostics**
   - `embedding_dimensions/0` - Returns configured embedding dimensions
   - `embedding_info/0` - Returns comprehensive embedding configuration including type, model, and dimensions

3. **Production Deployment Support**
   - Designed for release environments (no mix tasks required)
   - Callable via IEx remote shell or release eval commands
   - Example: `bin/my_app eval "Arcana.Maintenance.reembed(MyApp.Repo)"`

### Rewriters

**File**: `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/rewriters.ex`

LLM-based query rewriting helpers:

1. **Query Expansion** (`expand/2`)
   - Expands queries with synonyms and related terms
   - Uses LLM protocol for provider-agnostic operation
   - Customizable prompt templates with `{query}` placeholder

2. **Keyword Extraction** (`keywords/2`)
   - Extracts key search terms from natural language queries
   - Reduces noise for better keyword-based retrieval

3. **Query Decomposition** (`decompose/2`)
   - Breaks complex multi-part questions into simpler sub-queries
   - Enables multi-hop retrieval strategies

4. **Dual API Pattern**
   - Direct use: `Rewriters.expand("ML models", llm: my_llm)`
   - Curried function: `Arcana.search("query", rewriter: Rewriters.expand(llm: my_llm))`

### Parser

**File**: `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/parser.ex`

File parsing with format detection:

1. **Supported Formats**
   - Text formats: `.txt`, `.md`, `.markdown`
   - PDF parsing via `pdftotext` (poppler-utils)

2. **PDF Support**
   - Magic byte validation (`%PDF` header check)
   - External dependency detection (`pdf_support_available?/0`)
   - Layout-preserving extraction (`pdftotext -layout`)

3. **Error Handling**
   - `:file_not_found`, `:read_error`, `:unsupported_format`
   - `:invalid_pdf`, `:pdf_parse_error`, `:pdf_support_not_available`

### Document Model

**File**: `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/document.ex`

Ecto schema for documents:

```elixir
schema "arcana_documents" do
  field(:content, :string)
  field(:content_type, :string, default: "text/plain")
  field(:source_id, :string)
  field(:file_path, :string)
  field(:metadata, :map, default: %{})
  field(:status, Ecto.Enum, values: [:pending, :processing, :completed, :failed])
  field(:error, :string)
  field(:chunk_count, :integer, default: 0)
  belongs_to(:collection, Arcana.Collection)
  has_many(:chunks, Arcana.Chunk)
  timestamps()
end
```

Key features:
- Binary UUID primary key
- Processing status tracking with Ecto.Enum
- Collection relationship for segmentation
- Chunk count for quick aggregation
- Error message storage for failed ingestions

### Collection Model

**File**: `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/collection.ex`

Ecto schema for document collections:

```elixir
schema "arcana_collections" do
  field(:name, :string)
  field(:description, :string)
  has_many(:documents, Arcana.Document)
  timestamps()
end
```

Key features:
- Unique constraint on name
- Optional description (used for agent-based collection selection)
- `get_or_create/3` helper for upsert semantics
- Lazy description updates (only updates if existing is nil/empty)

### Chunk Model

**File**: `/home/home/p/g/n/portfolio_index/arcana/lib/arcana/chunk.ex`

Ecto schema for vector chunks:

```elixir
schema "arcana_chunks" do
  field(:text, :string)
  field(:embedding, Pgvector.Ecto.Vector)
  field(:chunk_index, :integer, default: 0)
  field(:token_count, :integer)
  field(:metadata, :map, default: %{})
  belongs_to(:document, Arcana.Document)
  timestamps()
end
```

Key features:
- Native pgvector integration (`Pgvector.Ecto.Vector`)
- Document relationship with foreign key constraint
- Token count for cost estimation
- Chunk ordering via `chunk_index`

### Main Module Integration

**File**: `/home/home/p/g/n/portfolio_index/arcana/lib/arcana.ex`

Unified API with:
- `ingest/2` and `ingest_file/2` for document ingestion
- `search/2` with semantic, fulltext, and hybrid modes
- `ask/2` for RAG question-answering
- `rewrite_query/2` for query preprocessing
- `delete/2` for document removal
- Telemetry spans for observability
- RRF (Reciprocal Rank Fusion) for hybrid search
- Collection-aware search with multi-collection support

---

## Portfolio Libraries Current State

### portfolio_core

**DocumentStore Port** (`/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/document_store.ex`):
- Behaviour definition only (no implementation)
- CRUD operations: `store`, `get`, `delete`, `list`
- Metadata search via `search_metadata`
- Type definitions for document structure

### portfolio_index

**DocumentStore Postgres Adapter** (`/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/document_store/postgres.ex`):
- Raw SQL-based implementation
- Content-addressable storage (SHA256 hashing)
- Store namespace isolation via `store_id`
- No Ecto schema (uses raw Postgrex queries)
- Additional helpers: `exists_by_hash?`, `get_by_hash`

**Ingestion Pipeline** (`/home/home/p/g/n/portfolio_index/lib/portfolio_index/pipelines/ingestion.ex`):
- Broadway-based file processing
- FileProducer for file discovery
- Basic file type detection
- Chunking integration with Recursive chunker
- No document status tracking

**Embedding Pipeline** (`/home/home/p/g/n/portfolio_index/lib/portfolio_index/pipelines/embedding.ex`):
- Broadway-based embedding generation
- ETS-based internal queuing
- Rate limiting via Hammer
- Batch storage to vector store

**Chunker** (`/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/chunker/recursive.ex`):
- Format-aware splitting (17+ formats via Separators module)
- Configurable size function (character or token-based)
- Overlap support
- Offset tracking

### portfolio_manager

**RAG Module** (`/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/rag.ex`):
- Strategy-based retrieval (hybrid, self_rag, graph_rag, agentic)
- Manifest-driven configuration
- Basic streaming support (`stream_query`, `stream_search`)
- Repository indexing (`index_repo`)
- No query rewriting

**Pipeline Module** (`/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/pipeline.ex`):
- DAG-based orchestration
- Dependency resolution
- Parallel execution
- Caching via ETS
- Error policies (halt, continue, retry)

---

## Identified Gaps

### Gap 1: Production Maintenance Utilities

- **Arcana Feature**: `Arcana.Maintenance` module provides `reembed/2`, `embedding_dimensions/0`, and `embedding_info/0` for production operations without mix tasks.
- **Missing From**: portfolio_index, portfolio_manager
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Portfolio lacks any production maintenance tooling
  - No way to re-embed chunks when switching embedding models
  - No diagnostic functions for verifying embedding configuration
  - Would require adding chunk tracking to document store
  - Batch processing with streaming would need Ecto integration

### Gap 2: Ecto Schema-Backed Document Model

- **Arcana Feature**: `Arcana.Document` Ecto schema with status tracking, collection relationship, and chunk count.
- **Missing From**: portfolio_index (uses raw SQL)
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Current Postgres adapter uses raw Postgrex queries
  - No document lifecycle status (pending, processing, completed, failed)
  - No error message storage for failed ingestions
  - No chunk count tracking
  - Would require database migration and schema definition
  - Foreign key relationships to chunks not defined

### Gap 3: Collection/Namespace Management

- **Arcana Feature**: `Arcana.Collection` schema with `get_or_create/3`, unique constraints, and description for agent routing.
- **Missing From**: portfolio_index
- **Implementation Complexity**: Low
- **Technical Details**:
  - Portfolio uses `store_id` string for namespace isolation
  - No first-class Collection entity
  - No collection metadata (description, etc.)
  - Descriptions are used by Arcana's agent for collection selection
  - Would require new schema and migration

### Gap 4: Chunk Ecto Schema with Vector Type

- **Arcana Feature**: `Arcana.Chunk` with native `Pgvector.Ecto.Vector` type, document relationship, and metadata.
- **Missing From**: portfolio_index
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Portfolio stores vectors via VectorStore adapter (no Ecto schema)
  - No direct Ecto integration for pgvector
  - Chunk metadata is stored but without schema validation
  - Would require Pgvector.Ecto dependency

### Gap 5: LLM-Based Query Rewriters

- **Arcana Feature**: `Arcana.Rewriters` with `expand`, `keywords`, and `decompose` for query preprocessing.
- **Missing From**: portfolio_manager, portfolio_index
- **Implementation Complexity**: Low
- **Technical Details**:
  - Portfolio RAG has no query rewriting capability
  - Arcana integrates rewriters into search via `:rewriter` option
  - Uses LLM protocol for provider-agnostic operation
  - Customizable prompts with `{query}` placeholder
  - Easy to port using existing LLM adapter infrastructure

### Gap 6: File Parser with PDF Support

- **Arcana Feature**: `Arcana.Parser` with text/markdown/PDF parsing and magic byte validation.
- **Missing From**: portfolio_index (only basic file reading)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Ingestion pipeline does `File.read` without format parsing
  - No PDF text extraction
  - No content type detection
  - Would need poppler-utils dependency documentation
  - Error handling for various file issues not present

### Gap 7: Document Processing Status Tracking

- **Arcana Feature**: Document `status` field with Ecto.Enum (`:pending`, `:processing`, `:completed`, `:failed`) and `error` field.
- **Missing From**: portfolio_index
- **Implementation Complexity**: Low
- **Technical Details**:
  - No way to track document ingestion state
  - Failed ingestions are logged but not queryable
  - No mechanism to retry failed documents
  - Would enable building retry logic and progress monitoring

### Gap 8: Unified Ingestion API

- **Arcana Feature**: `Arcana.ingest/2` and `Arcana.ingest_file/2` with collection support, telemetry, and automatic chunking/embedding.
- **Missing From**: portfolio_index (Broadway pipelines only)
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Portfolio requires starting Broadway pipelines
  - No simple function-based ingestion API
  - Arcana provides synchronous ingestion for simpler use cases
  - Portfolio's async approach is better for large-scale, but lacks simple API

### Gap 9: Hybrid Search with RRF in Core Module

- **Arcana Feature**: `Arcana.search/2` with `:mode` option (`:semantic`, `:fulltext`, `:hybrid`) and built-in RRF.
- **Missing From**: portfolio_index (strategy-based only in portfolio_manager)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Portfolio uses RAG strategies for hybrid search
  - No simple search mode option in base API
  - RRF exists in PortfolioCore.VectorStore.RRF but not unified
  - Would simplify API surface

### Gap 10: Collection-Filtered Search

- **Arcana Feature**: Search with `:collection` or `:collections` option for multi-collection queries.
- **Missing From**: portfolio_index (uses index_id)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Portfolio uses `index_id` which is similar but not identical
  - No support for searching multiple collections in single query
  - Arcana merges results across collections with RRF

### Gap 11: Ask/QA API with Context

- **Arcana Feature**: `Arcana.ask/2` combines search + LLM completion with custom prompt support.
- **Missing From**: portfolio_index (exists in portfolio_manager.RAG but differently structured)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana returns `{:ok, answer, context}` with context chunks
  - Portfolio's `ask` is more basic
  - Custom prompt function support missing in Portfolio
  - LLM protocol integration provides flexibility

### Gap 12: Telemetry Spans for Ingestion/Search

- **Arcana Feature**: `:telemetry.span/3` calls for `[:arcana, :ingest]`, `[:arcana, :search]`, `[:arcana, :ask]`.
- **Missing From**: portfolio_index (has some telemetry but not comprehensive spans)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Portfolio has telemetry for pipeline stages
  - No unified ingestion/search span telemetry
  - Would improve observability and debugging

### Gap 13: Memory Vector Store Backend

- **Arcana Feature**: `Arcana.VectorStore.Memory` for testing and small-scale RAG without pgvector.
- **Missing From**: portfolio_index (hardcoded to Pgvector)
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Portfolio's VectorStore adapters are Pgvector-centric
  - No in-memory option for testing
  - Arcana uses HNSWLib for memory backend
  - Useful for local development without Postgres

### Gap 14: Configurable Embedder Resolution

- **Arcana Feature**: `Arcana.embedder/0` with `:local`, `:openai`, function, or custom module support.
- **Missing From**: portfolio_index (fixed adapter pattern)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Portfolio uses manifest-driven adapter resolution
  - Arcana provides simpler config-based approach
  - Anonymous function support for testing
  - Both approaches valid but Arcana's is simpler for single-app use

---

## Implementation Priority

### High Priority (Core Functionality Gaps)

1. **Gap 2: Ecto Schema-Backed Document Model** - Foundation for other features
2. **Gap 7: Document Processing Status Tracking** - Enables retry logic
3. **Gap 5: LLM-Based Query Rewriters** - Low effort, high value for retrieval quality
4. **Gap 1: Production Maintenance Utilities** - Essential for production operations

### Medium Priority (Enhanced Features)

5. **Gap 4: Chunk Ecto Schema with Vector Type** - Better data integrity
6. **Gap 3: Collection/Namespace Management** - Improves organization
7. **Gap 8: Unified Ingestion API** - Better developer experience
8. **Gap 6: File Parser with PDF Support** - Common use case

### Lower Priority (Nice-to-Have)

9. **Gap 9: Hybrid Search with RRF in Core Module** - Already available via strategies
10. **Gap 11: Ask/QA API with Context** - Partially exists in portfolio_manager
11. **Gap 12: Telemetry Spans** - Incremental improvement
12. **Gap 10: Collection-Filtered Search** - Similar to existing index_id
13. **Gap 13: Memory Vector Store Backend** - Testing convenience
14. **Gap 14: Configurable Embedder Resolution** - Different but equivalent approach

---

## Technical Dependencies

### Required for Document/Chunk Schemas

- **Ecto**: Already available in portfolio_index
- **Pgvector.Ecto**: Add `{:pgvector, "~> 0.3"}` to deps
- **Database migrations**: New tables for documents, collections, chunks

### Required for Parser

- **Poppler-utils**: System dependency for PDF parsing
- **External command execution**: Already using System.cmd in other areas

### Required for Memory Backend

- **HNSWLib**: `{:hnswlib, "~> 0.1"}` for in-memory vector search
- **GenServer**: For Memory process management

### Required for Query Rewriters

- **LLM Adapter**: Already available in portfolio_index
- **Protocol definition**: May want to extract Arcana.LLM protocol pattern

---

## Migration Path

### Phase 1: Schema Foundation

1. Add Pgvector.Ecto dependency
2. Create Document Ecto schema with status tracking
3. Create Collection Ecto schema
4. Create Chunk Ecto schema with vector type
5. Write database migrations

### Phase 2: Maintenance and Rewriters

1. Port Arcana.Maintenance functions
2. Implement query rewriters using existing LLM adapters
3. Add production maintenance documentation

### Phase 3: Parser and Ingestion

1. Port file parser with PDF support
2. Create unified ingestion API
3. Integrate status tracking with Broadway pipelines

### Phase 4: Search Enhancements

1. Add search mode option to base API
2. Implement collection-filtered search
3. Enhance telemetry coverage

---

## Recommendations

1. **Prioritize Document/Chunk Schemas**: These provide the foundation for maintenance, status tracking, and better data integrity.

2. **Add Query Rewriters Early**: Low implementation cost with significant retrieval quality improvements.

3. **Keep Broadway Pipelines**: Portfolio's async pipeline approach is better for large-scale operations; add simple API alongside, not instead of.

4. **Consider Hybrid Approach**: Use Ecto schemas for document/chunk management while keeping adapter pattern for embedder/vector store flexibility.

5. **Maintain Compatibility**: New features should be additive, not breaking changes to existing API.
