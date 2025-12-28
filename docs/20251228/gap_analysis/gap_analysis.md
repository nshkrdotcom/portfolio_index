# Gap Analysis: portfolio_index Adapters vs rag_ex Implementations

**Date**: December 28, 2025
**Comparison**: rag_ex feature inventory vs portfolio_index v0.2.0 adapters
**Purpose**: Identify missing implementations and enhancement opportunities

---

## Executive Summary

This document provides a comprehensive function-by-function comparison of portfolio_index adapters against rag_ex implementations. The analysis identifies **23 significant gaps** across 8 adapter categories, with critical deficiencies in chunking strategies, retriever modes, reranking, and GraphRAG components.

### Gap Severity Legend

| Severity | Description |
|----------|-------------|
| **Critical** | Core functionality missing that limits practical use |
| **High** | Important features affecting quality or flexibility |
| **Medium** | Nice-to-have features that improve developer experience |
| **Low** | Edge cases or specialized functionality |

---

## Summary Matrix

| Adapter Category | rag_ex Features | portfolio_index Has | Gap Count | Severity |
|------------------|-----------------|---------------------|-----------|----------|
| Chunker Adapters | 6 types | 1 type | 5 | **Critical** |
| Retriever Types | 4 modes | 2 modes | 2 | **High** |
| Reranker | 2 types | 0 | 2 | **High** |
| VectorStore | 8 functions | 6 functions | 2 | Medium |
| GraphStore | 12 functions | 9 functions | 3 | **High** |
| GraphRAG Components | 3 components | 0 | 3 | **Critical** |
| Embedding Service | 3 features | 1 feature | 2 | Medium |
| Pipeline Features | 5 features | 3 features | 2 | Medium |
| **TOTAL** | - | - | **21** | - |

---

## 1. CHUNKER ADAPTERS (Critical Gap)

### 1.1 Current State: portfolio_index

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/chunker/recursive.ex`

| Function | Status | Notes |
|----------|--------|-------|
| `chunk/3` | Present | Format-aware recursive splitting |
| `estimate_chunks/2` | Present | Chunk count estimation |

**Formats Supported**: `:plain`, `:markdown`, `:code`, `:html`

### 1.2 rag_ex Implementations (6 Types)

#### 1.2.1 Character Chunker
```elixir
# rag_ex: Rag.Chunker.Character
defmodule Rag.Chunker.Character do
  def chunk(text, opts) do
    chunk_size = opts[:chunk_size] || 1000
    overlap = opts[:chunk_overlap] || 200
    boundary = opts[:boundary] || :word  # :word | :sentence | :none

    # Split at character boundaries with smart word/sentence preservation
  end
end
```

**Gap**: portfolio_index lacks standalone character chunker with boundary awareness.

#### 1.2.2 Sentence Chunker
```elixir
# rag_ex: Rag.Chunker.Sentence
defmodule Rag.Chunker.Sentence do
  def chunk(text, opts) do
    # Uses NLP tokenizer to split on sentence boundaries
    # Groups sentences to reach target chunk size
    # Tracks byte positions for each chunk
  end
end
```

**Functions Missing in portfolio_index**:
- Sentence boundary detection using NLP tokenization
- Byte position tracking (`start_byte`, `end_byte` per chunk)

#### 1.2.3 Paragraph Chunker
```elixir
# rag_ex: Rag.Chunker.Paragraph
defmodule Rag.Chunker.Paragraph do
  def chunk(text, opts) do
    # Splits on paragraph boundaries (\n\n)
    # Merges small paragraphs
    # Splits large paragraphs at sentence boundaries
  end
end
```

**Gap**: portfolio_index handles paragraph splitting within recursive chunker but lacks standalone implementation.

#### 1.2.4 Recursive Chunker (PRESENT in portfolio_index)
```elixir
# Both rag_ex and portfolio_index have this
# portfolio_index implementation is comprehensive
```

**Status**: Implemented - formats `:plain`, `:markdown`, `:code`, `:html`

#### 1.2.5 Semantic Chunker (CRITICAL GAP)
```elixir
# rag_ex: Rag.Chunker.Semantic
defmodule Rag.Chunker.Semantic do
  def chunk(text, opts) do
    embedding_fn = opts[:embedding_fn]
    threshold = opts[:similarity_threshold] || 0.75
    max_chars = opts[:max_chunk_chars] || 1000

    sentences = split_sentences(text)
    embeddings = Enum.map(sentences, embedding_fn)

    # Group by cosine similarity
    # Start new chunk when similarity drops below threshold
    # Returns chunks with start_offset, end_offset, byte positions
  end

  defp cosine_similarity(vec1, vec2) do
    dot = Enum.zip(vec1, vec2) |> Enum.reduce(0, fn {a, b}, acc -> acc + a * b end)
    mag1 = :math.sqrt(Enum.reduce(vec1, 0, fn x, acc -> acc + x * x end))
    mag2 = :math.sqrt(Enum.reduce(vec2, 0, fn x, acc -> acc + x * x end))
    dot / (mag1 * mag2)
  end
end
```

**Gap Details**:
| Feature | rag_ex | portfolio_index |
|---------|--------|-----------------|
| Embedding-based grouping | Yes | No |
| Cosine similarity threshold | Yes | No |
| Sentence-level granularity | Yes | No |
| Dynamic chunk boundaries | Yes | No |

#### 1.2.6 Format-Aware Chunker
```elixir
# rag_ex: Rag.Chunker.FormatAware
defmodule Rag.Chunker.FormatAware do
  def chunk(text, opts) do
    format = opts[:format] || :auto

    case detect_format(text, format) do
      :markdown -> chunk_markdown(text, opts)
      :code -> chunk_code(text, opts)
      :json -> chunk_json(text, opts)
      _ -> chunk_plain(text, opts)
    end
  end

  defp chunk_markdown(text, opts) do
    # Preserve headers, code blocks, lists
    # Never split within fenced code blocks
    # Respect heading hierarchy
  end

  defp chunk_code(text, opts) do
    # Language-specific splitting
    # Preserve function/class boundaries
    # Keep imports with related code
  end
end
```

**Gap**: portfolio_index recursive chunker has format awareness but lacks:
- JSON-aware chunking
- Language detection
- Never-split zones for code blocks

### 1.3 Chunker Gap Summary

| Chunker Type | Status | Priority | LOC Estimate |
|--------------|--------|----------|--------------|
| Semantic | **MISSING** | Critical | 150 |
| Sentence | **MISSING** | High | 80 |
| Paragraph | **MISSING** | Medium | 60 |
| Character | **MISSING** | Medium | 50 |
| Format-Aware Enhancements | Partial | High | 100 |

---

## 2. RETRIEVER ADAPTERS (High Gap)

### 2.1 Current State: portfolio_index

**Files**:
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/hybrid.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/graph_rag.ex`

| Retriever | Status | Notes |
|-----------|--------|-------|
| Semantic (Vector) | Present | Via VectorStore.search |
| FullText (Keyword) | Present | Via VectorStore keyword mode |
| Hybrid (RRF) | Present | Complete RRF implementation |
| Graph | Partial | Basic entity traversal only |

### 2.2 rag_ex Implementations

#### 2.2.1 Semantic Retriever
```elixir
# rag_ex: Rag.Retriever.Semantic
defmodule Rag.Retriever.Semantic do
  def retrieve(query, opts) do
    index_id = opts[:index_id]
    k = opts[:k] || 10

    # Generate query embedding
    # Search with L2 distance in pgvector
    # Score = 1.0 - distance (normalized to 0-1)
    # Apply optional metadata filters
  end
end
```

**Status**: Implemented in portfolio_index via Hybrid strategy.

#### 2.2.2 FullText Retriever
```elixir
# rag_ex: Rag.Retriever.FullText
defmodule Rag.Retriever.FullText do
  def retrieve(query, opts) do
    # Uses PostgreSQL tsvector for full-text search
    # ts_rank for scoring
    # Supports language configuration
    # Supports phrase matching
  end

  def build_query(query, opts) do
    """
    SELECT id, content, ts_rank(tsv, query) as score
    FROM chunks, to_tsquery($1) query
    WHERE tsv @@ query
    ORDER BY score DESC
    LIMIT $2
    """
  end
end
```

**Gap**: portfolio_index uses ILIKE for keyword search, not proper tsvector full-text search.

#### 2.2.3 Hybrid Retriever
```elixir
# rag_ex: Rag.Retriever.Hybrid
defmodule Rag.Retriever.Hybrid do
  @rrf_k 60  # RRF constant

  def retrieve(query, opts) do
    semantic_results = Semantic.retrieve(query, opts)
    fulltext_results = FullText.retrieve(query, opts)

    calculate_rrf_score([semantic_results, fulltext_results])
  end

  def calculate_rrf_score(result_lists) do
    # RRF: 1/(k + rank) where k = 60
    # Sum scores across lists for each document
    # Return sorted by combined RRF score
  end
end
```

**Status**: Implemented in portfolio_index (`Hybrid.reciprocal_rank_fusion/2`).

#### 2.2.4 Graph Retriever (HIGH GAP)
```elixir
# rag_ex: Rag.Retriever.Graph
defmodule Rag.Retriever.Graph do
  @modes [:local, :global, :hybrid]

  def retrieve(query, opts) do
    mode = opts[:mode] || :hybrid

    case mode do
      :local -> local_search(query, opts)
      :global -> global_search(query, opts)
      :hybrid -> hybrid_search(query, opts)
    end
  end

  def local_search(query, opts) do
    # 1. Extract entities from query using LLM
    # 2. Find matching entities in graph (vector search on entity embeddings)
    # 3. BFS traversal to depth N
    # 4. Collect and score related entities/edges
    # 5. Format as context
  end

  def global_search(query, opts) do
    # 1. Generate query embedding
    # 2. Search community summaries (vector search)
    # 3. Retrieve top-k communities
    # 4. Return community descriptions as context
  end

  def hybrid_search(query, opts) do
    local = local_search(query, opts)
    global = global_search(query, opts)
    merge_results(local, global, opts[:weights])
  end
end
```

**Gap Details**:
| Feature | rag_ex | portfolio_index |
|---------|--------|-----------------|
| Local mode (entity traversal) | Yes | Partial |
| Global mode (community search) | Yes | **No** |
| Hybrid mode | Yes | **No** |
| Entity embedding search | Yes | **No** |
| BFS traversal depth control | Yes | **No** |
| Community summaries | Yes | **No** |

### 2.3 Retriever Gap Summary

| Feature | Status | Priority |
|---------|--------|----------|
| tsvector FullText search | **MISSING** | High |
| Graph local mode with entity vectors | Partial | High |
| Graph global mode (communities) | **MISSING** | Critical |
| Graph hybrid mode | **MISSING** | High |

---

## 3. RERANKER ADAPTERS (High Gap)

### 3.1 Current State: portfolio_index

**Status**: No reranker implementations exist. PortfolioCore.Ports.Reranker behavior is defined but not implemented.

### 3.2 rag_ex Implementations

#### 3.2.1 LLM Reranker
```elixir
# rag_ex: Rag.Reranker.LLM
defmodule Rag.Reranker.LLM do
  @prompt_template """
  Rank these documents by relevance to the query.
  Query: {query}

  Documents:
  {documents}

  Return JSON array: [{"index": 0, "score": 8}, ...]
  Score 1-10 where 10 = most relevant.
  """

  def rerank(query, documents, opts) do
    prompt = build_prompt(query, documents)

    case llm.complete(prompt, opts) do
      {:ok, %{content: json}} ->
        scores = parse_scores(json)
        reorder_documents(documents, scores)
      error -> error
    end
  end

  defp parse_scores(json) do
    # Extract index -> score mapping
    # Handle malformed JSON gracefully
  end
end
```

#### 3.2.2 Passthrough Reranker
```elixir
# rag_ex: Rag.Reranker.Passthrough
defmodule Rag.Reranker.Passthrough do
  def rerank(_query, documents, _opts) do
    {:ok, documents}  # No-op for testing
  end
end
```

### 3.3 Reranker Gap Summary

| Reranker Type | Status | Priority | LOC Estimate |
|---------------|--------|----------|--------------|
| LLM Reranker | **MISSING** | High | 120 |
| Passthrough Reranker | **MISSING** | Low | 20 |
| Cross-Encoder Reranker | **MISSING** | Medium | 80 |

---

## 4. VECTOR STORE ADAPTER (Medium Gap)

### 4.1 Current State: portfolio_index

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/vector_store/pgvector.ex`

| Function | Status | Notes |
|----------|--------|-------|
| `create_index/2` | Present | With HNSW/IVFFlat options |
| `delete_index/1` | Present | |
| `store/4` | Present | Single vector storage |
| `store_batch/2` | Present | Batch storage |
| `search/4` | Present | Vector + keyword modes |
| `delete/2` | Present | |
| `index_stats/1` | Present | |
| `index_exists?/1` | Present | |

### 4.2 rag_ex Additional Functions

```elixir
# rag_ex: Rag.VectorStore.Pgvector
defmodule Rag.VectorStore.Pgvector do
  # Functions present in portfolio_index
  def create_index/2, def delete_index/1, def store/4, etc.

  # ADDITIONAL FUNCTIONS (GAPS):

  def build_chunk(content, embedding, metadata) do
    %Chunk{
      content: content,
      embedding: embedding,
      metadata: metadata,
      byte_start: metadata[:byte_start],
      byte_end: metadata[:byte_end]
    }
  end

  def build_chunks(contents, embeddings, metadatas) do
    # Batch chunk building with validation
  end

  def from_chunker_chunks(chunks, embeddings) do
    # Convert chunker output to storable format
    # Preserves byte positions, metadata
  end

  def add_embeddings(chunks, embeddings) do
    # Merge embeddings into chunk structs
  end

  def prepare_for_insert(chunks) do
    # Validate and format for batch insert
    # Generates IDs if missing
  end

  def semantic_search_query(query_vector, k, opts) do
    # Returns Ecto query for composability
    # Supports joins, additional filters
  end

  def fulltext_search_query(query_text, k, opts) do
    # Returns Ecto query using tsvector
    # Supports phrase matching
  end

  def calculate_rrf_score(semantic_results, fulltext_results, k \\ 60) do
    # Standalone RRF calculation
  end
end
```

### 4.3 VectorStore Gap Summary

| Function | Status | Priority |
|----------|--------|----------|
| `build_chunk/3` | **MISSING** | Medium |
| `build_chunks/3` | **MISSING** | Medium |
| `from_chunker_chunks/2` | **MISSING** | Medium |
| `add_embeddings/2` | **MISSING** | Medium |
| `prepare_for_insert/1` | **MISSING** | Low |
| `semantic_search_query/3` | **MISSING** | Low |
| `fulltext_search_query/3` | **MISSING** | High |
| `calculate_rrf_score/3` | Present | In Hybrid strategy |

---

## 5. GRAPH STORE ADAPTER (High Gap)

### 5.1 Current State: portfolio_index

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/graph_store/neo4j.ex`

| Function | Status | Notes |
|----------|--------|-------|
| `create_graph/2` | Present | Graph namespace creation |
| `delete_graph/1` | Present | |
| `create_node/2` | Present | |
| `create_edge/2` | Present | |
| `get_node/2` | Present | |
| `get_neighbors/3` | Present | With direction, edge_types, limit |
| `query/3` | Present | Custom Cypher queries |
| `delete_node/2` | Present | |
| `delete_edge/2` | Present | |
| `graph_stats/1` | Present | Node/edge counts |

### 5.2 rag_ex Pgvector GraphStore Functions (GAPS)

```elixir
# rag_ex: Rag.GraphStore.Pgvector
defmodule Rag.GraphStore.Pgvector do
  # Entity operations with vectors
  def create_entity(graph_id, entity) do
    %{
      name: entity.name,
      type: entity.type,
      description: entity.description,
      embedding: entity.embedding,  # Vector for semantic search
      properties: entity.properties
    }
  end

  def search_entities_by_vector(graph_id, query_vector, k, opts) do
    # Vector similarity search on entity embeddings
    # Returns entities sorted by distance
  end

  # Community operations (CRITICAL GAP)
  def create_community(graph_id, community) do
    %{
      id: community.id,
      level: community.level,
      members: community.member_ids,
      summary: community.summary,
      embedding: community.embedding  # For global search
    }
  end

  def list_communities(graph_id, opts) do
    # List all communities at a given level
  end

  def get_community_members(graph_id, community_id) do
    # Get all entities in a community
  end

  def search_communities_by_vector(graph_id, query_vector, k) do
    # Global search: find relevant communities
  end

  # Traversal operations
  def traverse_bfs(graph_id, start_node_id, depth, opts) do
    # Breadth-first traversal with depth limit
    # Uses recursive CTE in PostgreSQL
    """
    WITH RECURSIVE traverse AS (
      SELECT id, 0 as depth FROM entities WHERE id = $1
      UNION ALL
      SELECT e.target_id, t.depth + 1
      FROM edges e
      JOIN traverse t ON e.source_id = t.id
      WHERE t.depth < $2
    )
    SELECT DISTINCT * FROM traverse
    """
  end

  def get_subgraph(graph_id, node_ids) do
    # Get all nodes and edges within a set of node IDs
  end
end
```

### 5.3 GraphStore Gap Summary

| Function | Status | Priority |
|----------|--------|----------|
| `search_entities_by_vector/4` | **MISSING** | Critical |
| `create_community/2` | **MISSING** | Critical |
| `list_communities/2` | **MISSING** | High |
| `get_community_members/2` | **MISSING** | High |
| `search_communities_by_vector/3` | **MISSING** | Critical |
| `traverse_bfs/4` | **MISSING** | High |
| `get_subgraph/2` | **MISSING** | Medium |

---

## 6. GRAPHRAG COMPONENTS (Critical Gap)

### 6.1 Current State: portfolio_index

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/graph_rag.ex`

| Component | Status | Notes |
|-----------|--------|-------|
| Entity extraction | Partial | Basic LLM extraction in strategy |
| Relationship extraction | Partial | Via entity extraction |
| Community detection | **MISSING** | No implementation |
| Community summarization | **MISSING** | No implementation |
| Global search | **MISSING** | No implementation |

### 6.2 rag_ex GraphRAG Components

#### 6.2.1 Entity Extractor
```elixir
# rag_ex: Rag.GraphRAG.Extractor
defmodule Rag.GraphRAG.Extractor do
  @extraction_prompt """
  Extract entities and relationships from this text.

  Text: {text}

  Return JSON:
  {
    "entities": [
      {"name": "...", "type": "...", "description": "..."}
    ],
    "relationships": [
      {"source": "...", "target": "...", "type": "...", "description": "..."}
    ]
  }
  """

  def extract(text, opts) do
    # Call LLM with extraction prompt
    # Parse JSON response
    # Validate entity/relationship structure
    # Return normalized results
  end

  def extract_batch(texts, opts) do
    # Parallel extraction with rate limiting
  end
end
```

**Gap**: portfolio_index has basic extraction in GraphRAG strategy but lacks:
- Batch extraction
- Entity deduplication/resolution
- Relationship validation

#### 6.2.2 Community Detector
```elixir
# rag_ex: Rag.GraphRAG.CommunityDetector
defmodule Rag.GraphRAG.CommunityDetector do
  @max_iterations 100

  def detect(graph_store, graph_id, opts) do
    max_iter = opts[:max_iterations] || @max_iterations

    entities = graph_store.list_entities(graph_id)
    edges = graph_store.list_edges(graph_id)

    # Label propagation algorithm
    labels = initialize_labels(entities)

    Enum.reduce_while(1..max_iter, labels, fn iter, current_labels ->
      new_labels = propagate_labels(current_labels, edges)

      if labels_converged?(current_labels, new_labels) do
        {:halt, new_labels}
      else
        {:cont, new_labels}
      end
    end)
    |> group_by_label()
  end

  defp propagate_labels(labels, edges) do
    # For each node, adopt most common neighbor label
    Enum.map(labels, fn {node_id, _label} ->
      neighbor_labels = get_neighbor_labels(node_id, edges, labels)
      most_common = most_common_label(neighbor_labels)
      {node_id, most_common}
    end)
    |> Map.new()
  end

  def detect_hierarchical(graph_store, graph_id, levels, opts) do
    # Level 0: initial communities
    # Level 1+: merge adjacent communities
    # Returns multi-level hierarchy
  end
end
```

**Gap**: Completely missing in portfolio_index.

#### 6.2.3 Community Summarizer
```elixir
# rag_ex: Rag.GraphRAG.Summarizer
defmodule Rag.GraphRAG.Summarizer do
  @summary_prompt """
  Summarize this community of related entities.

  Community members:
  {members}

  Relationships:
  {relationships}

  Provide a concise summary (2-3 sentences) describing:
  1. What this community represents
  2. Key themes or concepts
  3. How members relate to each other
  """

  def summarize(community, graph_store, graph_id, opts) do
    members = graph_store.get_community_members(graph_id, community.id)
    relationships = get_internal_relationships(members, graph_store, graph_id)

    prompt = build_prompt(members, relationships)
    {:ok, %{content: summary}} = llm.complete(prompt, opts)

    %{community | summary: summary}
  end

  def summarize_all(communities, graph_store, graph_id, opts) do
    # Parallel summarization with rate limiting
  end
end
```

**Gap**: Completely missing in portfolio_index.

### 6.3 GraphRAG Component Gap Summary

| Component | Status | Priority | LOC Estimate |
|-----------|--------|----------|--------------|
| Entity Extractor (batch) | Partial | High | 100 |
| Entity Resolution | **MISSING** | High | 80 |
| Community Detector | **MISSING** | Critical | 150 |
| Hierarchical Communities | **MISSING** | High | 100 |
| Community Summarizer | **MISSING** | Critical | 80 |

---

## 7. EMBEDDING SERVICE (Medium Gap)

### 7.1 Current State: portfolio_index

**Files**:
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/gemini.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/open_ai.ex`

| Feature | Status | Notes |
|---------|--------|-------|
| Single embedding | Present | `embed/2` |
| Batch embedding | Present | `embed_batch/2` (sequential) |
| Dimensions query | Present | `dimensions/1` |
| Model list | Present | `supported_models/0` |

### 7.2 rag_ex Embedding Service

```elixir
# rag_ex: Rag.Embedding.Service
defmodule Rag.Embedding.Service do
  use GenServer

  @batch_timeout 50  # ms
  @max_batch_size 100

  def embed_text(text), do: GenServer.call(__MODULE__, {:embed, text})

  def embed_texts(texts), do: GenServer.call(__MODULE__, {:embed_batch, texts})

  # Auto-batching: accumulate requests, flush on timeout or size
  def handle_call({:embed, text}, from, state) do
    new_state = add_to_batch(state, text, from)
    maybe_flush_batch(new_state)
  end

  # Provider limits respected
  def handle_info(:flush_batch, state) do
    {texts, froms} = get_batch(state)
    results = call_provider_batch(texts, state.provider_limit)
    reply_all(froms, results)
    {:noreply, clear_batch(state)}
  end

  # Telemetry integration
  def call_provider_batch(texts, limit) do
    texts
    |> Enum.chunk_every(limit)
    |> Enum.flat_map(fn chunk ->
      :telemetry.span([:embedding, :batch], %{count: length(chunk)}, fn ->
        {provider.embed_batch(chunk), %{}}
      end)
    end)
  end
end
```

### 7.3 Embedding Service Gap Summary

| Feature | Status | Priority |
|---------|--------|----------|
| Auto-batching GenServer | **MISSING** | Medium |
| Provider rate limit handling | Partial | Medium (Hammer used in pipeline) |
| Telemetry integration | Present | |

---

## 8. PIPELINE FEATURES (Medium Gap)

### 8.1 Current State: portfolio_index

**Files**:
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/pipelines/ingestion.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/pipelines/embedding.ex`

| Feature | Status | Notes |
|---------|--------|-------|
| Broadway integration | Present | Ingestion + Embedding pipelines |
| ETS queue | Present | ETSProducer for internal queuing |
| Rate limiting | Present | Hammer integration |
| Batch processing | Present | Configurable batch sizes |
| Telemetry | Present | Pipeline events emitted |

### 8.2 rag_ex Pipeline Features

```elixir
# rag_ex: Rag.Pipeline.Executor
defmodule Rag.Pipeline.Executor do
  def execute(pipeline, context, opts) do
    steps = pipeline.steps

    # Parallel execution of independent steps
    parallel_groups = group_by_dependencies(steps)

    Enum.reduce(parallel_groups, context, fn group, ctx ->
      group
      |> Task.async_stream(&execute_step(&1, ctx))
      |> merge_results(ctx)
    end)
  end

  def execute_step(step, context) do
    cache_key = build_cache_key(step, context)

    case get_cached(cache_key) do
      {:ok, cached} -> cached
      :miss ->
        result = run_with_retry(step, context)
        cache_result(cache_key, result)
        result
    end
  end

  defp run_with_retry(step, context, attempt \\ 1) do
    case step.execute.(context) do
      {:ok, result} -> {:ok, result}
      {:error, reason} when attempt < step.max_retries ->
        Process.sleep(backoff(attempt))
        run_with_retry(step, context, attempt + 1)
      error -> error
    end
  end
end

# rag_ex: Rag.Pipeline.Context
defmodule Rag.Pipeline.Context do
  defstruct [
    :query,
    :query_embedding,
    :retrieval_results,
    :reranked_results,
    :context_text,
    :response,
    :evaluations,
    :errors,
    halted?: false
  ]

  def put(ctx, key, value), do: Map.put(ctx, key, value)
  def get(ctx, key), do: Map.get(ctx, key)
  def halt(ctx, reason), do: %{ctx | halted?: true, errors: [reason | ctx.errors]}
end
```

### 8.3 Pipeline Gap Summary

| Feature | Status | Priority |
|---------|--------|----------|
| Parallel step execution | Partial | Medium |
| Step retry with backoff | **MISSING** | Medium |
| Pipeline Context struct | **MISSING** | Low |
| Step caching | Present | ETS-based |
| Dependency resolution | **MISSING** | Low |

---

## 9. IMPLEMENTATION PRIORITY MATRIX

### 9.1 Critical Priority (Weeks 1-2)

| Item | Effort | Impact | Notes |
|------|--------|--------|-------|
| Semantic Chunker | 3 days | High | Improves retrieval quality significantly |
| Community Detection | 3 days | High | Enables global GraphRAG search |
| Community Summarization | 2 days | High | Required for global search |
| Graph Entity Vector Search | 2 days | High | Required for local GraphRAG |

### 9.2 High Priority (Weeks 3-4)

| Item | Effort | Impact | Notes |
|------|--------|--------|-------|
| LLM Reranker | 2 days | High | Major retrieval quality improvement |
| Graph Global Mode | 2 days | High | Community-based search |
| Sentence Chunker | 1 day | Medium | Baseline chunking option |
| tsvector FullText | 2 days | Medium | Proper PostgreSQL full-text search |

### 9.3 Medium Priority (Weeks 5-6)

| Item | Effort | Impact | Notes |
|------|--------|--------|-------|
| Paragraph Chunker | 1 day | Medium | Document structure preservation |
| Character Chunker | 1 day | Medium | Predictable chunk sizes |
| Embedding Service (batching) | 2 days | Medium | Cost optimization |
| Pipeline Context struct | 1 day | Medium | Better debugging |
| BFS Traversal function | 1 day | Medium | Graph exploration |

### 9.4 Low Priority (As Needed)

| Item | Effort | Impact | Notes |
|------|--------|--------|-------|
| Passthrough Reranker | 0.5 day | Low | Testing utility |
| Pipeline retry with backoff | 1 day | Low | Resilience improvement |
| Cross-Encoder Reranker | 3 days | Medium | If LLM reranker insufficient |

---

## 10. RECOMMENDED IMPLEMENTATION ORDER

1. **Semantic Chunker** - Foundation for quality retrieval
2. **Community Detection** - Core GraphRAG capability
3. **Community Summarization** - Enables global search
4. **Graph Entity Vector Search** - Local mode enhancement
5. **LLM Reranker** - Result quality improvement
6. **Sentence Chunker** - Additional chunking flexibility
7. **Full-text Search (tsvector)** - Proper keyword search
8. **Remaining chunkers** - Complete chunking suite

---

## Appendix A: File Locations for Reference

### portfolio_index Adapter Files

| Adapter | Path |
|---------|------|
| Chunker (Recursive) | `lib/portfolio_index/adapters/chunker/recursive.ex` |
| VectorStore (Pgvector) | `lib/portfolio_index/adapters/vector_store/pgvector.ex` |
| GraphStore (Neo4j) | `lib/portfolio_index/adapters/graph_store/neo4j.ex` |
| Embedder (Gemini) | `lib/portfolio_index/adapters/embedder/gemini.ex` |
| Embedder (OpenAI) | `lib/portfolio_index/adapters/embedder/open_ai.ex` |
| LLM (Gemini) | `lib/portfolio_index/adapters/llm/gemini.ex` |
| LLM (Anthropic) | `lib/portfolio_index/adapters/llm/anthropic.ex` |
| LLM (OpenAI) | `lib/portfolio_index/adapters/llm/open_ai.ex` |
| DocumentStore (Postgres) | `lib/portfolio_index/adapters/document_store/postgres.ex` |

### portfolio_index RAG Strategy Files

| Strategy | Path |
|----------|------|
| Strategy Behaviour | `lib/portfolio_index/rag/strategy.ex` |
| Hybrid | `lib/portfolio_index/rag/strategies/hybrid.ex` |
| GraphRAG | `lib/portfolio_index/rag/strategies/graph_rag.ex` |
| SelfRAG | `lib/portfolio_index/rag/strategies/self_rag.ex` |
| Agentic | `lib/portfolio_index/rag/strategies/agentic.ex` |
| AdapterResolver | `lib/portfolio_index/rag/adapter_resolver.ex` |

### portfolio_index Pipeline Files

| Pipeline | Path |
|----------|------|
| Ingestion | `lib/portfolio_index/pipelines/ingestion.ex` |
| Embedding | `lib/portfolio_index/pipelines/embedding.ex` |
| FileProducer | `lib/portfolio_index/pipelines/producers/file_producer.ex` |
| ETSProducer | `lib/portfolio_index/pipelines/producers/ets_producer.ex` |
