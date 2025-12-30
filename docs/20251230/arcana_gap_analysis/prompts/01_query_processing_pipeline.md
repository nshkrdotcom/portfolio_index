# Prompt 1: Query Processing Pipeline Implementation

## Target Repositories
- **portfolio_core**: `/home/home/p/g/n/portfolio_core`
- **portfolio_index**: `/home/home/p/g/n/portfolio_index`

## Required Reading Before Implementation

### Reference Implementation (Arcana)
Read these files to understand the reference implementation:
```
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/context.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/rewriter.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/rewriter/llm.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/expander.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/expander/llm.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/decomposer.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/agent/decomposer/llm.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/rewriters.ex
```

### Existing Portfolio Code
Read these files to understand existing patterns:
```
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/llm.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/reranker.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/llm/anthropic.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/reranker/llm.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategy.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/agentic.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/generation.ex
```

### Gap Analysis Documentation
```
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/01_agent_system.md
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/05_llm_integration.md
```

---

## Implementation Tasks

### Task 1: Pipeline Context Struct (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/pipeline/context.ex`:

```elixir
defmodule PortfolioIndex.RAG.Pipeline.Context do
  @moduledoc """
  Context struct that flows through the RAG pipeline, tracking all intermediate results.
  Enables functional composition with the pipe operator.
  """

  @type t :: %__MODULE__{
    # Input
    question: String.t() | nil,
    opts: keyword(),

    # Query Processing
    rewritten_query: String.t() | nil,
    expanded_query: String.t() | nil,
    sub_questions: [String.t()],

    # Routing
    selected_indexes: [String.t()],
    selection_reasoning: String.t() | nil,

    # Retrieval
    results: [map()],
    rerank_scores: %{String.t() => float()},

    # Generation
    answer: String.t() | nil,
    context_used: [map()],

    # Self-Correction
    correction_count: non_neg_integer(),
    corrections: [{String.t(), String.t()}],

    # Error Handling
    error: term() | nil,
    halted?: boolean()
  }

  defstruct [
    question: nil,
    opts: [],
    rewritten_query: nil,
    expanded_query: nil,
    sub_questions: [],
    selected_indexes: [],
    selection_reasoning: nil,
    results: [],
    rerank_scores: %{},
    answer: nil,
    context_used: [],
    correction_count: 0,
    corrections: [],
    error: nil,
    halted?: false
  ]

  @doc "Create a new context with the given question and options"
  @spec new(String.t(), keyword()) :: t()
  def new(question, opts \\ [])

  @doc "Mark context as halted with an error"
  @spec halt(t(), term()) :: t()
  def halt(ctx, error)

  @doc "Check if context has an error"
  @spec error?(t()) :: boolean()
  def error?(ctx)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/rag/pipeline/context_test.exs`

---

### Task 2: Query Rewriter Port (portfolio_core)

Create `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/query_rewriter.ex`:

```elixir
defmodule PortfolioCore.Ports.QueryRewriter do
  @moduledoc """
  Behaviour for query rewriting - transforming conversational input into clean search queries.
  """

  @type rewrite_result :: %{
    original: String.t(),
    rewritten: String.t(),
    changes_made: [String.t()]
  }

  @callback rewrite(query :: String.t(), opts :: keyword()) ::
    {:ok, rewrite_result()} | {:error, term()}

  @optional_callbacks []
end
```

**Test file**: `/home/home/p/g/n/portfolio_core/test/ports/query_rewriter_test.exs`

---

### Task 3: Query Rewriter LLM Adapter (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/query_rewriter/llm.ex`:

```elixir
defmodule PortfolioIndex.Adapters.QueryRewriter.LLM do
  @moduledoc """
  LLM-based query rewriter that cleans conversational input.
  Removes greetings, filler words, and extracts the core question.
  """

  @behaviour PortfolioCore.Ports.QueryRewriter

  @default_prompt """
  Transform the following user query into a clean search query.
  Remove conversational elements like greetings, filler phrases, and politeness markers.
  Keep technical terms and the core question intact.
  Return ONLY the cleaned query, nothing else.

  User query: {query}
  """

  @impl true
  def rewrite(query, opts \\ [])
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/query_rewriter/llm_test.exs`

---

### Task 4: Query Expander Port (portfolio_core)

Create `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/query_expander.ex`:

```elixir
defmodule PortfolioCore.Ports.QueryExpander do
  @moduledoc """
  Behaviour for query expansion - adding synonyms and related terms.
  """

  @type expansion_result :: %{
    original: String.t(),
    expanded: String.t(),
    added_terms: [String.t()]
  }

  @callback expand(query :: String.t(), opts :: keyword()) ::
    {:ok, expansion_result()} | {:error, term()}
end
```

**Test file**: `/home/home/p/g/n/portfolio_core/test/ports/query_expander_test.exs`

---

### Task 5: Query Expander LLM Adapter (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/query_expander/llm.ex`:

```elixir
defmodule PortfolioIndex.Adapters.QueryExpander.LLM do
  @moduledoc """
  LLM-based query expander that adds synonyms and related terms.
  Improves recall by including alternative phrasings.
  """

  @behaviour PortfolioCore.Ports.QueryExpander

  @default_prompt """
  Expand the following search query with synonyms and related terms.
  Add abbreviation expansions, alternative phrasings, and technical equivalents.
  Return the original query PLUS the additional terms, space-separated.

  Query: {query}
  """

  @impl true
  def expand(query, opts \\ [])
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/query_expander/llm_test.exs`

---

### Task 6: Query Decomposer Port (portfolio_core)

Create `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/query_decomposer.ex`:

```elixir
defmodule PortfolioCore.Ports.QueryDecomposer do
  @moduledoc """
  Behaviour for query decomposition - breaking complex questions into sub-questions.
  """

  @type decomposition_result :: %{
    original: String.t(),
    sub_questions: [String.t()],
    is_complex: boolean()
  }

  @callback decompose(query :: String.t(), opts :: keyword()) ::
    {:ok, decomposition_result()} | {:error, term()}
end
```

**Test file**: `/home/home/p/g/n/portfolio_core/test/ports/query_decomposer_test.exs`

---

### Task 7: Query Decomposer LLM Adapter (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/query_decomposer/llm.ex`:

```elixir
defmodule PortfolioIndex.Adapters.QueryDecomposer.LLM do
  @moduledoc """
  LLM-based query decomposer that breaks complex questions into simpler sub-questions.
  Returns JSON with sub_questions array.
  """

  @behaviour PortfolioCore.Ports.QueryDecomposer

  @default_prompt """
  Analyze the following question. If it is complex and contains multiple parts,
  break it into 2-4 simpler sub-questions that can be answered independently.
  If it is already simple, return it as the only sub-question.

  Return JSON format: {"sub_questions": ["q1", "q2", ...]}

  Question: {query}
  """

  @impl true
  def decompose(query, opts \\ [])
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/query_decomposer/llm_test.exs`

---

### Task 8: Query Processor Module (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/query_processor.ex`:

```elixir
defmodule PortfolioIndex.RAG.QueryProcessor do
  @moduledoc """
  Unified query processing module that combines rewriting, expansion, and decomposition.
  """

  alias PortfolioIndex.RAG.Pipeline.Context

  @doc "Apply query rewriting to context"
  @spec rewrite(Context.t(), keyword()) :: Context.t()
  def rewrite(ctx, opts \\ [])

  @doc "Apply query expansion to context"
  @spec expand(Context.t(), keyword()) :: Context.t()
  def expand(ctx, opts \\ [])

  @doc "Apply query decomposition to context"
  @spec decompose(Context.t(), keyword()) :: Context.t()
  def decompose(ctx, opts \\ [])

  @doc "Apply all query processing steps in sequence"
  @spec process(Context.t(), keyword()) :: Context.t()
  def process(ctx, opts \\ [])
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/rag/query_processor_test.exs`

---

## TDD Requirements

For each task:

1. **Write tests FIRST** following existing test patterns in the repos
2. Tests must cover:
   - Happy path with valid input
   - Error handling (invalid input, LLM failures)
   - Edge cases (empty query, very long query)
   - Context propagation (for pipeline tests)
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
- `PortfolioCore.Ports.QueryRewriter` behaviour for query cleaning
- `PortfolioCore.Ports.QueryExpander` behaviour for query expansion
- `PortfolioCore.Ports.QueryDecomposer` behaviour for multi-hop queries
```

### portfolio_index
Update `/home/home/p/g/n/portfolio_index/CHANGELOG.md` - add entry to version 0.3.1:
```markdown
### Added
- `PortfolioIndex.RAG.Pipeline.Context` struct for pipeline state tracking
- `PortfolioIndex.Adapters.QueryRewriter.LLM` - LLM-based query cleaning
- `PortfolioIndex.Adapters.QueryExpander.LLM` - LLM-based query expansion
- `PortfolioIndex.Adapters.QueryDecomposer.LLM` - LLM-based query decomposition
- `PortfolioIndex.RAG.QueryProcessor` - unified query processing module
```

## Verification Checklist

- [ ] All new files created in correct locations
- [ ] All tests pass
- [ ] No credo warnings
- [ ] No dialyzer errors
- [ ] Changelogs updated
- [ ] Module documentation complete with @moduledoc and @doc
- [ ] Type specifications complete with @type, @spec, @callback

