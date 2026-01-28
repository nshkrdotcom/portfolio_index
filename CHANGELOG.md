# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-01-28

### Added

#### OpenAI Responses API & GPT-5 Support
- `PortfolioIndex.Adapters.LLM.OpenAI` - Full OpenAI Responses API integration
  - Automatic API selection: GPT-5 models use Responses API, others use Chat Completions
  - Explicit API override via `api: :responses` or `api: :chat_completions` option
  - `gpt-5-nano` model support (400k context window, 128k max output)
  - Responses API streaming with delta event handling
  - `response_id` tracking for conversation continuity via `previous_response_id`
  - `store: true` option for server-side response persistence
  - `max_output_tokens` / `max_completion_tokens` support for newer models
  - Automatic `max_tokens` → `max_completion_tokens` conversion for models that require it (GPT-5, o-series)
  - System message extraction into `instructions` field for Responses API
  - Response normalization across both API surfaces (content, usage, finish_reason)

#### Agent Session Adapters
- `PortfolioIndex.Adapters.AgentSession.Claude` - Claude agent session adapter
  - Implements `PortfolioCore.Ports.AgentSession` behaviour
  - Delegates to `AgentSessionManager.SessionManager` with Claude provider
  - Rate limiting via `PortfolioIndex.Adapters.RateLimiter`
  - Telemetry spans for start_session, execute, cancel, and end_session
  - Input normalization (map, string, or arbitrary data)
  - Token usage and turn count tracking in telemetry measurements
- `PortfolioIndex.Adapters.AgentSession.Codex` - Codex agent session adapter
  - Same architecture as Claude adapter with Codex provider backend
  - Full session lifecycle management (start, execute, cancel, end)
  - Rate limiting and telemetry instrumentation
- `PortfolioIndex.Adapters.AgentSession.Config` - Shared configuration resolver
  - Application config-based store and adapter resolution
  - Per-provider adapter configuration with defaults
  - Runtime override support via keyword options

#### Git VCS Adapter
- `PortfolioIndex.Adapters.VCS.Git` - Git adapter implementing VCS port
  - Full status parsing via `git status --porcelain=v1 -b`
  - Diff operations with patch and numstat statistics
  - Staging operations (stage, stage_all, unstage)
  - Commit creation with options (allow_empty, amend, no_verify)
  - Log parsing with custom format for commit history
  - Branch operations (create, delete, checkout)
  - Push/pull with remote and branch options
  - Semantic error mapping from Git exit codes
  - Telemetry instrumentation for status, commit, diff, push, and pull operations

#### LLM Adapter Normalization
- All LLM adapters (Anthropic, Codex, Gemini, Ollama) updated with consistent
  `@behaviour PortfolioCore.Ports.LLM` declaration
- Standardized `@impl true` annotations across all LLM adapter callbacks

#### Adapter Registry
- `PortfolioIndex.adapter(:agent_session)` - Agent session adapter resolution
  with configurable default (Claude)

### Changed

- OpenAI adapter refactored to dual-API architecture (Chat Completions + Responses)
- vLLM adapter rewritten for SnakeBridge native integration (replaces HTTP API approach)
  - Uses in-process Python runtime via `VLLM.generate/2`
  - Configurable model loading with `max_model_len`, `gpu_memory_utilization` options
  - Streaming returns single-chunk response (vLLM limitation)
- SnakeBridge compile-time introspection skipped by default via `SNAKEBRIDGE_SKIP` env var
- OpenAI example updated to use `gpt-5-nano` model and Responses API
- vLLM example updated for SnakeBridge setup (CUDA + `mix snakebridge.setup`)
- `Schemas.Queries.similarity_search/3` supports configurable distance operator

### Dependencies

- Updated `claude_agent_sdk` to `~> 0.9.2`
- Updated `codex_sdk` to `~> 0.6.0`
- Updated `gemini_ex` to `~> 0.9.1`
- Updated `openai_ex` to `~> 0.9.18`
- Updated `vllm` to `~> 0.2.1`
- Added `agent_session_manager` `~> 0.1.1`

### Tests

- Added `ClaudeAgentSessionTest` (291 lines) covering session lifecycle, telemetry, and error handling
- Added `CodexAgentSessionTest` (280 lines) with full session management coverage
- Added `AgentSessionConfigTest` (90 lines) for configuration resolution
- Added `GitAdapterTest` (419 lines) covering status, diff, staging, commit, branch, and push/pull
- Expanded `OpenAILLMTest` with Responses API completion and streaming tests
- Refactored `VLLMTest` for SnakeBridge-based implementation
- Added `LlmSdkBehaviours` test support module for mock definitions
- Added `VLLMSdkMock` to test configuration

## [0.4.0] - 2026-01-08

### Added

#### Local LLM Support
- `PortfolioIndex.Adapters.LLM.Ollama` - Ollama LLM adapter using ollixir client
  - Local model orchestration with configurable base URL
  - OpenAI-style message formatting
  - Streaming support with delta normalization
  - Rate limiting and telemetry instrumentation
  - Configurable model info and supported models list
- `PortfolioIndex.Adapters.LLM.VLLM` - vLLM adapter using the `vllm` SnakeBridge library
  - Local GPU inference via Python runtime
  - Configurable model, sampling, and run options
  - Rate limiting and telemetry instrumentation

#### Local Embeddings Support
- `PortfolioIndex.Adapters.Embedder.Ollama` - Ollama embeddings adapter using ollixir
  - Support for nomic-embed-text, mxbai-embed-large models
  - Batch embedding support via native API
  - Token count extraction from response or estimation fallback
  - Rate limiting and telemetry instrumentation

#### Telemetry Enhancements
- `PortfolioIndex.Telemetry.Context` - Lineage context helpers for telemetry metadata
  - Standard context keys: `trace_id`, `work_id`, `plan_id`, `step_id`
  - `merge/2` for combining context with telemetry metadata
  - Integrated into all LLM adapters (Anthropic, Codex, Gemini, OpenAI, Ollama, vLLM)

#### Backend Integration
- `PortfolioIndex.LLM.BackendBridge` - Bridge for CrucibleIR backend prompts
  - `prompt_to_messages/1` - Convert backend prompt structs to messages and opts
  - `completion_from_result/3` - Build completion maps from adapter results
  - Usage normalization across provider formats

#### Examples
- `examples/ollama_embedder.exs` - Ollama embedder demonstration
- `examples/ollama_llm.exs` - Ollama LLM with streaming demonstration
- `examples/ollama_setup.exs` - Automated Ollama model installation script
- `examples/vllm_llm.exs` - vLLM adapter demonstration
- `examples/support/ollama_helpers.exs` - Shared helpers for Ollama examples

### Changed

- LLM adapters now pass opts to telemetry for lineage context propagation
- Gemini embedder and LLM adapters support SDK injection via `:sdk` option
- RateLimiter uses rescue instead of try for ETS table creation
- Updated run_all.sh to include Ollama examples (vLLM skipped by default)

### Dependencies

- Changed portfolio_core from path to hex: `~> 0.4.0`
- Changed foundation from path to hex: `~> 0.2.0`
- Changed gemini_ex from path to hex: `~> 0.8.8`
- Changed claude_agent_sdk from path to hex: `~> 0.7.6`
- Changed codex_sdk from path to hex: `~> 0.5.0`
- Added ollixir `~> 0.1.0` for Ollama integration
- Added vllm `~> 0.1.0` for local GPU inference via SnakeBridge

## [0.3.1] - 2025-12-30

### Added

#### Collection Selection & Self-Correction
- `PortfolioIndex.Adapters.CollectionSelector.LLM` - LLM-based collection routing
  - Routes queries to relevant collections based on descriptions
  - Returns JSON with selected collections and reasoning
  - Custom prompt support via `:prompt` option
- `PortfolioIndex.Adapters.CollectionSelector.RuleBased` - Rule-based collection routing
  - Keyword matching with configurable boost factors
  - Deterministic routing without LLM calls
  - Useful for testing and predictable behavior
- `PortfolioIndex.RAG.SelfCorrectingSearch` - Search with sufficiency evaluation and query rewriting
  - Evaluates if results are sufficient for answering the question
  - Rewrites query and retries if insufficient
  - Configurable max iterations and custom prompts
  - Tracks correction history in context
- `PortfolioIndex.RAG.SelfCorrectingAnswer` - Answer generation with grounding evaluation
  - Evaluates if answer is grounded in provided context
  - Identifies ungrounded claims and generates corrections
  - Configurable max corrections and grounding threshold
  - Tracks correction history for debugging
- `PortfolioIndex.RAG.Reranker` - Pipeline-integrated reranking utilities
  - `rerank/2` - Rerank context results with threshold filtering
  - `rerank_chunks/3` - Direct chunk reranking
  - `deduplicate/2` - Remove duplicate chunks by id or content
  - Score tracking in context

#### Enhanced Agentic Strategy
- `PortfolioIndex.RAG.Strategies.Agentic.execute_pipeline/2` - Full pipeline execution with all enhancements
  - Query rewriting, expansion, decomposition
  - Collection selection and routing
  - Self-correcting search with sufficiency evaluation
  - Reranking with threshold filtering
  - Self-correcting answer with grounding evaluation
- `PortfolioIndex.RAG.Strategies.Agentic.with_context/2` - Pipeline execution with Context struct
  - Enables functional composition with pipe operator
  - Configurable step skipping via `:skip` option
  - Returns full Context with all intermediate results

#### Telemetry Standardization
- `PortfolioIndex.Telemetry.Logger` - Human-readable telemetry logger with one-line attach
  - Text and JSON output formats
  - Component-level filtering (embedder, llm, rag, vector_store, evaluation)
  - Duration formatting (ms, s)
  - Context-aware metadata display
- `PortfolioIndex.Telemetry.LLM` - LLM-specific telemetry with token tracking
  - `span/2` for wrapping LLM calls with detailed metadata
  - `estimate_tokens/1` for token count estimation
  - `extract_usage/1` for parsing provider-specific usage data
- `PortfolioIndex.Telemetry.Embedder` - Embedder telemetry utilities
  - `span/2` for single embedding operations
  - `batch_span/2` for batch embedding operations
- `PortfolioIndex.Telemetry.RAG` - RAG pipeline step telemetry
  - `step_span/3` for wrapping pipeline steps (rewrite, expand, decompose, etc.)
  - `search_span/3` for search-specific telemetry
  - `rerank_span/3` for rerank-specific telemetry
  - `correction_event/2` for self-correction tracking
- `PortfolioIndex.Telemetry.VectorStore` - Vector store operation telemetry
  - `search_span/2` for search operations
  - `insert_span/2` for single insert operations
  - `batch_insert_span/2` for batch insert operations

#### Vector Store Enhancements
- `PortfolioIndex.Adapters.VectorStore.Memory` - In-memory HNSWLib vector store
  - GenServer-based in-memory storage for testing and development
  - Uses HNSWLib for approximate nearest neighbor (ANN) search
  - Soft deletion support (marks as deleted without index rebuild)
  - Optional file-based persistence via save/load
  - Thread-safe for concurrent reads and writes
  - Configurable dimensions, max_elements, ef_construction, and m parameters
- `PortfolioIndex.VectorStore.Backend` - Backend resolution with per-call override
  - Runtime backend switching via `:backend` option
  - Backend aliases: `:pgvector`, `:memory`, `:qdrant`
  - Module and tuple configuration support: `{Memory, store: pid}`
  - Unified API for search, insert, insert_batch, delete, get
- `PortfolioIndex.VectorStore.IndexManager` - Index auto-creation and management
  - `ensure_index/2` - Create index if not exists
  - `index_exists?/2` - Check index existence
  - `index_stats/2` - Get index statistics
  - `rebuild_index/2` - Rebuild index after bulk inserts
  - `drop_index/2` - Remove index
  - Backend-specific options for pgvector (HNSW, IVFFlat) and memory stores
- `PortfolioIndex.VectorStore.Collections` - Collection-based organization
  - Logical grouping of vectors via metadata filtering
  - `search_collection/3` - Search within specific collection
  - `insert_to_collection/5` - Insert with collection tag
  - `list_collections/1` - List all collections
  - `collection_stats/2` - Get collection statistics
  - `clear_collection/2` - Delete all vectors in collection
- `PortfolioIndex.VectorStore.SoftDelete` - Soft deletion support
  - `soft_delete/2` - Mark item as deleted without removal
  - `soft_delete_where/2` - Soft delete matching items
  - `restore/2` - Restore soft-deleted item
  - `purge_deleted/2` - Permanently delete old soft-deleted items
  - `count_deleted/1` - Count soft-deleted items
- `PortfolioIndex.VectorStore.Search` - Enhanced search with hybrid support
  - `similarity_search/2` - Vector search with threshold and collection filtering
  - `hybrid_search/3` - Combine vector and keyword search with RRF
  - `filter_results/2` - Post-filter by metadata
  - `normalize_scores/2` - Normalize across distance metrics
  - `deduplicate/2` - Remove duplicate results by id or content_hash

#### Embedder Enhancements
- `PortfolioIndex.Adapters.Embedder.OpenAI` - OpenAI text-embedding API adapter
  - Full implementation replacing placeholder with actual API calls
  - Support for text-embedding-3-small, text-embedding-3-large, text-embedding-ada-002
  - Batch embedding support via native API
  - Telemetry instrumentation for monitoring
- `PortfolioIndex.Adapters.Embedder.Bumblebee` - Local Bumblebee/Nx.Serving embeddings
  - HuggingFace model loading with EXLA compilation
  - Support for BGE, MiniLM, and other sentence-transformers
  - Supervision tree integration via `child_spec/1`
  - No API calls required - fully local inference
- `PortfolioIndex.Adapters.Embedder.Function` - Custom function wrapper adapter
  - Wrap any function as an embedder
  - Optional batch function support
  - Useful for testing and custom integrations
- `PortfolioIndex.Embedder.Registry` - Model dimension registry
  - Pre-configured dimensions for OpenAI, Voyage, Bumblebee, Ollama models
  - Runtime registration for custom models
  - Provider lookup by model name
- `PortfolioIndex.Embedder.Config` - Unified embedder configuration
  - Shorthand syntax (:openai, :bumblebee, etc.)
  - Module and tuple configuration support
  - Function wrapper auto-resolution
  - `current/0` and `current_dimensions/0` helpers
- `PortfolioIndex.Embedder.DimensionDetector` - Automatic dimension detection
  - Multiple detection strategies (explicit, registry, probe)
  - Dimension validation for embeddings
  - Fallback probing for unknown models

#### Retrieval Evaluation System
- `PortfolioIndex.Adapters.RetrievalMetrics.Standard` - Standard IR metrics adapter
  - Implements `PortfolioCore.Ports.RetrievalMetrics` behaviour
  - `recall_at_k/3` - Recall at K (fraction of relevant items retrieved)
  - `precision_at_k/3` - Precision at K (fraction of retrieved items relevant)
  - `mrr/2` - Mean Reciprocal Rank (inverse of first relevant rank)
  - `hit_rate_at_k/3` - Hit Rate at K (1 if any relevant item in top K)
  - Aggregation with mean calculation across test cases
- `PortfolioIndex.Schemas.TestCase` - Ecto schema for evaluation test cases
  - Links questions to ground truth chunks via many-to-many
  - Source: `:synthetic` (LLM-generated) or `:manual`
  - Collection and metadata support
- `PortfolioIndex.Schemas.EvaluationRun` - Ecto schema for evaluation runs
  - Status tracking: `:running`, `:completed`, `:failed`
  - Aggregate metrics and per-case results storage
  - Timing and configuration tracking
- `PortfolioIndex.Evaluation.Generator` - LLM-powered test case generation
  - `generate/2` - Sample chunks and generate synthetic questions
  - `generate_question/2` - Generate single question from chunk content
  - Chunk sampling with collection/source filtering
- `PortfolioIndex.Evaluation` - Main evaluation orchestrator
  - `run/2` - Execute evaluation against test cases
  - `list_test_cases/2` - List with filtering options
  - `create_test_case/2` - Create manual test cases
  - `add_ground_truth/3` - Link chunks as ground truth
  - `list_runs/2` - Get historical evaluation runs
  - `compare_runs/2` - Compare metrics between runs
- Database migration for evaluation tables
  - `portfolio_evaluation_test_cases` with source and collection indexes
  - `portfolio_evaluation_test_case_chunks` join table
  - `portfolio_evaluation_runs` with status index

#### Production Maintenance Utilities
- `PortfolioIndex.Maintenance` - Production maintenance utilities (reembed, diagnostics, retry)
  - `reembed/2` - Re-embed all chunks or filtered subset with progress tracking
  - `diagnostics/1` - Get system diagnostics including counts and storage usage
  - `retry_failed/2` - Reset failed documents to pending for reprocessing
  - `cleanup_deleted/2` - Permanently remove soft-deleted documents and chunks
  - `verify_embeddings/1` - Verify embedding consistency across chunks
- `PortfolioIndex.Maintenance.Progress` - Progress reporting for maintenance operations
  - `cli_reporter/1` - Prints progress to stdout with percentage
  - `silent_reporter/0` - No-op reporter for silent operations
  - `telemetry_reporter/1` - Emits telemetry events for monitoring
  - `build_event/4` - Create progress events from components

#### Mix Tasks
- `mix portfolio.install` - Installation task for new projects
  - Generates database migrations for collections, documents, and chunks tables
  - Creates pgvector extension setup with HNSW index
  - Prints configuration instructions and next steps
  - Options: `--repo`, `--dimension`, `--no-migrations`
- `mix portfolio.gen.embedding_migration` - Generate migration for dimension changes
  - Creates migration to alter vector column dimensions
  - Drops and recreates HNSW index for new dimensions
  - Options: `--dimension` (required), `--table`, `--column`

#### Document Management Schemas
- `PortfolioIndex.Schemas.Collection` - Ecto schema for document collections
  - Groups related documents for organized retrieval and routing
  - Unique name constraint with metadata support
  - Virtual `document_count` field for aggregation
- `PortfolioIndex.Schemas.Document` - Ecto schema for ingested documents with status tracking
  - Status enum: `:pending`, `:processing`, `:completed`, `:failed`, `:deleted`
  - Content hash for deduplication via `compute_hash/1`
  - Collection relationship for document organization
  - Error message tracking for failed ingestions
- `PortfolioIndex.Schemas.Chunk` - Ecto schema for document chunks with pgvector embeddings
  - Native `Pgvector.Ecto.Vector` type for similarity search
  - Document relationship with cascade delete
  - Character offset tracking (`start_char`, `end_char`)
  - Token count for LLM context budgeting
- `PortfolioIndex.Schemas.Queries` - Query helpers for schema operations
  - `get_collection_by_name/2` - Fetch collection by name
  - `get_or_create_collection/3` - Upsert collection
  - `list_documents_by_status/3` - Filter documents by processing status
  - `get_document_with_chunks/2` - Load document with preloaded chunks
  - `similarity_search/3` - pgvector cosine similarity search
  - `count_chunks_without_embedding/1` - Count unprocessed chunks
  - `get_failed_documents/2` - Fetch documents for retry
  - `soft_delete_document/2` - Mark document as deleted
- Database migration for document management tables
  - `portfolio_collections` with unique name index
  - `portfolio_documents` with status, source_id, and content_hash indexes
  - `portfolio_chunks` with HNSW vector index for fast similarity search

#### Query Processing Pipeline
- `PortfolioIndex.RAG.Pipeline.Context` struct for pipeline state tracking
  - Flows through RAG pipeline accumulating intermediate results
  - Tracks query transformations, routing, retrieval, and generation
  - Supports functional composition with pipe operator
  - Error propagation and halt semantics
- `PortfolioIndex.Adapters.QueryRewriter.LLM` - LLM-based query cleaning
  - Removes greetings, filler phrases, conversational noise
  - Preserves technical terms and entity names
  - Custom prompt support
- `PortfolioIndex.Adapters.QueryExpander.LLM` - LLM-based query expansion
  - Adds synonyms and related terms for better recall
  - Expands abbreviations (ML -> machine learning)
  - Tracks added terms for debugging
- `PortfolioIndex.Adapters.QueryDecomposer.LLM` - LLM-based query decomposition
  - Breaks complex questions into 2-4 simpler sub-questions
  - Enables parallel retrieval for multi-faceted queries
  - JSON response parsing with fallback handling
- `PortfolioIndex.RAG.QueryProcessor` - unified query processing module
  - `rewrite/2` - Apply query rewriting to pipeline context
  - `expand/2` - Apply query expansion to pipeline context
  - `decompose/2` - Apply query decomposition to pipeline context
  - `process/2` - Run all processing steps with skip options
  - `effective_query/1` - Get best query for retrieval

#### Chunker Enhancements
- **Separators module** - Centralized language-specific separators for 17+ formats
  - Language support: Elixir, Ruby, PHP, Python, JavaScript, TypeScript, Vue, HTML
  - Document formats: doc, docx, epub, latex, odt, pdf, rtf
  - Markdown with header-aware splitting
- **Config module** - NimbleOptions-based configuration validation with compile-time schema
- **Pluggable `get_chunk_size` function** - Token-based chunking support across all strategies
  - Character, byte, word, or custom tokenizer-based sizing
  - Defaults to `String.length/1` for backwards compatibility

#### Token Utilities
- **Tokens module** - Centralized token estimation utilities
  - `Tokens.estimate/2` - Estimate token count from text (~4 chars/token heuristic)
  - `Tokens.sizer/1` - Get sizing function for token-based chunking
  - `Tokens.to_chars/2` - Convert token count to character count
  - `Tokens.from_chars/2` - Convert character count to token count
  - `Tokens.default_ratio/0` - Returns the default chars-per-token ratio (4)

#### Chunker Config Enhancement
- **`size_unit` option** - Specify `:characters` or `:tokens` for chunk sizing
  - `:tokens` auto-configures `get_chunk_size` with token estimation
  - `:characters` (default) uses `String.length/1`
  - Implements `PortfolioCore.Ports.Chunker` port specification for `size_unit`

#### Chunker Output Enhancement
- **`token_count` in metadata** - All chunkers now include estimated token count
  - Useful for LLM context window budgeting
  - Approximately `char_count / 4`
  - Included in: Recursive, Character, Paragraph, Sentence, Semantic chunkers

### Changed

- All chunker adapters now support `:get_chunk_size` option for custom size measurement
- Recursive chunker uses new Separators module for format-specific splitting
- Added nimble_options dependency for robust configuration validation

### Documentation

- Added technical documentation in `docs/20251230/chunker-enhancements/`
  - `overview.md` - Feature overview and migration guide
  - `separators.md` - Language separator reference
  - `tokenization.md` - Token-based chunking guide

## [0.3.0] - 2025-12-28

### Added

#### Chunker Adapters
- Character chunker with boundary modes (`:word`, `:sentence`, `:none`)
- Paragraph chunker with intelligent merging and splitting
- Sentence chunker with NLP tokenization and abbreviation handling
- Semantic chunker using embedding-based similarity grouping

#### GraphRAG Components
- `CommunityDetector` with label propagation algorithm
- `CommunitySummarizer` with LLM-based summarization and embedding generation
- `EntityExtractor` with batch support and entity resolution

#### Graph Store Enhancements (Neo4j)
- `EntitySearch` module for vector-based entity search
- `Community` module for community CRUD and vector search
- `Traversal` module for BFS, subgraph extraction, and path finding

#### Reranker Adapters
- LLM-based reranker with customizable prompts
- Passthrough reranker for testing and baselines

#### Retriever Enhancements
- GraphRAG local/global/hybrid search modes
- PostgreSQL tsvector-based full-text search

### Changed

- GraphRAG strategy now supports `:mode` option (`:local`, `:global`, `:hybrid`)
- Updated portfolio_core dependency to path reference for development

## [0.2.0] - 2025-12-27

### Added

- Anthropic LLM adapter via claude_agent_sdk with streaming
- OpenAI LLM adapter via codex_sdk with streaming
- GraphRAG strategy combining vector search with graph traversal
- Agentic strategy for tool-based iterative retrieval
- Telemetry events for new adapters and strategies

### Dependencies

- Added claude_agent_sdk ~> 0.6.10
- Added codex_sdk ~> 0.4.3
- Updated portfolio_core to 0.2.0

## [0.1.1] - 2025-12-27

### Added

- OpenAI embedder adapter placeholder (`PortfolioIndex.Adapters.Embedder.OpenAI`)
- Anthropic LLM adapter placeholder (`PortfolioIndex.Adapters.LLM.Anthropic`)
- `AdapterResolver` for dynamic adapter resolution from context or registry
- Agentic RAG strategy placeholder (`PortfolioIndex.RAG.Strategies.Agentic`)
- GraphRAG strategy placeholder (`PortfolioIndex.RAG.Strategies.GraphRAG`)
- `enqueue/2` function to Ingestion pipeline for ad-hoc file indexing

### Changed

- Pgvector adapter: idempotent index creation with dimension validation
- Pgvector adapter: normalize metric and index type from string or atom inputs
- Application startup: conditional child process loading via config flags
- Hybrid and SelfRAG strategies now use AdapterResolver for dynamic adapter selection
- Updated `portfolio_core` dependency to `~> 0.1.1`

## [0.1.0] - 2025-12-27

### Added

- Initial release of PortfolioIndex

[Unreleased]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/nshkrdotcom/portfolio_index/releases/tag/v0.1.0
