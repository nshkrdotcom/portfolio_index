# Evaluation System Gap Analysis

## Executive Summary

This document analyzes the evaluation capabilities in Arcana's RAG framework compared to the portfolio libraries (PortfolioCore and PortfolioManager). While both systems address RAG evaluation, they take fundamentally different approaches: **Arcana focuses on retrieval quality metrics with test case management**, while **portfolio libraries focus on generation quality assessment using the RAG Triad framework**. These are complementary systems with significant gaps in both directions.

---

## Arcana Evaluation Capabilities

### 1. Core Evaluation Architecture

Arcana provides a comprehensive retrieval evaluation framework with the following components:

#### 1.1 Evaluation Module (`Arcana.Evaluation`)
- **Main entry point** for all evaluation operations
- Coordinates test case generation, evaluation runs, and metrics aggregation
- Supports multiple search modes: `:semantic`, `:fulltext`, `:hybrid`
- Optional answer evaluation with faithfulness scoring

#### 1.2 Test Case System (`Arcana.Evaluation.TestCase`)
- Ecto schema for persisting test cases in database
- Tracks `question` with linked `relevant_chunks` (ground truth)
- Two sources: `:synthetic` (LLM-generated) or `:manual` (user-created)
- Many-to-many relationship with chunks via join table
- Enables reproducible evaluation across runs

#### 1.3 Synthetic Test Case Generator (`Arcana.Evaluation.Generator`)
- LLM-powered question generation from document chunks
- Random sampling with configurable `sample_size`
- Filtering by `source_id` or `collection`
- Customizable prompt templates with `{chunk_text}` placeholder
- Default prompt ensures questions are specific and searchable

#### 1.4 Retrieval Metrics (`Arcana.Evaluation.Metrics`)
Standard IR (Information Retrieval) metrics at K=[1, 3, 5, 10]:
- **Recall@K**: Fraction of relevant docs in top K results
- **Precision@K**: Fraction of top K that are relevant
- **MRR (Mean Reciprocal Rank)**: 1/position of first relevant result
- **Hit Rate@K**: Binary indicator of any relevant doc in top K

Aggregation across test cases with automatic averaging.

#### 1.5 Answer Quality Metrics (`Arcana.Evaluation.AnswerMetrics`)
- **Faithfulness Scoring**: LLM-as-judge evaluation (0-10 scale)
- Evaluates if generated answers are grounded in retrieved context
- Customizable evaluation prompts
- Returns score with reasoning explanation

#### 1.6 Evaluation Run Persistence (`Arcana.Evaluation.Run`)
- Ecto schema for storing evaluation runs
- Tracks status: `:running`, `:completed`, `:failed`
- Stores configuration, aggregate metrics, and per-case results
- Enables historical comparison and trend analysis

#### 1.7 Mix Tasks (CLI Interface)
**`mix arcana.eval.generate`**:
- Generates synthetic test cases from chunks
- Options: `--sample-size`, `--source-id`, `--collection`

**`mix arcana.eval.run`**:
- Executes evaluation against test cases
- Options: `--mode`, `--source-id`, `--generate`, `--format`, `--fail-under`
- Supports JSON output for CI integration
- Threshold-based CI failure (`--fail-under` for recall@5)

### 2. Key Arcana Features

| Feature | Description |
|---------|-------------|
| Test Case Persistence | Database-backed test cases for reproducibility |
| Synthetic Generation | LLM generates questions from chunks |
| Manual Test Cases | User-defined ground truth |
| Multi-mode Evaluation | Compare semantic, fulltext, hybrid |
| Run History | Track evaluation over time |
| CI Integration | `--fail-under` threshold checking |
| Answer Evaluation | Optional faithfulness scoring |
| Per-case Results | Drill-down into failures |

---

## Portfolio Libraries Current State

### 1. PortfolioCore.Ports.Evaluation (Port Specification)

Defines the evaluation behavior contract with:

#### 1.1 RAG Triad Framework (TruLens-based)
Three evaluation dimensions scored 1-5:
- **Context Relevance**: Is retrieved context relevant to query?
- **Groundedness**: Is response supported by context?
- **Answer Relevance**: Does answer address the query?

#### 1.2 Hallucination Detection
- Binary detection with evidence explanation
- Strict mode option for safety-critical applications

#### 1.3 Callback Specifications
```elixir
@callback evaluate_rag_triad(generation(), opts) :: {:ok, triad_result()} | {:error, term()}
@callback evaluate_context_relevance(generation(), opts) :: {:ok, triad_score()} | {:error, term()}
@callback evaluate_groundedness(generation(), opts) :: {:ok, triad_score()} | {:error, term()}
@callback evaluate_answer_relevance(generation(), opts) :: {:ok, triad_score()} | {:error, term()}
@callback detect_hallucination(generation(), opts) :: {:ok, hallucination_result()} | {:error, term()}
```

### 2. PortfolioManager.Evaluation (Implementation)

#### 2.1 Full RAG Triad Implementation
- Implements all PortfolioCore.Ports.Evaluation callbacks
- Sequential evaluation of all three dimensions
- Overall score as average of three dimensions
- LLM-powered assessment via Router.complete

#### 2.2 Prompt Engineering
- Structured prompts for each evaluation type
- JSON response format with score and reasoning
- Robust JSON extraction from LLM responses

#### 2.3 Telemetry Integration
- Events for `:rag_triad` and `:hallucination` evaluations
- Duration tracking for performance monitoring
- Metadata includes generation_id and result

### 3. Key Portfolio Features

| Feature | Description |
|---------|-------------|
| RAG Triad Scoring | 1-5 scale with reasoning |
| Context Relevance | Query-context alignment |
| Groundedness | Response-context support |
| Answer Relevance | Response-query alignment |
| Hallucination Detection | Binary with evidence |
| Telemetry | Observable evaluation metrics |

---

## Identified Gaps

### Gap 1: Test Case Persistence System
- **Arcana Feature**: Complete Ecto-based test case storage with:
  - `arcana_evaluation_test_cases` table
  - `arcana_evaluation_test_case_chunks` join table
  - Source tracking (synthetic vs manual)
  - Question-to-chunk ground truth relationships
- **Missing From**: PortfolioCore (no port), PortfolioManager (no implementation)
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Requires Ecto schema definitions
  - Migration for test_cases and join table
  - API for CRUD operations on test cases
  - Integration with existing chunk schema from PortfolioIndex

### Gap 2: Synthetic Test Case Generation
- **Arcana Feature**: LLM-powered question generation from chunks with:
  - Random sampling of chunks
  - Customizable prompts with `{chunk_text}` placeholder
  - Filtering by source_id or collection
  - Automatic linking of source chunk as ground truth
- **Missing From**: PortfolioCore, PortfolioManager
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Requires LLM adapter integration
  - Chunk access/sampling logic
  - Prompt template system
  - Test case creation workflow

### Gap 3: Retrieval Quality Metrics (IR Metrics)
- **Arcana Feature**: Standard information retrieval metrics:
  - Recall@K (K=1,3,5,10)
  - Precision@K
  - Mean Reciprocal Rank (MRR)
  - Hit Rate@K
  - Aggregation across test cases
- **Missing From**: PortfolioCore (no port), PortfolioManager (no implementation)
- **Implementation Complexity**: Low-Medium
- **Technical Details**:
  - Pure computation functions (no external dependencies)
  - Requires test case with expected chunk IDs
  - Requires search results with retrieved chunk IDs
  - K-value configuration

### Gap 4: Evaluation Run Persistence
- **Arcana Feature**: Complete run tracking with:
  - `arcana_evaluation_runs` Ecto schema
  - Status tracking (running/completed/failed)
  - Stored configuration for reproducibility
  - Aggregate metrics storage
  - Per-case results for drill-down
  - Historical comparison capability
- **Missing From**: PortfolioCore, PortfolioManager
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Ecto schema with JSON fields for metrics/results/config
  - Run lifecycle management
  - Query APIs for historical runs
  - Integration with metrics computation

### Gap 5: CLI Tooling for Evaluation
- **Arcana Feature**: Mix tasks for evaluation workflow:
  - `mix arcana.eval.generate` for test case generation
  - `mix arcana.eval.run` for evaluation execution
  - Multiple output formats (table, JSON)
  - CI integration with `--fail-under` threshold
  - Auto-generation when no test cases exist
- **Missing From**: PortfolioCore, PortfolioManager, PortfolioIndex
- **Implementation Complexity**: Low
- **Technical Details**:
  - Mix.Task implementations
  - Option parsing with OptionParser
  - Output formatting functions
  - Integration with evaluation APIs

### Gap 6: Faithfulness Scoring Port
- **Arcana Feature**: `AnswerMetrics.evaluate_faithfulness/4` with:
  - 0-10 scale scoring
  - LLM-as-judge approach
  - Customizable prompt function
  - JSON response parsing with clamping
- **Missing From**: PortfolioCore (partial - groundedness is similar but not identical)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana uses 0-10 scale, Portfolio uses 1-5
  - Arcana evaluates full answer faithfulness
  - Portfolio's groundedness is response-to-context only
  - Different prompt structures and semantics

### Gap 7: Multi-Mode Evaluation Comparison
- **Arcana Feature**: Evaluation across search modes:
  - Semantic search evaluation
  - Fulltext search evaluation
  - Hybrid search evaluation
  - Same test cases across all modes for fair comparison
- **Missing From**: PortfolioCore, PortfolioManager
- **Implementation Complexity**: Low (if search modes exist)
- **Technical Details**:
  - Parameterized search mode in evaluation
  - Configuration storage per run
  - Cross-mode comparison reporting

### Gap 8: Ground Truth Management
- **Arcana Feature**: Multiple relevant chunks per test case:
  - Many-to-many relationship
  - Manual addition of relevant chunks
  - Source chunk tracking for synthetic cases
  - Bulk operations via insert_all
- **Missing From**: PortfolioCore, PortfolioManager
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Join table schema
  - API for managing ground truth
  - Preloading for evaluation

### Gap 9: Evaluation Port Definition
- **Arcana Feature**: (Implicit - no explicit port but cohesive API)
- **Missing From**: PortfolioCore lacks retrieval evaluation port
- **Implementation Complexity**: Low
- **Technical Details**:
  - Port for retrieval metrics computation
  - Port for test case generation
  - Port for evaluation run management
  - Integration with existing Evaluation port

### Gap 10: Per-Case Result Drill-Down
- **Arcana Feature**: Detailed per-test-case results including:
  - Expected chunk IDs
  - Retrieved chunk IDs
  - Per-K recall/precision values
  - Reciprocal rank
  - Hit indicators
- **Missing From**: PortfolioManager (evaluates single generations, no aggregation)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Return structure enhancement
  - Storage in run results map
  - Query APIs for analysis

### Gap 11: Threshold-Based CI Failure
- **Arcana Feature**: `--fail-under` option for CI pipelines:
  - Exit code 1 if recall@5 below threshold
  - Clear pass/fail output
  - Configurable threshold value
- **Missing From**: PortfolioCore, PortfolioManager, PortfolioIndex
- **Implementation Complexity**: Low
- **Technical Details**:
  - CLI flag parsing
  - Threshold comparison logic
  - Exit code management

### Gap 12: Collection-Based Filtering
- **Arcana Feature**: Filter evaluation by collection:
  - Generator supports `--collection` option
  - Joins to collection via document relationship
  - Scoped test case generation
- **Missing From**: PortfolioCore, PortfolioManager
- **Implementation Complexity**: Low
- **Technical Details**:
  - Requires collection association in schema
  - Query filtering enhancement
  - CLI option addition

---

## Reverse Gaps (Portfolio Features Missing from Arcana)

### Reverse Gap 1: Context Relevance Scoring
- **Portfolio Feature**: Query-to-context relevance evaluation
- **Arcana Status**: Not implemented - focuses on retrieval, not context quality
- **Notes**: Could be valuable addition to answer evaluation

### Reverse Gap 2: Answer Relevance Scoring
- **Portfolio Feature**: Response-to-query alignment evaluation
- **Arcana Status**: Not implemented - faithfulness only checks groundedness
- **Notes**: Complements faithfulness scoring

### Reverse Gap 3: Hallucination Detection with Evidence
- **Portfolio Feature**: Binary hallucination detection with explanation
- **Arcana Status**: Partial - faithfulness score implies but doesn't explicitly detect
- **Notes**: More actionable for content filtering

### Reverse Gap 4: Telemetry Integration
- **Portfolio Feature**: Observable evaluation with telemetry events
- **Arcana Status**: No telemetry integration
- **Notes**: Important for production monitoring

---

## Implementation Priority

### Priority 1: Critical (Needed for RAG Quality Assurance)
1. **Gap 3: Retrieval Quality Metrics** - Core IR metrics (Low-Medium complexity)
2. **Gap 9: Evaluation Port Definition** - Contract for retrieval evaluation (Low complexity)
3. **Gap 1: Test Case Persistence** - Foundation for reproducible evaluation (Medium complexity)

### Priority 2: High (Enable Automated Evaluation)
4. **Gap 2: Synthetic Test Case Generation** - Scalable test creation (Medium complexity)
5. **Gap 4: Evaluation Run Persistence** - Historical tracking (Medium complexity)
6. **Gap 8: Ground Truth Management** - Multiple relevant chunks (Medium complexity)

### Priority 3: Medium (CI/CD Integration)
7. **Gap 5: CLI Tooling** - Developer experience (Low complexity)
8. **Gap 11: Threshold-Based CI Failure** - Automated quality gates (Low complexity)
9. **Gap 7: Multi-Mode Evaluation** - Search mode comparison (Low complexity)

### Priority 4: Enhancement (Improved Analysis)
10. **Gap 10: Per-Case Drill-Down** - Failure analysis (Low complexity)
11. **Gap 6: Faithfulness Scoring Port** - Answer quality (Low complexity)
12. **Gap 12: Collection-Based Filtering** - Scoped evaluation (Low complexity)

---

## Technical Dependencies

### For PortfolioCore (Port Definitions)
| Gap | Dependencies |
|-----|--------------|
| Gap 9: Evaluation Port | None (pure specification) |
| Gap 3: Retrieval Metrics Port | Gap 9 |

### For PortfolioIndex (Adapters)
| Gap | Dependencies |
|-----|--------------|
| Gap 3: Retrieval Metrics Adapter | Gap 9 port, Chunk schema |
| Gap 1: Test Case Schema | Chunk schema, Ecto |
| Gap 8: Ground Truth | Gap 1 |
| Gap 4: Run Schema | Gap 1, Gap 3 |
| Gap 2: Generator | Gap 1, LLM adapter, Chunk access |

### For PortfolioManager (Integration)
| Gap | Dependencies |
|-----|--------------|
| Gap 7: Multi-Mode Eval | Search modes in manager |
| Gap 10: Per-Case Results | Gap 3, Gap 4 |
| Gap 5: CLI Tooling | All above gaps |
| Gap 11: CI Threshold | Gap 5 |

### External Dependencies
| Gap | External Dependency |
|-----|---------------------|
| Gap 2 | LLM provider (OpenAI, Anthropic, etc.) |
| Gap 6 | LLM provider for faithfulness |
| Gap 1, 4 | Ecto and PostgreSQL |

---

## Migration Strategy

### Phase 1: Foundation (PortfolioCore + PortfolioIndex)
1. Define retrieval evaluation port in PortfolioCore
2. Implement metrics computation adapter in PortfolioIndex
3. Add test case and run Ecto schemas to PortfolioIndex
4. Create migrations for evaluation tables

### Phase 2: Generation (PortfolioIndex)
1. Implement test case generator adapter
2. Add ground truth management APIs
3. Create synthetic test case generation workflow

### Phase 3: Integration (PortfolioManager)
1. Add evaluation orchestration to manager
2. Implement multi-mode evaluation
3. Add telemetry for evaluation events

### Phase 4: Tooling (All Libraries)
1. Create Mix tasks in appropriate library
2. Add CLI options for all features
3. Implement CI threshold checking
4. Add JSON output for automation

---

## Summary

The Arcana evaluation system provides a comprehensive **retrieval quality measurement framework** with test case persistence, synthetic generation, and standard IR metrics. The portfolio libraries currently focus on **generation quality assessment** via the RAG Triad framework.

**Key insight**: These are complementary systems. A complete RAG evaluation suite requires both:
- **Retrieval evaluation** (Arcana's strength): Did we find the right documents?
- **Generation evaluation** (Portfolio's strength): Did we produce a good answer?

The recommended approach is to:
1. Port Arcana's retrieval evaluation features to PortfolioIndex
2. Keep and enhance PortfolioManager's RAG Triad implementation
3. Create a unified evaluation workflow that assesses both retrieval and generation quality

Total gaps identified: **12 forward gaps** + **4 reverse gaps**
Implementation effort estimate: **3-4 weeks** for full feature parity
