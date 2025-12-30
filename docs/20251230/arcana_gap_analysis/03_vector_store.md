# Vector Store System Gap Analysis

## Executive Summary

This document analyzes the vector store systems in Arcana and compares them against the Portfolio libraries (PortfolioCore and PortfolioIndex). The analysis identifies key architectural differences, missing features, and prioritized implementation gaps for RAG functionality.

---

## Arcana Vector Store Capabilities

### Architecture Overview

Arcana implements a **dispatch-based vector store** with a behaviour pattern that supports:

1. **Multiple Backend Support**
   - `:pgvector` - PostgreSQL with pgvector extension (default)
   - `:memory` - In-memory storage using HNSWLib
   - Custom modules implementing the `Arcana.VectorStore` behaviour

2. **Core Operations**
   - `store/5` - Store vectors with metadata
   - `search/3` - Semantic similarity search
   - `search_text/3` - Full-text search
   - `delete/3` - Remove vectors by ID
   - `clear/2` - Clear entire collections

3. **Backend Override Pattern**
   - Runtime backend switching via options
   - Per-call backend configuration: `vector_store: {:memory, pid: pid}`
   - Supports custom module backends

### Memory Backend Features (`Arcana.VectorStore.Memory`)

- **GenServer-based** in-memory store
- **HNSWLib integration** for approximate nearest neighbor (ANN) search
- **Cosine similarity** for semantic search
- **TF-IDF-like scoring** for text search
- **Soft deletion** via MapSet tracking
- **Collection isolation** - multiple collections per server
- **Max elements configuration** (default: 10,000)
- **Automatic dimension detection** on first vector

### Pgvector Backend Features (`Arcana.VectorStore.Pgvector`)

- **Ecto-based** PostgreSQL integration
- **Collection/Document/Chunk schema** integration
- **Full-text search** via PostgreSQL ts_rank
- **Cosine distance** (`<=>` operator)
- **Score threshold filtering**
- **Source ID filtering** for document-level queries
- **Auto document creation** for standalone vector storage

---

## Portfolio Libraries Current State

### PortfolioCore Port Specification (`PortfolioCore.Ports.VectorStore`)

A comprehensive **behaviour specification** with:

1. **Index Lifecycle Management**
   - `create_index/2` - Create index with configuration
   - `delete_index/1` - Remove index
   - `index_exists?/1` - Check existence
   - `index_stats/1` - Get statistics

2. **Vector Operations**
   - `store/4` - Single vector storage
   - `store_batch/2` - Batch vector storage
   - `search/4` - k-NN search with options
   - `delete/2` - Remove by ID
   - `fulltext_search/4` - Optional text search

3. **Rich Type Specifications**
   - Multiple distance metrics: `:cosine`, `:euclidean`, `:dot_product`
   - Index types: IVF, HNSW, Flat
   - Configurable index options
   - Search result includes optional vector return

### PortfolioCore Hybrid Behavior (`PortfolioCore.Ports.VectorStore.Hybrid`)

- Separate behaviour for hybrid search capability
- `hybrid_search/6` helper function
- Integrates with RRF scoring module

### PortfolioCore RRF Module (`PortfolioCore.VectorStore.RRF`)

- **Reciprocal Rank Fusion** implementation
- Configurable k parameter (default: 60)
- Separate weights for semantic/fulltext
- Result merging with vector preservation

### PortfolioIndex Pgvector Adapter (`PortfolioIndex.Adapters.VectorStore.Pgvector`)

1. **Dynamic Table Management**
   - Per-index table creation (`vectors_{index_id}`)
   - Index registry table for metadata
   - Support for IVFFlat and HNSW index types

2. **All Three Distance Metrics**
   - Cosine (`<=>`)
   - Euclidean (`<->`)
   - Dot Product (`<#>`)

3. **Advanced Features**
   - Metadata filtering in searches
   - Min score thresholds
   - Optional vector inclusion in results
   - Telemetry integration
   - Transaction-based batch operations

4. **Full-Text Search Module** (`Pgvector.FullText`)
   - tsvector-based PostgreSQL search
   - Language-aware stemming
   - Phrase matching support
   - GIN index creation

---

## Identified Gaps

### Gap 1: In-Memory Vector Store Adapter

- **Arcana Feature**: `Arcana.VectorStore.Memory` - GenServer-based in-memory store using HNSWLib for ANN search with soft deletion and collection management
- **Missing From**: PortfolioIndex (no memory adapter exists)
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Portfolio currently only has pgvector adapter
  - HNSWLib dependency would need to be added
  - Useful for testing, development, and small datasets
  - Should implement `PortfolioCore.Ports.VectorStore` behaviour
  - Consider adding index statistics tracking

### Gap 2: Collection-Based Organization

- **Arcana Feature**: First-class collection abstraction with `collection` parameter in all operations, allowing logical grouping without separate table management
- **Missing From**: PortfolioIndex (uses per-index tables)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana uses collection names mapped to collection_id
  - Portfolio uses index_id which maps to individual tables
  - Different architectural approaches - both valid
  - Portfolio approach may have better isolation
  - Could add collection abstraction layer on top of current approach

### Gap 3: Backend Override at Runtime

- **Arcana Feature**: Per-call backend switching via `vector_store: {:memory, pid: pid}` or `vector_store: {:pgvector, repo: MyRepo}` options
- **Missing From**: PortfolioCore/PortfolioIndex
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Arcana allows mixing backends in same application
  - Portfolio uses static adapter configuration
  - Useful for testing (use memory in tests, pgvector in prod)
  - Could add optional `:adapter` key to search/store options
  - Requires dispatcher module similar to Arcana's dispatch pattern

### Gap 4: Automatic Document/Collection Creation

- **Arcana Feature**: `Collection.get_or_create/2` and auto-document creation for standalone vector storage in pgvector backend
- **Missing From**: PortfolioIndex (requires explicit index creation)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana creates minimal documents when storing vectors without explicit document
  - Reduces boilerplate for simple use cases
  - Portfolio requires `create_index/2` before storing vectors
  - Could add auto-create option to `store/4`

### Gap 5: Soft Deletion in Memory Backend

- **Arcana Feature**: Memory backend uses MapSet for tracking deleted indices, avoiding index rebuilds
- **Missing From**: N/A (no memory backend in Portfolio)
- **Implementation Complexity**: Low (when implementing memory adapter)
- **Technical Details**:
  - HNSWLib doesn't support true deletion
  - Soft deletion allows marking as deleted without rebuild
  - Filter deleted entries in search results
  - Increases memory usage but improves performance

### Gap 6: Dimension Auto-Detection

- **Arcana Feature**: Memory backend auto-detects vector dimensions from first stored vector
- **Missing From**: PortfolioIndex (requires explicit dimension in config)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana: `ensure_dimensions/2` sets dims on first store
  - Portfolio: dimensions must be specified in `create_index/2`
  - Auto-detection simplifies API but can mask configuration errors
  - Consider optional auto-detect with explicit override

### Gap 7: Simple Text Search in Memory

- **Arcana Feature**: `search_text/4` in memory backend with TF-IDF-like scoring using tokenization
- **Missing From**: PortfolioIndex memory adapter (doesn't exist yet)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Simple term matching without database
  - Tokenization: lowercase, remove punctuation, split on whitespace
  - Score: `(matching_terms / query_terms) * length_normalization`
  - Useful for testing hybrid search without PostgreSQL

### Gap 8: Document-Level Filtering in Vector Search

- **Arcana Feature**: `source_id` filtering allows searching within specific document scope
- **Missing From**: PortfolioIndex (has metadata filtering but not document-level)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana: `Pgvector.search/3` accepts `:source_id` option
  - Portfolio: Uses generic metadata filter `{:filter, %{key: value}}`
  - Could add explicit document_id/source_id filter shorthand
  - Or document as convention in metadata

### Gap 9: Integrated Document/Chunk Schema

- **Arcana Feature**: Tight integration with `Arcana.Document` and `Arcana.Chunk` schemas, including document status tracking
- **Missing From**: PortfolioIndex (schema-agnostic approach)
- **Implementation Complexity**: High
- **Technical Details**:
  - Arcana stores chunks with document_id foreign key
  - Document has status (`:pending`, `:completed`)
  - Collection has associated documents
  - Portfolio uses standalone vector tables without document hierarchy
  - Different design philosophy - Portfolio favors flexibility

### Gap 10: Score Threshold in Search

- **Arcana Feature**: `threshold` option in pgvector search to filter low-similarity results
- **Missing From**: Partially exists - Portfolio has `:min_score` option
- **Implementation Complexity**: N/A (already implemented differently)
- **Technical Details**:
  - Arcana: `threshold: 0.0` - filter in WHERE clause
  - Portfolio: `:min_score` - same functionality
  - Naming difference only, no implementation gap

### Gap 11: Hybrid Search Convenience Function

- **Arcana Feature**: No built-in hybrid search - relies on caller to combine results
- **Missing From**: N/A - Portfolio has better implementation
- **Implementation Complexity**: N/A
- **Technical Details**:
  - Portfolio has `PortfolioCore.Ports.VectorStore.Hybrid.hybrid_search/6`
  - Portfolio has RRF scoring module
  - Arcana requires manual result merging
  - **Portfolio is ahead here**

### Gap 12: Euclidean and Dot Product Distance Metrics

- **Arcana Feature**: Only cosine similarity supported in search
- **Missing From**: N/A - Portfolio has better implementation
- **Implementation Complexity**: N/A
- **Technical Details**:
  - Arcana pgvector uses only `<=>` (cosine)
  - Arcana memory uses only `:cosine` in HNSWLib
  - Portfolio supports all three: cosine, euclidean, dot_product
  - **Portfolio is ahead here**

### Gap 13: Index Statistics

- **Arcana Feature**: No index statistics API
- **Missing From**: N/A - Portfolio has this
- **Implementation Complexity**: N/A
- **Technical Details**:
  - Portfolio: `index_stats/1` returns count, dimensions, metric, size_bytes
  - Arcana has no equivalent
  - **Portfolio is ahead here**

### Gap 14: Batch Store Operations

- **Arcana Feature**: No batch store API - only single vector store
- **Missing From**: N/A - Portfolio has this
- **Implementation Complexity**: N/A
- **Technical Details**:
  - Portfolio: `store_batch/2` with transaction support
  - Arcana requires loop of individual `store/5` calls
  - **Portfolio is ahead here**

### Gap 15: Max Elements Configuration (Memory)

- **Arcana Feature**: Configurable `max_elements` for HNSWLib index (default: 10,000)
- **Missing From**: PortfolioIndex (no memory adapter)
- **Implementation Complexity**: Low (when implementing memory adapter)
- **Technical Details**:
  - HNSWLib requires max elements at index creation
  - Arcana passes this via GenServer options
  - Portfolio memory adapter should include this configuration

---

## Implementation Priority

### Priority 1 - High Value, Low Effort

1. **Backend Override at Runtime** (Gap 3)
   - Enable testing with memory backend
   - Production flexibility
   - Estimated: 2-3 hours

2. **Auto Index/Collection Creation** (Gap 4)
   - Reduce boilerplate
   - Better developer experience
   - Estimated: 1-2 hours

### Priority 2 - High Value, Medium Effort

3. **In-Memory Vector Store Adapter** (Gaps 1, 5, 7, 15)
   - Testing without PostgreSQL
   - Development workflows
   - Small dataset optimization
   - Estimated: 4-6 hours

4. **Document-Level Filtering** (Gap 8)
   - Scoped searches
   - Multi-tenant use cases
   - Estimated: 1-2 hours

### Priority 3 - Medium Value, Low Effort

5. **Dimension Auto-Detection** (Gap 6)
   - Convenience feature
   - Can be optional
   - Estimated: 1 hour

### Priority 4 - Low Priority

6. **Collection Abstraction** (Gap 2)
   - Different design philosophy
   - Current approach is valid
   - Consider only if specific need arises

7. **Integrated Document Schema** (Gap 9)
   - Major architectural change
   - Portfolio's flexible approach may be preferred
   - Consider domain-specific wrappers instead

---

## Technical Dependencies

### For In-Memory Adapter (Priority 2)

```elixir
# mix.exs
{:hnswlib, "~> 0.1", optional: true}
{:nx, "~> 0.7"}  # Already likely present
```

### For Backend Override (Priority 1)

- No new dependencies
- Requires dispatcher pattern in PortfolioIndex
- Update `search/4` and `store/4` signatures

### For Auto-Creation (Priority 1)

- No new dependencies
- Add `get_or_create_index/2` helper
- Update `store/4` to optionally auto-create

---

## Portfolio Advantages Over Arcana

The following features exist in Portfolio but not in Arcana:

1. **Multiple Distance Metrics** - Cosine, Euclidean, Dot Product
2. **Index Type Configuration** - IVFFlat, HNSW, Flat
3. **Batch Operations** - `store_batch/2` for efficient bulk ingestion
4. **Index Statistics** - `index_stats/1` for monitoring
5. **Index Lifecycle** - `create_index/2`, `delete_index/1`, `index_exists?/1`
6. **RRF Hybrid Search** - Built-in RRF scoring with configurable weights
7. **Hybrid Behaviour** - Separate behaviour for hybrid-capable stores
8. **Advanced Full-Text** - Phrase matching, language support, GIN indices
9. **Telemetry Integration** - Performance monitoring out of the box
10. **Dynamic Table Management** - Per-index tables with registry

---

## Summary

The Portfolio libraries have a more mature and feature-rich vector store implementation compared to Arcana. The primary gaps are:

1. **In-memory adapter** for testing and development
2. **Runtime backend switching** for flexibility
3. **Convenience features** like auto-creation and dimension detection

The recommended approach is to implement the in-memory adapter and backend switching pattern from Arcana while preserving Portfolio's superior features in distance metrics, batch operations, and hybrid search.
