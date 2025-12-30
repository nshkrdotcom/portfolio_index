# Agent System Gap Analysis

## Overview

This document compares the Arcana RAG agent system against the portfolio libraries (portfolio_core, portfolio_manager, portfolio_index) to identify gaps in RAG pipeline functionality.

## Arcana Agent Capabilities

### Architecture Overview

Arcana implements a **pipeline-based agentic RAG** system where a `Context` struct flows through each transformation step. The architecture follows a functional, composable pattern:

```elixir
Arcana.Agent.new(question, llm: llm_fn)
|> Arcana.Agent.rewrite()      # Clean conversational input
|> Arcana.Agent.expand()       # Add synonyms/related terms
|> Arcana.Agent.decompose()    # Break into sub-questions
|> Arcana.Agent.select()       # Choose collections to search
|> Arcana.Agent.search()       # Execute search with self-correction
|> Arcana.Agent.rerank()       # Re-score and filter results
|> Arcana.Agent.answer()       # Generate answer with self-correction
```

### Component Details

#### 1. Context (`Arcana.Agent.Context`)
- Central data structure that flows through pipeline
- Tracks all intermediate results: rewritten_query, expanded_query, sub_questions, collections, results, rerank_scores, answer, context_used
- Includes error handling and correction history

#### 2. Query Rewriter (`Arcana.Agent.Rewriter`)
- Behaviour + LLM implementation (`Arcana.Agent.Rewriter.LLM`)
- Removes conversational noise (greetings, filler phrases)
- Extracts core question while preserving technical terms
- Custom prompt support via `:prompt` option

#### 3. Query Expander (`Arcana.Agent.Expander`)
- Behaviour + LLM implementation (`Arcana.Agent.Expander.LLM`)
- Adds synonyms, related terms, abbreviation expansions
- Example: "ML models" -> "ML machine learning models"
- Custom expander modules or inline functions supported

#### 4. Query Decomposer (`Arcana.Agent.Decomposer`)
- Behaviour + LLM implementation (`Arcana.Agent.Decomposer.LLM`)
- Breaks complex questions into 2-4 simpler sub-questions
- Each sub-question searched independently
- Improves retrieval for multi-faceted queries

#### 5. Collection Selector (`Arcana.Agent.Selector`)
- Behaviour + LLM implementation (`Arcana.Agent.Selector.LLM`)
- LLM-based routing to select relevant collections
- Fetches collection descriptions from database for context
- Supports deterministic routing via custom selectors
- Returns reasoning for selection decisions

#### 6. Searcher (`Arcana.Agent.Searcher`)
- Behaviour + Arcana implementation (`Arcana.Agent.Searcher.Arcana`)
- Self-correcting search with configurable iterations
- Asks LLM if results are sufficient
- Rewrites query and retries if insufficient
- Supports multiple collections and sub-questions

#### 7. Reranker (`Arcana.Agent.Reranker`)
- Behaviour + LLM implementation (`Arcana.Agent.Reranker.LLM`)
- Scores each chunk 0-10 based on relevance
- Filters by threshold (default 7)
- Re-sorts by score
- Tracks scores for observability

#### 8. Answerer (`Arcana.Agent.Answerer`)
- Behaviour + LLM implementation (`Arcana.Agent.Answerer.LLM`)
- Generates answers from retrieved context
- Self-correcting answers with grounding evaluation
- Tracks correction history and count
- Custom prompt support

### Key Features

1. **Telemetry Integration**: All steps emit telemetry events via `:telemetry.span`
2. **Behaviour-based Extensibility**: Each component has a behaviour for custom implementations
3. **Error Propagation**: Context carries errors through pipeline, short-circuiting subsequent steps
4. **Self-Correction Loops**: Both search and answer steps support iterative improvement

---

## Portfolio Libraries Current State

### portfolio_core

**File**: `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/agent.ex`

Defines the `PortfolioCore.Ports.Agent` behaviour with:
- `run/2` - Execute agent task
- `available_tools/0` - List tool specifications
- `execute_tool/1` - Execute a tool call
- `max_iterations/0` - Return max iterations
- `get_state/0` - Get current agent state (optional)
- `process/3` - Process input within session
- `process_with_tools/4` - Process with tool execution

**Type definitions** for:
- tool_spec, parameter_spec, tool_call, tool_result
- agent_state, message, session

### portfolio_manager

**File**: `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/agent.ex`

Implements a **tool-using agent** for code analysis:
- Session-based conversation management
- Tool execution loop with max iterations
- Built-in tools: `search_code`, `read_file`, `list_files`, `get_graph_context`
- JSON parsing for tool calls and final answers
- Memory tracking across iterations

**File**: `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/agent/session.ex`

Session management with:
- Message history with timestamps
- Tool results tracking
- Context and metadata storage
- LLM message formatting
- Token estimation

**File**: `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/agent/tool.ex`

Tool framework with:
- Tool behaviour definition
- Built-in tools (search_code, read_file, list_files, get_graph_context)
- Argument validation
- LLM prompt formatting

### portfolio_index RAG Strategies

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/hybrid.ex`
- Combines vector and keyword search
- Reciprocal Rank Fusion (RRF) for result merging
- No query preprocessing

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/graph_rag.ex`
- Entity extraction from queries
- Graph traversal for related entities
- Local/Global/Hybrid search modes
- Community-based search

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/agentic.ex`
- Tool-based iterative retrieval
- Tools: semantic_search, keyword_search, get_context
- Agent loop with max iterations
- Basic tool call parsing

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/rag/strategies/self_rag.ex`
- Retrieval need assessment
- Self-critique with Relevance/Support/Completeness scores
- Answer refinement based on critique

### portfolio_index Reranker Adapters

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/reranker/llm.ex`
- LLM-based document reranking
- Scores 1-10, normalizes to 0-1
- Custom prompt templates
- Fallback to passthrough on failure

**File**: `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/reranker/passthrough.ex`
- No-op reranker for testing

---

## Identified Gaps

### Gap 1: Query Rewriting

- **Arcana Feature**: Dedicated `Rewriter` behaviour with LLM implementation that removes conversational noise while preserving technical terms. Configurable prompts, telemetry integration, inline function support.
- **Missing From**: `portfolio_index` RAG strategies
- **Implementation Complexity**: Low
- **Technical Details**:
  - Create `PortfolioCore.Ports.QueryRewriter` behaviour
  - Implement `PortfolioIndex.Adapters.QueryRewriter.LLM` adapter
  - Add rewrite step to RAG pipeline before embedding

### Gap 2: Query Expansion

- **Arcana Feature**: `Expander` behaviour with LLM implementation that adds synonyms, related terms, and expands abbreviations/acronyms.
- **Missing From**: `portfolio_index` RAG strategies
- **Implementation Complexity**: Low
- **Technical Details**:
  - Create `PortfolioCore.Ports.QueryExpander` behaviour
  - Implement `PortfolioIndex.Adapters.QueryExpander.LLM` adapter
  - Can also add thesaurus-based or embedding-based expansion

### Gap 3: Query Decomposition

- **Arcana Feature**: `Decomposer` behaviour that breaks complex questions into 2-4 simpler sub-questions. Each sub-question is searched independently, improving retrieval for multi-faceted queries.
- **Missing From**: `portfolio_index` RAG strategies
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Create `PortfolioCore.Ports.QueryDecomposer` behaviour
  - Implement `PortfolioIndex.Adapters.QueryDecomposer.LLM` adapter
  - Modify search to handle multiple queries and merge results
  - GraphRAG already extracts entities but doesn't decompose to sub-questions

### Gap 4: Collection/Index Selection (LLM-based Routing)

- **Arcana Feature**: `Selector` behaviour with LLM implementation that:
  - Fetches collection descriptions from database
  - Uses LLM to select most relevant collections
  - Returns reasoning for decisions
  - Supports deterministic routing via custom selectors
- **Missing From**: All portfolio libraries
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Create `PortfolioCore.Ports.IndexSelector` behaviour
  - Implement `PortfolioIndex.Adapters.IndexSelector.LLM` adapter
  - Add collection/index metadata storage
  - Integrate with RAG strategies for multi-index scenarios

### Gap 5: Self-Correcting Search

- **Arcana Feature**: Search with self-correction loop:
  1. Execute search
  2. LLM evaluates if results are sufficient
  3. If not, LLM rewrites query
  4. Repeat until sufficient or max iterations
- **Missing From**: `portfolio_index` Agentic strategy has iteration but no sufficiency check or query rewriting
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Add sufficiency evaluation to search loop
  - Implement query rewriting on insufficient results
  - Track iteration count and final query used
  - Configurable max_iterations and custom prompts

### Gap 6: Self-Correcting Answers (Grounding Evaluation)

- **Arcana Feature**: Answer generation with grounding evaluation:
  1. Generate answer
  2. LLM evaluates if answer is grounded in context
  3. If not, LLM provides feedback
  4. Generate corrected answer based on feedback
  5. Track correction history
- **Missing From**: `portfolio_index/self_rag.ex` has self-critique but not grounding-based correction
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Current SelfRAG has Relevance/Support/Completeness scores
  - Add explicit grounding evaluation (claims vs context)
  - Add correction loop with feedback-based regeneration
  - Track correction history for debugging

### Gap 7: Pipeline Context Object

- **Arcana Feature**: `Context` struct that flows through entire pipeline, accumulating:
  - Original question
  - Rewritten query
  - Expanded query
  - Sub-questions
  - Selected collections
  - Search results
  - Rerank scores
  - Final answer
  - Context used
  - Correction history
  - Errors
- **Missing From**: Portfolio strategies return flat result maps
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Create `PortfolioIndex.RAG.Context` struct
  - Modify strategies to work with context
  - Enable pipeline composition with `|>` operator
  - Add error propagation through pipeline

### Gap 8: Unified Reranker Integration in Agent Pipeline

- **Arcana Feature**: Reranker is a first-class pipeline step with:
  - Threshold filtering (default 7/10)
  - Score tracking in context
  - Telemetry integration
  - Chunk deduplication by ID
- **Missing From**: `portfolio_index` has `Reranker.LLM` adapter but it's not integrated into strategies
- **Implementation Complexity**: Low
- **Technical Details**:
  - Add rerank step to RAG strategies
  - Wire up existing `Reranker.LLM` adapter
  - Add threshold configuration
  - Track scores in result metadata

### Gap 9: Behaviour-based Component Extensibility

- **Arcana Feature**: Every pipeline component (Rewriter, Expander, Decomposer, Selector, Searcher, Reranker, Answerer) has:
  - A behaviour definition
  - A default LLM implementation
  - Support for custom modules
  - Support for inline functions
- **Missing From**: Portfolio adapters exist but not as composable pipeline components
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Create behaviours for each component in `portfolio_core/ports/`
  - Implement LLM-based adapters in `portfolio_index/adapters/`
  - Add inline function support for quick customization
  - Enable mix-and-match of implementations

### Gap 10: Telemetry Spans for Pipeline Steps

- **Arcana Feature**: Each step wrapped in `:telemetry.span` with:
  - Start metadata (question, component name)
  - Stop metadata (results, counts)
  - Consistent event naming ([:arcana, :agent, :step_name])
- **Missing From**: Some portfolio strategies emit telemetry but inconsistently
- **Implementation Complexity**: Low
- **Technical Details**:
  - Standardize telemetry event names across portfolio libraries
  - Use `:telemetry.span` for all pipeline steps
  - Include duration, token usage, result counts

---

## Implementation Priority

### Priority 1 - High Value, Low Complexity
1. **Query Rewriting** - Immediate improvement to query quality
2. **Query Expansion** - Better recall without complex changes
3. **Reranker Integration** - Already implemented, needs wiring

### Priority 2 - High Value, Medium Complexity
4. **Pipeline Context Object** - Enables composition and debugging
5. **Self-Correcting Search** - Significant quality improvement
6. **Collection/Index Selection** - Essential for multi-collection scenarios

### Priority 3 - Medium Value, Medium Complexity
7. **Query Decomposition** - Helps with complex queries
8. **Self-Correcting Answers** - Quality improvement for answers
9. **Behaviour-based Extensibility** - Long-term maintainability

### Priority 4 - Foundation/Infrastructure
10. **Telemetry Spans** - Observability, can be added incrementally

---

## Technical Dependencies

### Dependency Graph

```
Telemetry Spans (standalone)
    |
Pipeline Context Object
    |
    +-- Query Rewriting
    +-- Query Expansion
    +-- Query Decomposition
    +-- Collection Selection
    +-- Self-Correcting Search
    +-- Reranker Integration
    +-- Self-Correcting Answers
    |
Behaviour-based Extensibility (refactoring)
```

### Implementation Order

1. **Phase 1: Foundation**
   - Create `PortfolioIndex.RAG.Pipeline.Context` struct
   - Add telemetry span wrapper utility

2. **Phase 2: Query Processing**
   - Implement Query Rewriter port + LLM adapter
   - Implement Query Expander port + LLM adapter
   - Implement Query Decomposer port + LLM adapter

3. **Phase 3: Search Enhancement**
   - Implement Collection Selector port + LLM adapter
   - Add self-correcting search loop to Agentic strategy
   - Integrate Reranker into strategy pipelines

4. **Phase 4: Answer Quality**
   - Add grounding evaluation to SelfRAG
   - Implement answer correction loop

5. **Phase 5: Refactoring**
   - Standardize all components as behaviours
   - Add inline function support throughout
   - Unified telemetry across all libraries

---

## Summary

The Arcana agent system provides a mature, well-architected RAG pipeline with:
- 7 distinct pipeline components, each with behaviour + implementation
- Self-correcting loops for both search and answer generation
- LLM-based query preprocessing (rewrite, expand, decompose)
- LLM-based collection routing
- Comprehensive telemetry
- Error propagation through pipeline context

The portfolio libraries have foundational pieces:
- Tool-based agents in portfolio_manager
- RAG strategies in portfolio_index (Hybrid, GraphRAG, Agentic, SelfRAG)
- Reranker adapters (LLM, Passthrough)
- Port behaviours in portfolio_core

**10 gaps identified**, with the most impactful being:
1. Query preprocessing (rewrite, expand, decompose)
2. Self-correcting search
3. Collection selection/routing
4. Pipeline context for composition

These gaps can be addressed incrementally, with low-complexity items providing immediate value while building toward the full pipeline architecture.
