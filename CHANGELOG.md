# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2025-12-30

### Added

#### Chunker Enhancements
- **Separators module** - Centralized language-specific separators for 17+ formats
  - Language support: Elixir, Ruby, PHP, Python, JavaScript, TypeScript, Vue, HTML
  - Document formats: doc, docx, epub, latex, odt, pdf, rtf
  - Markdown with header-aware splitting
- **Config module** - NimbleOptions-based configuration validation with compile-time schema
- **Pluggable `get_chunk_size` function** - Token-based chunking support across all strategies
  - Character, byte, word, or custom tokenizer-based sizing
  - Defaults to `String.length/1` for backwards compatibility

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

[Unreleased]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/nshkrdotcom/portfolio_index/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/nshkrdotcom/portfolio_index/releases/tag/v0.1.0
