# Implementation Prompt: portfolio_index v0.3.0

**Date**: December 28, 2025
**Target Version**: 0.3.0
**Focus**: Close rag_ex feature gaps with comprehensive adapter implementations

---

## REQUIRED READING

Before implementing, read and understand these files:

### Gap Analysis
- `/home/home/p/g/n/portfolio_index/docs/20251228/gap_analysis/gap_analysis.md`

### Current Adapter Implementations
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/chunker/recursive.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/vector_store/pgvector.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/graph_store/neo4j.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/graph_store/neo4j/schema.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/gemini.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/embedder/open_ai.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/llm/gemini.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/llm/anthropic.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/llm/open_ai.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/document_store/postgres.ex`

### RAG Strategy Implementations
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategy.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/hybrid.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/graph_rag.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/self_rag.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/agentic.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/adapter_resolver.ex`

### Pipeline Implementations
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/pipelines/ingestion.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/pipelines/embedding.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/pipelines/producers/file_producer.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/pipelines/producers/ets_producer.ex`

### Core Application Files
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/application.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/repo.ex`
- `/home/home/p/g/n/portfolio_index/lib/portfolio_index/telemetry.ex`
- `/home/home/p/g/n/portfolio_index/mix.exs`
- `/home/home/p/g/n/portfolio_index/README.md`

### PortfolioCore Port Definitions
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/chunker.ex`
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/embedder.ex`
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/vector_store.ex`
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/graph_store.ex`
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/reranker.ex`
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/llm.ex`

### Architecture Context
- `/home/home/p/g/n/portfolio_manager/docs/20251226/ecosystem design docs/01_rag_ex_review.md`
- `/home/home/p/g/n/portfolio_manager/docs/20251228/architecture-overview/gap-analysis.md`

---

## CONTEXT

### Current State (v0.2.0)

portfolio_index provides production adapters for the PortfolioCore hexagonal architecture:
- Vector Store: Pgvector (PostgreSQL + pgvector)
- Graph Store: Neo4j via boltx
- Embedders: Google Gemini (OpenAI placeholder)
- LLMs: Gemini, Anthropic Claude, OpenAI GPT
- Chunker: Recursive (format-aware)
- RAG Strategies: Hybrid, SelfRAG, GraphRAG, Agentic
- Pipelines: Broadway-based ingestion and embedding

### Gap Summary

The gap analysis identified 21 missing features across 8 categories:

1. **Chunker Adapters** (5 gaps - Critical)
   - Semantic chunker with embedding-based grouping
   - Sentence chunker with NLP tokenization
   - Paragraph chunker
   - Character chunker with smart boundaries
   - Byte position tracking

2. **Retriever Types** (2 gaps - High)
   - tsvector full-text search
   - Graph retriever global/hybrid modes

3. **Reranker Adapters** (2 gaps - High)
   - LLM reranker with customizable prompts
   - Passthrough reranker for testing

4. **VectorStore Functions** (2 gaps - Medium)
   - Chunk building utilities
   - Composable query functions

5. **GraphStore Functions** (3 gaps - High)
   - Entity vector search
   - Community CRUD operations
   - BFS traversal

6. **GraphRAG Components** (3 gaps - Critical)
   - Entity extraction/resolution
   - Community detection (label propagation)
   - Community summarization

7. **Embedding Service** (2 gaps - Medium)
   - Auto-batching GenServer
   - Provider limit handling

8. **Pipeline Features** (2 gaps - Medium)
   - Step retry with backoff
   - Context struct

---

## IMPLEMENTATION TASKS

### Phase 1: Critical Chunker Gaps (Days 1-3)

#### Task 1.1: Semantic Chunker

**File**: `lib/portfolio_index/adapters/chunker/semantic.ex`

```elixir
defmodule PortfolioIndex.Adapters.Chunker.Semantic do
  @moduledoc """
  Semantic chunker that groups text by embedding similarity.

  Uses cosine similarity between sentence embeddings to determine
  chunk boundaries. Starts a new chunk when similarity drops below
  threshold or max_chars is exceeded.

  ## Example

      config = %{
        threshold: 0.75,
        max_chars: 1000,
        embedding_fn: &MyEmbedder.embed/1
      }
      {:ok, chunks} = Semantic.chunk(text, :semantic, config)
  """

  @behaviour PortfolioCore.Ports.Chunker

  @default_threshold 0.75
  @default_max_chars 1000

  @impl true
  def chunk(text, _format, config) do
    threshold = config[:threshold] || @default_threshold
    max_chars = config[:max_chars] || @default_max_chars
    embedding_fn = config[:embedding_fn] || fn _ -> {:error, :no_embedding_fn} end

    # 1. Split text into sentences
    # 2. Generate embedding for each sentence
    # 3. Group by similarity threshold
    # 4. Respect max_chars limit
    # 5. Track byte positions
  end

  @impl true
  def estimate_chunks(text, config) do
    # Estimate based on text length and max_chars
  end

  # Private: sentence splitting, similarity calculation, grouping
end
```

**Tests**: `test/adapters/chunker/semantic_test.exs`

#### Task 1.2: Sentence Chunker

**File**: `lib/portfolio_index/adapters/chunker/sentence.ex`

```elixir
defmodule PortfolioIndex.Adapters.Chunker.Sentence do
  @moduledoc """
  Sentence-based chunker with NLP tokenization.

  Splits text on sentence boundaries and groups sentences
  to reach target chunk size.
  """

  @behaviour PortfolioCore.Ports.Chunker

  # Implement sentence boundary detection
  # Track byte positions for each chunk
end
```

**Tests**: `test/adapters/chunker/sentence_test.exs`

#### Task 1.3: Paragraph Chunker

**File**: `lib/portfolio_index/adapters/chunker/paragraph.ex`

**Tests**: `test/adapters/chunker/paragraph_test.exs`

#### Task 1.4: Character Chunker

**File**: `lib/portfolio_index/adapters/chunker/character.ex`

**Tests**: `test/adapters/chunker/character_test.exs`

---

### Phase 2: GraphRAG Components (Days 4-6)

#### Task 2.1: Community Detection

**File**: `lib/portfolio_index/graph_rag/community_detector.ex`

```elixir
defmodule PortfolioIndex.GraphRAG.CommunityDetector do
  @moduledoc """
  Label propagation algorithm for community detection.

  Clusters graph entities into communities based on
  edge connectivity patterns.
  """

  @max_iterations 100

  def detect(graph_store, graph_id, opts \\ []) do
    max_iter = opts[:max_iterations] || @max_iterations

    # 1. Initialize: each entity in own community
    # 2. Iterate: each entity adopts most common neighbor label
    # 3. Stop: when labels stabilize or max iterations
    # 4. Return community mapping: %{community_id => [entity_ids]}
  end

  def detect_hierarchical(graph_store, graph_id, levels, opts) do
    # Multi-level community detection
  end
end
```

**Tests**: `test/graph_rag/community_detector_test.exs`

#### Task 2.2: Community Summarization

**File**: `lib/portfolio_index/graph_rag/community_summarizer.ex`

```elixir
defmodule PortfolioIndex.GraphRAG.CommunitySummarizer do
  @moduledoc """
  LLM-based summarization of graph communities.

  Generates concise summaries describing community themes
  for use in global search.
  """

  def summarize(community, graph_store, graph_id, llm, opts) do
    # 1. Get community members
    # 2. Get internal relationships
    # 3. Build prompt with members and relationships
    # 4. Generate summary via LLM
    # 5. Generate embedding for summary
  end

  def summarize_all(communities, graph_store, graph_id, llm, opts) do
    # Parallel summarization with rate limiting
  end
end
```

**Tests**: `test/graph_rag/community_summarizer_test.exs`

#### Task 2.3: Entity Extractor Enhancement

**File**: `lib/portfolio_index/graph_rag/entity_extractor.ex`

```elixir
defmodule PortfolioIndex.GraphRAG.EntityExtractor do
  @moduledoc """
  LLM-based entity and relationship extraction.

  Extracts entities and relationships from text chunks
  for knowledge graph construction.
  """

  def extract(text, llm, opts) do
    # Extract entities and relationships
  end

  def extract_batch(texts, llm, opts) do
    # Parallel extraction with rate limiting
  end

  def resolve_entities(entities, existing_entities) do
    # Entity deduplication/resolution
  end
end
```

**Tests**: `test/graph_rag/entity_extractor_test.exs`

---

### Phase 3: Graph Store Enhancements (Days 7-8)

#### Task 3.1: Entity Vector Search

Add to Neo4j adapter or create new module:

**File**: `lib/portfolio_index/adapters/graph_store/neo4j/entity_search.ex`

```elixir
defmodule PortfolioIndex.Adapters.GraphStore.Neo4j.EntitySearch do
  @moduledoc """
  Vector-based entity search for Neo4j graph store.

  Enables semantic search over entity embeddings.
  """

  def search_by_vector(graph_id, query_vector, k, opts) do
    # Vector similarity search on entity embeddings
    # Requires entity nodes to have embedding property
  end

  def ensure_vector_index(graph_id) do
    # Create vector index on entity embeddings
  end
end
```

#### Task 3.2: Community Operations

Add to Neo4j adapter:

**File**: `lib/portfolio_index/adapters/graph_store/neo4j/community.ex`

```elixir
defmodule PortfolioIndex.Adapters.GraphStore.Neo4j.Community do
  @moduledoc """
  Community CRUD operations for Neo4j.
  """

  def create_community(graph_id, community)
  def list_communities(graph_id, opts)
  def get_community_members(graph_id, community_id)
  def search_communities_by_vector(graph_id, query_vector, k)
  def delete_community(graph_id, community_id)
end
```

#### Task 3.3: BFS Traversal

**File**: `lib/portfolio_index/adapters/graph_store/neo4j/traversal.ex`

```elixir
defmodule PortfolioIndex.Adapters.GraphStore.Neo4j.Traversal do
  @moduledoc """
  Graph traversal algorithms for Neo4j.
  """

  def bfs(graph_id, start_node_id, depth, opts) do
    # Breadth-first traversal with depth limit
  end

  def get_subgraph(graph_id, node_ids) do
    # Get all nodes and edges within a set of node IDs
  end
end
```

---

### Phase 4: Reranker Adapters (Day 9)

#### Task 4.1: LLM Reranker

**File**: `lib/portfolio_index/adapters/reranker/llm.ex`

```elixir
defmodule PortfolioIndex.Adapters.Reranker.LLM do
  @moduledoc """
  LLM-based document reranking.

  Uses an LLM to score document relevance to a query,
  then reorders results by score.
  """

  @behaviour PortfolioCore.Ports.Reranker

  @default_prompt_template """
  Rank these documents by relevance to the query.
  Query: {query}

  Documents:
  {documents}

  Return JSON array: [{"index": 0, "score": 8}, ...]
  Score 1-10 where 10 = most relevant.
  """

  @impl true
  def rerank(query, documents, opts) do
    # 1. Build prompt with query and documents
    # 2. Call LLM
    # 3. Parse scores from JSON response
    # 4. Reorder documents by score
    # 5. Return top_k results
  end
end
```

**Tests**: `test/adapters/reranker/llm_test.exs`

#### Task 4.2: Passthrough Reranker

**File**: `lib/portfolio_index/adapters/reranker/passthrough.ex`

```elixir
defmodule PortfolioIndex.Adapters.Reranker.Passthrough do
  @moduledoc """
  No-op reranker for testing and baseline comparisons.
  """

  @behaviour PortfolioCore.Ports.Reranker

  @impl true
  def rerank(_query, documents, _opts), do: {:ok, documents}
end
```

---

### Phase 5: Retriever Enhancements (Day 10)

#### Task 5.1: Graph Retriever Global Mode

Update GraphRAG strategy:

**File**: Update `lib/portfolio_index/rag/strategies/graph_rag.ex`

Add:
- `global_search/3` - Search community summaries
- `hybrid_search/3` - Combine local and global
- Support for `:mode` option (`:local`, `:global`, `:hybrid`)

#### Task 5.2: Full-Text Search with tsvector

Update VectorStore or create separate module:

**File**: `lib/portfolio_index/adapters/vector_store/pgvector/fulltext.ex`

```elixir
defmodule PortfolioIndex.Adapters.VectorStore.Pgvector.FullText do
  @moduledoc """
  PostgreSQL tsvector-based full-text search.
  """

  def search(index_id, query_text, k, opts) do
    # Use ts_rank for scoring
    # Support phrase matching
    # Support language configuration
  end

  def ensure_tsvector_column(index_id) do
    # Add tsvector column if not exists
    # Create GIN index
  end
end
```

---

### Phase 6: Final Integration (Day 11)

#### Task 6.1: Update GraphRAG Strategy

Integrate all new components:
- Community detection
- Community summarization
- Global search mode
- Entity vector search

#### Task 6.2: Update mix.exs

```elixir
@version "0.3.0"
```

#### Task 6.3: Update README.md

Add documentation for:
- New chunker types
- Reranker usage
- GraphRAG modes
- Community detection

#### Task 6.4: Create CHANGELOG Entry

```markdown
## [0.3.0] - 2025-12-28

### Added
- Semantic chunker with embedding-based similarity grouping
- Sentence chunker with NLP tokenization
- Paragraph chunker for document structure preservation
- Character chunker with smart boundaries
- LLM reranker for result quality improvement
- Passthrough reranker for testing
- Community detection using label propagation algorithm
- Community summarization with LLM
- Entity extractor with batch support and resolution
- Graph entity vector search
- Graph BFS traversal
- GraphRAG global and hybrid search modes
- Full-text search with PostgreSQL tsvector

### Changed
- GraphRAG strategy now supports `:mode` option (`:local`, `:global`, `:hybrid`)
- VectorStore keyword search upgraded to tsvector-based full-text

### Fixed
- (Any bug fixes made during implementation)
```

---

## GOALS

### Quality Gates

All of the following must pass before completion:

1. **No Warnings**: `mix compile --warnings-as-errors`
2. **No Errors**: All modules compile successfully
3. **All Tests Pass**: `mix test` with 100% pass rate
4. **No Dialyzer Issues**: `mix dialyzer` with no warnings
5. **No Credo Issues**: `mix credo --strict` with no issues
6. **Documentation**: All public functions have @doc and @spec

### Test Coverage Requirements

- Unit tests for all new chunker types
- Unit tests for community detection algorithm
- Unit tests for LLM reranker with mocked LLM
- Integration tests for GraphRAG modes
- Property-based tests for chunker correctness

### Version Bump Instructions

1. Update `@version` in `/home/home/p/g/n/portfolio_index/mix.exs`:
   ```elixir
   @version "0.3.0"
   ```

2. Update version in `/home/home/p/g/n/portfolio_index/README.md`:
   - Installation section: `{:portfolio_index, "~> 0.3.0"}`
   - Any other version references

3. Create CHANGELOG.md entry for 2025-12-28 v0.3.0

---

## TDD APPROACH

For each new module, follow this order:

### 1. Write Test First

```elixir
# test/adapters/chunker/semantic_test.exs
defmodule PortfolioIndex.Adapters.Chunker.SemanticTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Chunker.Semantic

  describe "chunk/3" do
    test "groups similar sentences together" do
      text = "Elixir is a functional language. It runs on the BEAM. Python is different."
      config = %{
        threshold: 0.7,
        max_chars: 500,
        embedding_fn: &mock_embedding/1
      }

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      # Elixir sentences should be grouped
      assert length(chunks) >= 1
      assert Enum.any?(chunks, &String.contains?(&1.content, "Elixir"))
    end

    test "respects max_chars limit" do
      text = String.duplicate("This is a sentence. ", 100)
      config = %{max_chars: 200, threshold: 0.9, embedding_fn: &mock_embedding/1}

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      assert Enum.all?(chunks, fn c -> String.length(c.content) <= 250 end)
    end

    test "tracks byte positions" do
      text = "First sentence. Second sentence. Third sentence."
      config = %{threshold: 0.5, embedding_fn: &mock_embedding/1}

      {:ok, chunks} = Semantic.chunk(text, :semantic, config)

      # Verify positions are tracked
      assert Enum.all?(chunks, fn c ->
        is_integer(c.start_offset) and is_integer(c.end_offset)
      end)
    end
  end

  defp mock_embedding(text) do
    # Return deterministic embedding based on text hash
    hash = :erlang.phash2(text)
    vec = for i <- 1..768, do: :math.sin(hash + i) / 2 + 0.5
    {:ok, %{vector: vec}}
  end
end
```

### 2. Implement Module

Make tests pass with minimal implementation.

### 3. Refactor

Improve code quality while keeping tests green.

### 4. Add Integration Tests

```elixir
# test/adapters/chunker/semantic_integration_test.exs
defmodule PortfolioIndex.Adapters.Chunker.SemanticIntegrationTest do
  use ExUnit.Case

  @tag :integration
  test "works with real embedder" do
    # Test with actual Gemini embedder
  end
end
```

---

## FILE STRUCTURE

After implementation, the following files should exist:

```
lib/portfolio_index/
  adapters/
    chunker/
      character.ex           # NEW
      paragraph.ex           # NEW
      recursive.ex           # EXISTS
      semantic.ex            # NEW
      sentence.ex            # NEW
    reranker/
      llm.ex                 # NEW
      passthrough.ex         # NEW
    vector_store/
      pgvector.ex            # EXISTS
      pgvector/
        fulltext.ex          # NEW
    graph_store/
      neo4j.ex               # EXISTS
      neo4j/
        community.ex         # NEW
        entity_search.ex     # NEW
        schema.ex            # EXISTS
        traversal.ex         # NEW
  graph_rag/
    community_detector.ex    # NEW
    community_summarizer.ex  # NEW
    entity_extractor.ex      # NEW
  rag/
    strategies/
      graph_rag.ex           # UPDATE (add global/hybrid modes)

test/
  adapters/
    chunker/
      character_test.exs     # NEW
      paragraph_test.exs     # NEW
      semantic_test.exs      # NEW
      sentence_test.exs      # NEW
    reranker/
      llm_test.exs           # NEW
      passthrough_test.exs   # NEW
  graph_rag/
    community_detector_test.exs    # NEW
    community_summarizer_test.exs  # NEW
    entity_extractor_test.exs      # NEW
```

---

## IMPLEMENTATION CHECKLIST

### Chunker Adapters
- [ ] Semantic chunker with embedding similarity
- [ ] Sentence chunker with NLP tokenization
- [ ] Paragraph chunker
- [ ] Character chunker with smart boundaries
- [ ] Byte position tracking in all chunkers
- [ ] Tests for all chunker types

### GraphRAG Components
- [ ] Community detection (label propagation)
- [ ] Hierarchical community support
- [ ] Community summarization
- [ ] Entity extractor with batch support
- [ ] Entity resolution/deduplication
- [ ] Tests for all components

### Graph Store Enhancements
- [ ] Entity vector search in Neo4j
- [ ] Community CRUD operations
- [ ] BFS traversal function
- [ ] Subgraph extraction
- [ ] Tests for new functions

### Reranker Adapters
- [ ] LLM reranker with customizable prompts
- [ ] Passthrough reranker
- [ ] Tests for rerankers

### Retriever Enhancements
- [ ] GraphRAG global search mode
- [ ] GraphRAG hybrid search mode
- [ ] tsvector full-text search
- [ ] Update Hybrid strategy to use tsvector
- [ ] Tests for retriever modes

### Quality Gates
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` passes with 100%
- [ ] `mix dialyzer` has no warnings
- [ ] `mix credo --strict` has no issues
- [ ] All public functions have @doc and @spec

### Documentation
- [ ] Update mix.exs to version 0.3.0
- [ ] Update README.md with new features
- [ ] Create CHANGELOG entry for v0.3.0
- [ ] Add @moduledoc to all new modules
- [ ] Add @doc to all public functions

---

## NOTES

### Embedding Function Pattern

All chunkers that need embeddings should accept an `embedding_fn` in config:

```elixir
config = %{
  embedding_fn: fn text ->
    case Embedder.embed(text, []) do
      {:ok, %{vector: vec}} -> {:ok, vec}
      error -> error
    end
  end
}
```

### Error Handling

All new functions should return:
- `{:ok, result}` on success
- `{:error, reason}` on failure

Never raise exceptions from adapter code.

### Telemetry

Add telemetry events for new operations:

```elixir
:telemetry.execute(
  [:portfolio_index, :chunker, :semantic, :chunk],
  %{duration_ms: duration, chunk_count: length(chunks)},
  %{format: format}
)
```

### Dialyzer Suppression

If gemini_ex or other deps cause dialyzer warnings, use module-level suppression:

```elixir
@dialyzer [
  {:nowarn_function, function_name: arity},
  :no_return
]
```
