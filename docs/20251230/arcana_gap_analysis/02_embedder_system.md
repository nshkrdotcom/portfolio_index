# Embedder System Gap Analysis

## Arcana Embedder Capabilities

Arcana provides a comprehensive embedding system with the following components:

### Core Behaviour (`Arcana.Embedder`)
- **Callback-based architecture**: Defines `embed/2`, `embed_batch/2`, and `dimensions/1` callbacks
- **Optional batch callback**: `embed_batch/2` is optional with automatic sequential fallback
- **Unified dispatch**: Helper functions `embed/2`, `embed_batch/2`, and `dimensions/1` that accept `{module, opts}` tuples
- **Flexible configuration**: Supports atoms (`:local`, `:openai`), tuples with options, custom functions, and custom modules

### Local Embedding Provider (`Arcana.Embedder.Local`)
- **Bumblebee/EXLA integration**: Uses Nx.Serving for batched inference
- **HuggingFace model support**: Loads models directly from HuggingFace Hub
- **Pre-configured model dimensions**: Knows dimensions for BGE, E5, GTE, and MiniLM models
- **Automatic dimension detection**: Falls back to runtime detection for unknown models
- **Supervision tree integration**: Provides `child_spec/1` for supervised serving
- **Configurable compilation**: Batch size 32, sequence length 512, EXLA compiler
- **Telemetry instrumentation**: `[:arcana, :embed]` span with text, model, and dimensions metadata

### OpenAI Provider (`Arcana.Embedder.OpenAI`)
- **ReqLLM integration**: Uses ReqLLM for API calls
- **Lazy dependency loading**: Checks for ReqLLM at runtime with helpful error messages
- **Model dimension mapping**: text-embedding-3-small (1536), text-embedding-3-large (3072), ada-002 (1536)
- **Automatic dimension detection**: Runtime detection for unknown models
- **Telemetry instrumentation**: Same span pattern as local embedder

### Custom Provider (`Arcana.Embedder.Custom`)
- **Function wrapper**: Wraps user-provided functions to implement the behaviour
- **Flexible function signature**: Accepts functions returning `{:ok, embedding}` or `{:error, reason}`
- **Optional dimension specification**: Can provide dimensions via opts or detect at runtime
- **Error handling**: Validates embedding result format

### Legacy Serving (`Arcana.Embeddings.Serving`)
- **Standalone Nx.Serving**: Simplified serving without behaviour pattern
- **Fixed model**: BAAI/bge-small-en-v1.5 (384 dimensions)
- **Direct API**: `embed/1` and `embed_batch/1` functions
- **Telemetry**: Same instrumentation pattern

## Portfolio Libraries Current State

### PortfolioCore Port (`PortfolioCore.Ports.Embedder`)
- **Behaviour definition**: Defines `embed/2`, `embed_batch/2`, `dimensions/1`, `supported_models/0`
- **Rich return types**: Returns structured maps with vector, model, dimensions, and token_count
- **Batch result type**: Includes total_tokens aggregation
- **Documentation**: Well-documented with examples and model suggestions

### PortfolioIndex Adapters

#### Gemini Adapter (`PortfolioIndex.Adapters.Embedder.Gemini`)
- **Full implementation**: Complete working adapter using gemini_ex
- **Configurable dimensions**: Supports 128-3072 dimension output
- **Automatic normalization**: Normalizes when required by model
- **Token estimation**: Estimates tokens from text length
- **Telemetry**: Emits `[:portfolio_index, :embedder, :embed]` and `[:portfolio_index, :embedder, :embed_batch]`
- **Model resolution**: Handles atoms, strings, and registry defaults

#### OpenAI Adapter (`PortfolioIndex.Adapters.Embedder.OpenAI`)
- **Placeholder only**: Returns `{:error, :not_implemented}` for all operations
- **No actual functionality**: Only defines dimensions and supported_models

## Identified Gaps

### Gap 1: Local Bumblebee/Nx.Serving Embedding Support
- **Arcana Feature**: Complete local embedding using Bumblebee with HuggingFace models, Nx.Serving supervision, EXLA compilation, and support for multiple model families (BGE, E5, GTE, MiniLM)
- **Missing From**: PortfolioIndex (no local embedding adapter exists)
- **Implementation Complexity**: High
- **Technical Details**:
  - Requires Bumblebee, EXLA, and Nx dependencies
  - Need to implement `child_spec/1` for supervision tree integration
  - Must handle model loading from HuggingFace Hub
  - Should maintain dimension mapping for common models
  - Needs batched inference configuration (batch_size, sequence_length)
  - Must integrate with PortfolioCore.Ports.Embedder behaviour (returning structured maps)

### Gap 2: OpenAI Embeddings Implementation
- **Arcana Feature**: Working OpenAI embeddings via ReqLLM with proper model handling and telemetry
- **Missing From**: PortfolioIndex.Adapters.Embedder.OpenAI (exists but not implemented)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana uses ReqLLM with model spec format "openai:#{model}"
  - Portfolio could use ReqLLM or direct Req calls
  - Need to implement actual API calls instead of returning `:not_implemented`
  - Must return structured result matching PortfolioCore.Ports.Embedder types
  - Add token counting from API response (OpenAI returns usage info)

### Gap 3: Custom Function Embedder
- **Arcana Feature**: Wraps arbitrary user functions as embedders, allowing `fn text -> {:ok, embedding} end` configuration
- **Missing From**: PortfolioIndex (no custom/function-based adapter)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Simple wrapper module that implements the behaviour
  - Accepts function via options and invokes it
  - Validates return type `{:ok, [float()]}` or `{:error, term()}`
  - Optional dimension specification or runtime detection
  - Useful for testing and ad-hoc integrations

### Gap 4: Unified Configuration System
- **Arcana Feature**: Single `:arcana, embedder:` config that accepts atoms, tuples, functions, or modules, with automatic resolution to `{module, opts}` tuple
- **Missing From**: PortfolioIndex lacks a unified embedder configuration resolver
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Config parsing logic to handle multiple formats:
    - `:local` -> `{Arcana.Embedder.Local, []}`
    - `{:local, model: "..."}` -> `{Arcana.Embedder.Local, [model: "..."]}`
    - `:openai` -> `{Arcana.Embedder.OpenAI, []}`
    - `fn text -> ... end` -> `{Arcana.Embedder.Custom, [fun: fn]}`
    - `MyModule` -> `{MyModule, []}`
    - `{MyModule, opts}` -> `{MyModule, opts}`
  - Currently PortfolioIndex uses explicit adapter modules without unified dispatch

### Gap 5: Automatic Dimension Detection
- **Arcana Feature**: All embedders can detect dimensions at runtime by embedding a test string when dimensions are not preconfigured
- **Missing From**: PortfolioIndex (Gemini relies on config, OpenAI is hardcoded)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Fall back to embedding "test" string and measuring result length
  - Cache detected dimensions to avoid repeated API calls
  - Useful when adding support for new models

### Gap 6: Embedder Model Dimension Registry
- **Arcana Feature**: `@model_dimensions` map containing known dimensions for popular models (BGE, E5, GTE, MiniLM families)
- **Missing From**: PortfolioIndex (no central dimension registry)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Central registry of model -> dimension mappings
  - BGE: small=384, base=768, large=1024
  - E5: small=384, base=768, large=1024
  - GTE: small=384, base=768, large=1024
  - OpenAI: text-embedding-3-small=1536, text-embedding-3-large=3072
  - Reduces need for runtime detection

### Gap 7: Lazy Dependency Validation
- **Arcana Feature**: Checks `Code.ensure_loaded?(ReqLLM)` at runtime with helpful error messages
- **Missing From**: PortfolioIndex adapters assume dependencies are available
- **Implementation Complexity**: Low
- **Technical Details**:
  - Runtime check for optional dependencies before use
  - Raise clear error with installation instructions
  - Allows adapters to exist without requiring all dependencies

### Gap 8: Serving Child Spec for Supervision
- **Arcana Feature**: Local embedder provides `child_spec/1` for direct supervision tree integration
- **Missing From**: PortfolioIndex has no supervised serving pattern
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Implement `child_spec/1` returning proper spec with id, start, type
  - Allow multiple servings with different models via unique names
  - Use `Module.concat(__MODULE__, model)` pattern for naming
  - Enables hot model swapping and graceful restarts

### Gap 9: Token Count in Return Types
- **Arcana Feature**: N/A (Arcana returns raw embedding without token count)
- **Portfolio Feature Exists**: PortfolioCore.Ports.Embedder specifies `token_count` in result
- **Status**: Portfolio is MORE complete here - Arcana lacks token counting
- **Note**: This is a reverse gap - portfolio has this, Arcana doesn't

### Gap 10: Supported Models Callback
- **Portfolio Feature**: `supported_models/0` callback exists in PortfolioCore.Ports.Embedder
- **Arcana Lacks**: No equivalent callback in Arcana.Embedder behaviour
- **Status**: Portfolio is MORE complete here
- **Note**: This is a reverse gap - portfolio has this, Arcana doesn't

## Implementation Priority

1. **OpenAI Embeddings Implementation** (Low complexity, High value)
   - Complete the existing placeholder adapter
   - Immediate unblocking for OpenAI-based workflows

2. **Local Bumblebee/Nx.Serving Adapter** (High complexity, High value)
   - Enable fully local RAG without API costs
   - Critical for offline/private deployments

3. **Custom Function Embedder** (Low complexity, Medium value)
   - Useful for testing and prototyping
   - Enables quick integrations without full adapter

4. **Model Dimension Registry** (Low complexity, Medium value)
   - Reduces configuration overhead
   - Supports automatic model detection

5. **Unified Configuration System** (Medium complexity, Medium value)
   - Improves developer experience
   - Reduces boilerplate in application config

6. **Automatic Dimension Detection** (Low complexity, Low value)
   - Nice fallback for unknown models
   - Lower priority since registry covers common cases

7. **Lazy Dependency Validation** (Low complexity, Low value)
   - Defensive programming improvement
   - Can be added incrementally to adapters

8. **Serving Child Spec Pattern** (Medium complexity, Medium value)
   - Only needed if implementing local embedder
   - Bundled with Local adapter implementation

## Technical Dependencies

### For Local Bumblebee Adapter
- `bumblebee` - Model loading and serving
- `exla` - XLA compiler backend for Nx
- `nx` - Numerical computing (Nx.Serving)
- HuggingFace Hub access for model download

### For OpenAI Adapter Completion
- `req` - HTTP client (likely already present)
- Optional: `req_llm` - Higher-level LLM client wrapper
- OpenAI API key configuration

### For Custom Function Embedder
- No additional dependencies
- Pure Elixir implementation

### For Configuration System
- No additional dependencies
- May need Application config access patterns

### Shared Dependencies
- `:telemetry` - Already used in portfolio libs
- `Logger` - Standard library

## Summary

The primary gaps are:
1. **Local embedding** - Arcana has full Bumblebee/Nx.Serving support; Portfolio has none
2. **OpenAI implementation** - Arcana works; Portfolio is a placeholder
3. **Configuration flexibility** - Arcana supports functions/atoms/modules; Portfolio is rigid

Portfolio has advantages in:
1. **Richer return types** - Structured maps with token counts
2. **Supported models callback** - Explicit model enumeration
3. **Gemini support** - Working Gemini adapter that Arcana lacks
