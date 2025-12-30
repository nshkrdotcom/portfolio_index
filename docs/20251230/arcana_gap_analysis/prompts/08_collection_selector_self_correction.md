# Prompt 8: Collection Selector & Self-Correction Implementation

## Target Repositories
- **portfolio_core**: `/home/home/p/g/n/portfolio_core`
- **portfolio_index**: `/home/home/p/g/n/portfolio_index`

## Required Reading Before Implementation

### Reference Implementation (Arcana)
Read these files to understand the reference implementation:
```
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/context.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/selector.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/selector/llm.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/searcher.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/searcher/arcana.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/answerer.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/answerer/llm.ex
```

### Existing Portfolio Code
Read these files to understand existing patterns:
```
/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategy.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/agentic.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/self_rag.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/reranker/llm.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/reranker.ex
```

### Gap Analysis Documentation
```
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/01_agent_system.md
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/05_llm_integration.md
```

### Prerequisite - Pipeline Context (from Prompt 1)
This prompt depends on the Pipeline Context from Prompt 1:
```
/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/pipeline/context.ex
```

---

## Implementation Tasks

### Task 1: Collection Selector Port (portfolio_core)

Create `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/collection_selector.ex`:

```elixir
defmodule PortfolioCore.Ports.CollectionSelector do
  @moduledoc """
  Behaviour for selecting relevant collections/indexes to search.
  Enables intelligent routing of queries to appropriate data sources.
  """

  @type selection_result :: %{
    selected: [String.t()],
    reasoning: String.t() | nil,
    confidence: float() | nil
  }

  @type collection_info :: %{
    name: String.t(),
    description: String.t() | nil,
    document_count: non_neg_integer() | nil
  }

  @doc """
  Select relevant collections for a query.

  ## Parameters
  - `query` - The search query
  - `available_collections` - List of available collection info
  - `opts` - Options including `:max_collections`, `:llm`
  """
  @callback select(query :: String.t(), available_collections :: [collection_info()], opts :: keyword()) ::
    {:ok, selection_result()} | {:error, term()}
end
```

**Test file**: `/home/home/p/g/n/portfolio_core/test/ports/collection_selector_test.exs`

---

### Task 2: Collection Selector LLM Adapter (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/collection_selector/llm.ex`:

```elixir
defmodule PortfolioIndex.Adapters.CollectionSelector.LLM do
  @moduledoc """
  LLM-based collection selector that routes queries to relevant collections.
  Uses collection descriptions to determine relevance.
  """

  @behaviour PortfolioCore.Ports.CollectionSelector

  @default_prompt """
  You are a query router. Given a user query and available document collections,
  select the most relevant collections to search.

  User query: {query}

  Available collections:
  {collections}

  Return a JSON object with:
  - "selected": array of collection names to search (1-3 collections)
  - "reasoning": brief explanation of why these collections were selected

  Return ONLY the JSON, nothing else.
  """

  @impl true
  def select(query, available_collections, opts \\ [])

  @doc "Format collection info for prompt"
  @spec format_collections([map()]) :: String.t()
  def format_collections(collections)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/collection_selector/llm_test.exs`

---

### Task 3: Deterministic Collection Selector (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/collection_selector/rule_based.ex`:

```elixir
defmodule PortfolioIndex.Adapters.CollectionSelector.RuleBased do
  @moduledoc """
  Rule-based collection selector using keyword matching.
  Useful when LLM routing is not needed or for deterministic behavior.

  ## Configuration

      rules = [
        %{
          collection: "api_docs",
          keywords: ["api", "endpoint", "request", "response"],
          boost: 2.0
        },
        %{
          collection: "tutorials",
          keywords: ["how to", "guide", "tutorial", "example"],
          boost: 1.5
        }
      ]

      RuleBased.select(query, collections, rules: rules)
  """

  @behaviour PortfolioCore.Ports.CollectionSelector

  @impl true
  def select(query, available_collections, opts \\ [])

  @doc "Score a query against rules"
  @spec score_query(String.t(), [map()]) :: [{String.t(), float()}]
  def score_query(query, rules)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/collection_selector/rule_based_test.exs`

---

### Task 4: Self-Correcting Search Module (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/self_correcting_search.ex`:

```elixir
defmodule PortfolioIndex.RAG.SelfCorrectingSearch do
  @moduledoc """
  Search with self-correction loop that evaluates result sufficiency
  and rewrites queries when needed.

  ## Flow

  1. Execute initial search
  2. Evaluate if results are sufficient for answering the question
  3. If insufficient:
     a. Ask LLM to suggest a better query
     b. Execute new search
     c. Repeat until sufficient or max iterations
  4. Return results with correction history
  """

  alias PortfolioIndex.RAG.Pipeline.Context

  @type search_opts :: [
    max_iterations: pos_integer(),
    min_results: pos_integer(),
    sufficiency_prompt: String.t() | (String.t(), [map()] -> String.t()),
    rewrite_prompt: String.t() | (String.t(), [map()] -> String.t()),
    llm: (String.t() -> {:ok, String.t()} | {:error, term()}),
    search_fn: (String.t(), keyword() -> {:ok, [map()]} | {:error, term()})
  ]

  @doc """
  Execute self-correcting search.

  Returns context with results and correction history.
  """
  @spec search(Context.t(), search_opts()) :: Context.t()
  def search(ctx, opts \\ [])

  @doc """
  Evaluate if search results are sufficient.
  """
  @spec evaluate_sufficiency(String.t(), [map()], keyword()) :: {:ok, boolean(), String.t()} | {:error, term()}
  def evaluate_sufficiency(question, results, opts)

  @doc """
  Generate a rewritten query based on feedback.
  """
  @spec rewrite_query(String.t(), [map()], String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def rewrite_query(original_query, results, feedback, opts)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/rag/self_correcting_search_test.exs`

---

### Task 5: Self-Correcting Answer Module (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/self_correcting_answer.ex`:

```elixir
defmodule PortfolioIndex.RAG.SelfCorrectingAnswer do
  @moduledoc """
  Answer generation with grounding evaluation and correction loop.

  ## Flow

  1. Generate initial answer from context
  2. Evaluate if answer is grounded in the provided context
  3. If not grounded:
     a. Identify ungrounded claims
     b. Generate corrected answer
     c. Repeat until grounded or max iterations
  4. Return answer with correction history
  """

  alias PortfolioIndex.RAG.Pipeline.Context

  @type answer_opts :: [
    max_corrections: pos_integer(),
    grounding_threshold: float(),
    grounding_prompt: String.t() | (String.t(), String.t(), [map()] -> String.t()),
    correction_prompt: String.t() | (String.t(), String.t(), String.t() -> String.t()),
    llm: (String.t() -> {:ok, String.t()} | {:error, term()})
  ]

  @type grounding_result :: %{
    grounded: boolean(),
    score: float(),
    ungrounded_claims: [String.t()],
    feedback: String.t()
  }

  @doc """
  Generate answer with self-correction.
  """
  @spec answer(Context.t(), answer_opts()) :: Context.t()
  def answer(ctx, opts \\ [])

  @doc """
  Generate initial answer from context.
  """
  @spec generate_answer(String.t(), [map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_answer(question, context_chunks, opts)

  @doc """
  Evaluate if answer is grounded in context.
  """
  @spec evaluate_grounding(String.t(), String.t(), [map()], keyword()) :: {:ok, grounding_result()} | {:error, term()}
  def evaluate_grounding(question, answer, context_chunks, opts)

  @doc """
  Generate corrected answer based on grounding feedback.
  """
  @spec correct_answer(String.t(), String.t(), grounding_result(), [map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def correct_answer(question, original_answer, grounding_result, context_chunks, opts)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/rag/self_correcting_answer_test.exs`

---

### Task 6: Reranker Integration Module (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/reranker.ex`:

```elixir
defmodule PortfolioIndex.RAG.Reranker do
  @moduledoc """
  Reranking utilities for RAG pipeline integration.
  Wraps the existing Reranker.LLM adapter with pipeline-aware functionality.
  """

  alias PortfolioIndex.RAG.Pipeline.Context
  alias PortfolioIndex.Adapters.Reranker.LLM, as: RerankerLLM

  @type rerank_opts :: [
    threshold: float(),
    limit: pos_integer(),
    reranker: module() | (String.t(), [map()] -> {:ok, [map()]} | {:error, term()}),
    track_scores: boolean()
  ]

  @doc """
  Rerank search results in pipeline context.

  Updates context with:
  - Reranked and filtered results
  - Rerank scores (if track_scores: true)
  """
  @spec rerank(Context.t(), rerank_opts()) :: Context.t()
  def rerank(ctx, opts \\ [])

  @doc """
  Rerank a list of chunks directly.
  """
  @spec rerank_chunks(String.t(), [map()], rerank_opts()) :: {:ok, [map()]} | {:error, term()}
  def rerank_chunks(question, chunks, opts \\ [])

  @doc """
  Deduplicate chunks by content or ID.
  """
  @spec deduplicate([map()], atom()) :: [map()]
  def deduplicate(chunks, key \\ :id)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/rag/reranker_test.exs`

---

### Task 7: Enhanced Agentic Strategy (portfolio_index)

Update `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/agentic.ex` to integrate all new components:

```elixir
# Add these new functions to the existing Agentic strategy module:

@doc """
Execute full agentic pipeline with all enhancements.

Pipeline steps:
1. Query rewriting (clean conversational input)
2. Query expansion (add synonyms)
3. Query decomposition (break complex questions)
4. Collection selection (route to relevant collections)
5. Self-correcting search (iterate until sufficient)
6. Reranking (score and filter results)
7. Self-correcting answer (ensure grounding)
"""
@spec execute_pipeline(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
def execute_pipeline(question, opts \\ [])

@doc """
Execute pipeline with Context struct.
Enables functional composition with pipe operator.
"""
@spec with_context(Context.t()) :: Context.t()
def with_context(ctx)
```

**Test file**: Update `/home/home/p/g/n/portfolio_index/test/rag/strategies/agentic_test.exs`

---

## TDD Requirements

For each task:

1. **Write tests FIRST** following existing test patterns in the repos
2. Tests must cover:
   - Happy path with valid input
   - LLM mock responses
   - Error handling (LLM failures, empty results)
   - Iteration limits
   - Correction history tracking
   - Integration with Pipeline Context
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
- `PortfolioCore.Ports.CollectionSelector` behaviour for query routing
```

### portfolio_index
Update `/home/home/p/g/n/portfolio_index/CHANGELOG.md` - add entry to version 0.3.1:
```markdown
### Added
- `PortfolioIndex.Adapters.CollectionSelector.LLM` - LLM-based collection routing
- `PortfolioIndex.Adapters.CollectionSelector.RuleBased` - Rule-based collection routing
- `PortfolioIndex.RAG.SelfCorrectingSearch` - Search with sufficiency evaluation and query rewriting
- `PortfolioIndex.RAG.SelfCorrectingAnswer` - Answer generation with grounding evaluation
- `PortfolioIndex.RAG.Reranker` - Pipeline-integrated reranking utilities

### Changed
- `PortfolioIndex.RAG.Strategies.Agentic` - Added full pipeline execution with all enhancements
```

## Verification Checklist

- [ ] All new files created in correct locations
- [ ] All tests pass in both repos
- [ ] No credo warnings
- [ ] No dialyzer errors
- [ ] Changelogs updated for both repos
- [ ] Module documentation complete
- [ ] Type specifications complete
- [ ] Integration with Pipeline Context verified
- [ ] Agentic strategy enhanced with new components

