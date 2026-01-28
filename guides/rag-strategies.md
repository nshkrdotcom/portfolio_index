# RAG Strategies

PortfolioIndex implements four Retrieval-Augmented Generation strategies, each
suited to different use cases. All strategies implement the
`PortfolioCore.Ports.RAGStrategy` behaviour.

## Strategy Overview

| Strategy | Description | Best For |
|----------|-------------|----------|
| **Hybrid** | Vector + keyword search with RRF fusion | General-purpose retrieval |
| **Self-RAG** | Self-critique with answer refinement | High-accuracy requirements |
| **GraphRAG** | Graph-aware retrieval with community context | Knowledge graph queries |
| **Agentic** | Full pipeline with self-correction | Complex multi-step queries |

## Hybrid Strategy

`PortfolioIndex.RAG.Strategies.Hybrid` combines vector similarity search with
keyword-based full-text search using Reciprocal Rank Fusion (RRF):

```elixir
alias PortfolioIndex.RAG.Strategies.Hybrid

{:ok, result} = Hybrid.retrieve(
  "How does authentication work?",
  %{index_id: "docs"},
  k: 10
)

# result.items -- ranked results
# result.timing_ms -- query duration
```

Hybrid search ensures good results even when the query doesn't embed well
(e.g., exact names, error codes).

## Self-RAG Strategy

`PortfolioIndex.RAG.Strategies.SelfRAG` adds self-critique to retrieval,
evaluating and refining results:

```elixir
alias PortfolioIndex.RAG.Strategies.SelfRAG

{:ok, result} = SelfRAG.retrieve(
  "What is GenServer?",
  %{index_id: "docs"},
  k: 5,
  min_critique_score: 3
)

# result.answer -- generated answer
# result.critique -- %{relevance: N, support: N, completeness: N}
```

Self-RAG evaluates each retrieved document for relevance, then generates
an answer and scores it for factual grounding.

## GraphRAG Strategy

`PortfolioIndex.RAG.Strategies.GraphRAG` combines vector search with knowledge
graph traversal:

```elixir
alias PortfolioIndex.RAG.Strategies.GraphRAG

{:ok, result} = GraphRAG.retrieve(
  "How are modules related?",
  %{index_id: "docs", graph_id: "knowledge"},
  mode: :hybrid,  # :local | :global | :hybrid
  k: 10
)
```

Modes:
- `:local` -- entity-level search using graph neighbors
- `:global` -- community-level search using summarized communities
- `:hybrid` -- combines local and global results

Requires Neo4j with populated graph data. See the [Graph Stores guide](graph-stores.md).

### GraphRAG Components

- `PortfolioIndex.GraphRAG.EntityExtractor` -- extracts entities from text with batch support
- `PortfolioIndex.GraphRAG.CommunityDetector` -- label propagation community detection
- `PortfolioIndex.GraphRAG.CommunitySummarizer` -- LLM-based community summarization

## Agentic Strategy

`PortfolioIndex.RAG.Strategies.Agentic` runs a full pipeline with query processing,
collection routing, self-correcting search, reranking, and grounded answer generation:

```elixir
alias PortfolioIndex.RAG.Strategies.Agentic

{:ok, result} = Agentic.retrieve(
  "Compare authentication methods in the codebase",
  %{index_id: "docs"},
  k: 10
)
```

### Full Pipeline Execution

```elixir
alias PortfolioIndex.RAG.Strategies.Agentic
alias PortfolioIndex.RAG.Pipeline.Context

# Create context and run through pipeline
context = Context.new("Compare authentication methods", %{index_id: "docs"})

{:ok, context} = Agentic.execute_pipeline(context, [])

# Access intermediate results
context.rewritten_query
context.expanded_query
context.sub_queries
context.retrieved_items
context.reranked_items
context.answer
context.corrections
```

### Pipeline Steps

The agentic pipeline runs these steps in order:

1. **Query Rewriting** -- cleans conversational noise
2. **Query Expansion** -- adds synonyms and related terms
3. **Query Decomposition** -- breaks complex queries into sub-questions
4. **Collection Selection** -- routes to relevant collections
5. **Self-Correcting Search** -- retrieves and evaluates sufficiency
6. **Reranking** -- scores and filters results
7. **Self-Correcting Answer** -- generates and validates grounded answers

Skip steps with the `:skip` option:

```elixir
Agentic.execute_pipeline(context, skip: [:expand, :decompose])
```

### Pipeline Context

`PortfolioIndex.RAG.Pipeline.Context` tracks state through the pipeline:

```elixir
alias PortfolioIndex.RAG.Pipeline.Context

context = Context.new("my query", %{index_id: "docs"})

# Functional composition
context
|> Agentic.with_context(step: :rewrite)
|> Agentic.with_context(step: :search)
|> Agentic.with_context(step: :answer)
```

## Query Processing

The query processing modules clean and enhance queries before retrieval:

### Query Rewriter

```elixir
alias PortfolioIndex.Adapters.QueryRewriter.LLM

{:ok, rewritten} = LLM.rewrite("hey can u tell me about genservers?")
# => "What are GenServers in Elixir?"
```

Removes greetings, filler words, and conversational noise while preserving
technical terms.

### Query Expander

```elixir
alias PortfolioIndex.Adapters.QueryExpander.LLM

{:ok, expanded} = LLM.expand("ML pipeline")
# => "ML machine learning pipeline data processing workflow"
```

Adds synonyms and expands abbreviations for better recall.

### Query Decomposer

```elixir
alias PortfolioIndex.Adapters.QueryDecomposer.LLM

{:ok, sub_queries} = LLM.decompose("Compare REST and GraphQL for authentication")
# => ["What is REST authentication?", "What is GraphQL authentication?", ...]
```

Breaks complex questions into 2-4 simpler sub-questions for parallel retrieval.

## Collection Selection

Routes queries to the most relevant document collections:

### LLM-Based Selection

```elixir
alias PortfolioIndex.Adapters.CollectionSelector.LLM

{:ok, selected} = LLM.select("How do I authenticate?", collections)
```

### Rule-Based Selection

```elixir
alias PortfolioIndex.Adapters.CollectionSelector.RuleBased

{:ok, selected} = RuleBased.select("How do I authenticate?", collections)
```

Keyword matching with configurable boost factors. Deterministic, no LLM calls.

## Self-Correction

### Self-Correcting Search

`PortfolioIndex.RAG.SelfCorrectingSearch` evaluates if retrieved results are
sufficient and rewrites the query if not:

```elixir
alias PortfolioIndex.RAG.SelfCorrectingSearch

{:ok, results} = SelfCorrectingSearch.search(context,
  max_iterations: 3
)
```

### Self-Correcting Answer

`PortfolioIndex.RAG.SelfCorrectingAnswer` evaluates if the generated answer
is grounded in the provided context:

```elixir
alias PortfolioIndex.RAG.SelfCorrectingAnswer

{:ok, answer} = SelfCorrectingAnswer.generate(context,
  max_corrections: 2,
  grounding_threshold: 0.8
)
```

## Reranking

`PortfolioIndex.RAG.Reranker` provides pipeline-integrated reranking:

```elixir
alias PortfolioIndex.RAG.Reranker

{:ok, reranked} = Reranker.rerank(context, threshold: 0.5)
deduped = Reranker.deduplicate(results, by: :content)
```

### Reranker Adapters

- `PortfolioIndex.Adapters.Reranker.LLM` -- LLM-based relevance scoring
- `PortfolioIndex.Adapters.Reranker.Passthrough` -- no-op for testing

## Telemetry

RAG operations emit telemetry via `PortfolioIndex.Telemetry.RAG`:

```elixir
[:portfolio_index, :rag, :step, :start | :stop | :exception]     # pipeline steps
[:portfolio_index, :rag, :search, :start | :stop | :exception]    # search operations
[:portfolio_index, :rag, :rerank, :start | :stop | :exception]    # reranking
[:portfolio_index, :rag, :correction]                              # self-correction events
```
