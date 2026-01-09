# LLM Integration Gap Analysis

## Executive Summary

This analysis compares the LLM integration patterns between Arcana and the Portfolio libraries (portfolio_core, portfolio_index, portfolio_manager). Arcana uses a lightweight protocol-based approach with built-in RAG agent components, while Portfolio has a more formal port/adapter architecture with multi-provider support but lacks several RAG-specific query processing features.

---

## Arcana LLM Capabilities

### Core Protocol (`Arcana.LLM`)

Arcana defines a simple protocol for LLM integration with three implementations:

1. **Function-based** - Anonymous functions with 1-3 arity for testing/flexibility
2. **String-based** - Model strings via `ReqLLM` (e.g., `"openai:gpt-4o-mini"`, `"zai:glm-4.5-flash"`)
3. **Tuple-based** - `{model_string, opts}` for passing API keys and other options

**Key Features:**
- Single `complete/4` callback: `(llm, prompt, context, opts) -> {:ok, response} | {:error, reason}`
- Built-in telemetry via `Arcana.LLM.Helpers.with_telemetry/4`
- Context formatting with `format_context/1` for RAG scenarios
- Default system prompt generation with context injection

### Agent Pipeline Components (RAG-Specific)

Arcana provides a rich set of LLM-powered RAG components:

| Component | Module | Purpose |
|-----------|--------|---------|
| Query Rewriter | `Arcana.Agent.Rewriter.LLM` | Transforms conversational input into search queries |
| Query Expander | `Arcana.Agent.Expander.LLM` | Adds synonyms and related terms for better recall |
| Query Decomposer | `Arcana.Agent.Decomposer.LLM` | Breaks complex queries into sub-questions |
| Collection Selector | `Arcana.Agent.Selector.LLM` | Routes queries to relevant collections |
| Reranker | `Arcana.Agent.Reranker.LLM` | Scores chunk relevance with LLM judgment |
| Answerer | `Arcana.Agent.Answerer.LLM` | Generates final answers from context |

### Structured Output Patterns

Arcana uses JSON-based structured outputs for several components:

1. **Selector** - Returns `{"collections": [...], "reasoning": "..."}`
2. **Decomposer** - Returns `{"sub_questions": ["q1", "q2", ...]}`
3. **Reranker** - Returns `{"score": <0-10>, "reasoning": "..."}`

All components include robust JSON extraction with fallback handling.

### Pipeline Context (`Arcana.Agent.Context`)

A comprehensive struct that flows through the pipeline tracking:
- Input: `question`, `repo`, `llm`
- Query Processing: `rewritten_query`, `expanded_query`, `sub_questions`
- Routing: `collections`, `selection_reasoning`
- Retrieval: `results`, `rerank_scores`
- Output: `answer`, `context_used`, `correction_count`, `corrections`
- Error handling: `error`

---

## Portfolio Libraries Current State

### PortfolioCore.Ports.LLM (Behaviour Definition)

Formal port specification with comprehensive callbacks:

| Callback | Signature | Description |
|----------|-----------|-------------|
| `complete/2` | `([message], opts) -> {:ok, completion_result} | {:error, term}` | Synchronous completion |
| `stream/2` | `([message], opts) -> {:ok, Enumerable.t} | {:error, term}` | Streaming completion |
| `supported_models/0` | `() -> [String.t()]` | List available models |
| `model_info/1` | `(model) -> %{context_window, max_output, supports_tools}` | Model metadata |

**Structured Types:**
- `message` - `%{role: :system | :user | :assistant, content: String.t()}`
- `completion_result` - `%{content, model, usage, finish_reason}`
- `stream_chunk` - `%{delta, finish_reason}`

### PortfolioIndex LLM Adapters

Six provider implementations:

1. **Anthropic** (`PortfolioIndex.Adapters.LLM.Anthropic`)
   - Uses `claude_agent_sdk`
   - Supports SDK direct calls and `ClaudeAgentSDK.Streaming`
   - Dynamic SDK function detection

2. **Gemini** (`PortfolioIndex.Adapters.LLM.Gemini`)
   - Uses `gemini_ex`
   - Safety rating handling
   - Retry logic for empty responses

3. **OpenAI** (`PortfolioIndex.Adapters.LLM.OpenAI`)
   - Uses `openai_ex`
   - OpenAI Chat Completions API
   - Stream event transformation

4. **Codex** (`PortfolioIndex.Adapters.LLM.Codex`)
   - Uses `codex_sdk`
   - Thread-based execution support
   - Agentic run streaming

5. **Ollama** (`PortfolioIndex.Adapters.LLM.Ollama`)
   - Uses `ollixir`
   - Local model orchestration
   - OpenAI-style message formatting

6. **vLLM** (`PortfolioIndex.Adapters.LLM.VLLM`)
   - OpenAI-compatible API via `openai_ex`
   - Configurable base URL for local clusters
   - SSE stream parsing

All adapters implement:
- Token usage normalization
- Finish reason mapping
- Telemetry emission
- Streaming support

### PortfolioIndex RAG Strategies

| Strategy | LLM Usage |
|----------|-----------|
| `SelfRAG` | Retrieval assessment, answer generation with self-critique, refinement |
| `Agentic` | Tool-based iterative retrieval with JSON action parsing |
| `Hybrid` | No direct LLM usage (RRF-based) |
| `GraphRAG` | Community summarization (LLM for synthesis) |

### PortfolioIndex Reranker

`PortfolioIndex.Adapters.Reranker.LLM`:
- JSON-based scoring prompt
- Score parsing with fallback to passthrough
- Normalized 0-1 score output

### PortfolioManager.Generation

State container for RAG pipeline tracking:
- `query`, `query_embedding`, `retrieval_results`
- `context`, `context_sources`, `prompt`, `response`
- `evaluations`, `metadata`, `halted?`, `errors`

Uses builder pattern: `new/2 |> with_embedding/2 |> with_retrieval/2 |> ...`

---

## Identified Gaps

### Gap 1: Query Rewriting

- **Arcana Feature**: `Arcana.Agent.Rewriter.LLM` transforms conversational input (e.g., "Hey, can you tell me about Elixir?") into clean search queries ("Elixir programming language")
- **Missing From**: portfolio_index, portfolio_core
- **Implementation Complexity**: Low
- **Technical Details**:
  - Requires single LLM call with simple prompt template
  - No structured output - just string response
  - Can use existing LLM adapters directly
  - Portfolio has no pre-processing of user queries before embedding

### Gap 2: Query Expansion

- **Arcana Feature**: `Arcana.Agent.Expander.LLM` adds synonyms and related terms to improve retrieval recall (e.g., "ML models" -> "ML machine learning models neural networks deep learning")
- **Missing From**: portfolio_index, portfolio_core
- **Implementation Complexity**: Low
- **Technical Details**:
  - Single LLM call with expansion prompt
  - Improves recall for abbreviations and technical terms
  - Could be integrated into `PortfolioIndex.RAG.Strategy` interface
  - Portfolio currently does direct query-to-embedding without term expansion

### Gap 3: Query Decomposition

- **Arcana Feature**: `Arcana.Agent.Decomposer.LLM` breaks complex questions into simpler sub-questions for parallel retrieval (e.g., "Compare Elixir and Go" -> ["Elixir features", "Go features", "performance comparison"])
- **Missing From**: portfolio_index, portfolio_core
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Returns JSON `{"sub_questions": [...]}` with fallback handling
  - Requires aggregation logic for multiple retrieval results
  - Portfolio's `Agentic` strategy does iterative retrieval but not query decomposition
  - Would need `Generation` struct extension or new preprocessing module

### Gap 4: Collection/Index Selection

- **Arcana Feature**: `Arcana.Agent.Selector.LLM` uses LLM to route queries to relevant collections based on descriptions
- **Missing From**: portfolio_index
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Returns JSON `{"collections": [...], "reasoning": "..."}`
  - Requires collection descriptions/metadata
  - Portfolio assumes single-index queries or manual specification
  - Could be added to `AdapterResolver` or as new strategy

### Gap 5: Lightweight Protocol-Based LLM Interface

- **Arcana Feature**: Simple `Arcana.LLM` protocol that accepts functions, strings, or tuples without formal behaviour callbacks
- **Missing From**: portfolio_core (has formal behaviour only)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana's approach enables easier testing with anonymous functions
  - Portfolio requires implementing full behaviour
  - Could add protocol defimpl for Portfolio's behaviour modules
  - Trade-off: Arcana is more flexible, Portfolio is more type-safe

### Gap 6: Context-Aware System Prompts

- **Arcana Feature**: `Arcana.LLM.Helpers.default_system_prompt/1` automatically generates system prompts with injected context
- **Missing From**: portfolio_index LLM adapters
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana auto-formats context chunks into system prompt
  - Portfolio adapters expect pre-formatted messages
  - RAG strategies manually build context but no standard helper
  - Could add to `PortfolioIndex.RAG.ContextBuilder` or similar

### Gap 7: Unified Pipeline Context Struct

- **Arcana Feature**: `Arcana.Agent.Context` tracks full pipeline state including query transformations, routing decisions, and correction history
- **Missing From**: Partial coverage in portfolio_manager
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Arcana tracks: `rewritten_query`, `expanded_query`, `sub_questions`, `collections`, `selection_reasoning`, `correction_count`, `corrections`
  - Portfolio's `Generation` tracks: `query_embedding`, `retrieval_results`, `context`, `response`, `evaluations`
  - Missing: query transformation tracking, routing decisions, self-correction history
  - Would need `Generation` struct extension

### Gap 8: Self-Correction with Critique History

- **Arcana Feature**: Context tracks `correction_count` and `corrections` list of `{answer, feedback}` tuples
- **Missing From**: portfolio_index strategies
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Arcana enables iterative answer refinement with feedback tracking
  - Portfolio's `SelfRAG` does single refinement but doesn't track history
  - Useful for debugging and answer quality analysis
  - Would need extension to `SelfRAG` strategy and `Generation` struct

### Gap 9: Customizable Prompt Functions

- **Arcana Feature**: All agent components accept `:prompt` option as custom function (e.g., `answer(ctx, prompt: fn question, chunks -> ... end)`)
- **Missing From**: portfolio_index adapters
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana: `prompt_fn.(question, chunks)` or `prompt_fn.(question)` patterns
  - Portfolio uses hardcoded prompt templates
  - Only `Reranker.LLM` has `:prompt_template` option
  - Easy addition to all LLM-using components

### Gap 10: Multi-Provider via ReqLLM

- **Arcana Feature**: Single `ReqLLM` dependency handles multiple providers via model string format ("openai:...", "zai:...", "anthropic:...")
- **Missing From**: portfolio_index (separate adapter per provider)
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Arcana: One protocol, one dependency, many providers
  - Portfolio: Separate Anthropic, Gemini, OpenAI adapters with different SDKs
  - Trade-off: Arcana is simpler, Portfolio offers provider-specific optimizations
  - Could add `ReqLLM` adapter as alternative implementation

---

## Implementation Priority

### High Priority (Essential for RAG Quality)

1. **Query Rewriting** - Immediate impact on search quality
2. **Query Expansion** - Significant recall improvement
3. **Customizable Prompt Functions** - Enables domain-specific tuning

### Medium Priority (Enhanced RAG Capabilities)

4. **Query Decomposition** - Complex query handling
5. **Collection Selection** - Multi-index routing
6. **Unified Pipeline Context** - Better observability

### Lower Priority (Nice-to-Have)

7. **Self-Correction History** - Debugging/analysis
8. **Context-Aware System Prompts** - Developer convenience
9. **Lightweight Protocol Interface** - Testing flexibility
10. **Multi-Provider via ReqLLM** - Simplification option

---

## Technical Dependencies

### For Query Processing Gaps (1-4)

- Existing LLM adapters (no new dependencies)
- JSON parsing (already available)
- `PortfolioIndex.RAG.Strategy` extension or new preprocessing module

### For Context/Pipeline Gaps (7-8)

- Extension of `PortfolioManager.Generation` struct
- Backward-compatible field additions

### For Interface Gaps (5, 9, 10)

- Optional: Protocol definitions for existing behaviours
- Optional: `req_llm` dependency for unified provider access

### Integration Points

| Gap | Integration Location |
|-----|---------------------|
| Query Rewriting | New `PortfolioIndex.RAG.QueryProcessor` module |
| Query Expansion | Same as above or inline in strategies |
| Query Decomposition | New module with `Generation` integration |
| Collection Selection | `PortfolioIndex.RAG.AdapterResolver` or new router |
| Prompt Functions | Options for existing LLM adapters and Reranker |
| Pipeline Context | `PortfolioManager.Generation` struct extension |

---

## Recommendations

1. **Create `PortfolioIndex.RAG.QueryProcessor`** - Unified module for rewriting, expansion, and decomposition with pluggable implementations

2. **Extend `PortfolioManager.Generation`** - Add fields for query transformations and routing decisions to enable full pipeline observability

3. **Add `:prompt` option to LLM-using components** - Low-effort change with high customization value

4. **Consider `ReqLLM` adapter** - As optional lightweight alternative to provider-specific adapters for simpler deployments

5. **Document structured output patterns** - Create standard for JSON response parsing with fallback handling across all components
