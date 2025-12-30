# Arcana Gap Analysis - Consolidated Summary

## Overview

This document consolidates all findings from the Arcana vs Portfolio libraries gap analysis across 8 analysis areas. It identifies **~72 individual gaps** across agent systems, embedders, vector stores, evaluation, LLM integration, telemetry, mix tasks, and maintenance/documents.

## Analysis Documents

1. **01_agent_system.md** - Agent pipeline, query processing, behaviours (10 gaps)
2. **02_embedder_system.md** - Embedding providers, local models, configuration (10 gaps)
3. **03_vector_store.md** - Memory backend, collections, auto-creation (15 gaps, 4 reverse)
4. **04_evaluation_system.md** - IR metrics, test cases, synthetic generation (12 gaps, 4 reverse)
5. **05_llm_integration.md** - Query rewriting, context handling, prompts (10 gaps)
6. **06_telemetry.md** - Spans, logging, pipeline observability (12 gaps)
7. **07_mix_tasks.md** - Installation, re-embedding, evaluation CLI (8 gaps)
8. **08_maintenance_and_documents.md** - Schemas, status tracking, parser (14 gaps)

---

## Priority 1: High-Impact, Foundation Gaps

These gaps should be implemented first as they provide the foundation for other features.

### P1-1: Pipeline Context Object
- **From**: 01_agent_system.md (Gap 7)
- **Description**: `Context` struct that flows through RAG pipeline tracking all intermediate results
- **Repo**: portfolio_index
- **Complexity**: Medium
- **Enables**: Query processing, observability, debugging

### P1-2: Query Rewriting
- **From**: 01_agent_system.md (Gap 1), 05_llm_integration.md (Gap 1)
- **Description**: LLM-based cleaning of conversational input into search queries
- **Repo**: portfolio_index, portfolio_core (port)
- **Complexity**: Low
- **Enables**: Better search quality

### P1-3: Query Expansion
- **From**: 01_agent_system.md (Gap 2), 05_llm_integration.md (Gap 2)
- **Description**: Adding synonyms, related terms for better retrieval recall
- **Repo**: portfolio_index, portfolio_core (port)
- **Complexity**: Low
- **Enables**: Improved recall

### P1-4: Query Decomposition
- **From**: 01_agent_system.md (Gap 3), 05_llm_integration.md (Gap 3)
- **Description**: Breaking complex questions into simpler sub-questions
- **Repo**: portfolio_index, portfolio_core (port)
- **Complexity**: Medium
- **Enables**: Multi-hop retrieval

### P1-5: Document/Chunk Ecto Schemas
- **From**: 08_maintenance_and_documents.md (Gaps 2, 3, 4)
- **Description**: Ecto schemas for documents, collections, chunks with status tracking
- **Repo**: portfolio_index
- **Complexity**: Medium
- **Enables**: Maintenance, retry logic, status tracking

### P1-6: Production Maintenance Utilities
- **From**: 08_maintenance_and_documents.md (Gap 1), 07_mix_tasks.md (Gaps 1, 2, 3)
- **Description**: Re-embed, embedding migration, installation tasks
- **Repo**: portfolio_index, portfolio_manager
- **Complexity**: Medium
- **Enables**: Production operations

---

## Priority 2: Core RAG Enhancements

### P2-1: Retrieval Quality Metrics (IR Metrics)
- **From**: 04_evaluation_system.md (Gap 3)
- **Description**: Recall@K, Precision@K, MRR, Hit Rate@K for test cases
- **Repo**: portfolio_index, portfolio_core (port)
- **Complexity**: Low-Medium

### P2-2: Test Case Persistence & Generation
- **From**: 04_evaluation_system.md (Gaps 1, 2)
- **Description**: Ecto schemas for test cases, LLM-based synthetic generation
- **Repo**: portfolio_index
- **Complexity**: Medium

### P2-3: Self-Correcting Search
- **From**: 01_agent_system.md (Gap 5)
- **Description**: Search with sufficiency evaluation and query rewriting loop
- **Repo**: portfolio_index
- **Complexity**: Medium

### P2-4: Collection/Index Selection (Routing)
- **From**: 01_agent_system.md (Gap 4), 05_llm_integration.md (Gap 4)
- **Description**: LLM-based routing to relevant collections
- **Repo**: portfolio_index
- **Complexity**: Medium

### P2-5: Local Bumblebee Embeddings
- **From**: 02_embedder_system.md (Gap 1)
- **Description**: Nx.Serving + Bumblebee for local HuggingFace models
- **Repo**: portfolio_index
- **Complexity**: High

### P2-6: OpenAI Embeddings Implementation
- **From**: 02_embedder_system.md (Gap 2)
- **Description**: Complete the placeholder OpenAI adapter
- **Repo**: portfolio_index
- **Complexity**: Low

### P2-7: In-Memory Vector Store
- **From**: 03_vector_store.md (Gap 1)
- **Description**: HNSWLib-based in-memory store for testing
- **Repo**: portfolio_index
- **Complexity**: Medium

---

## Priority 3: Observability & Developer Experience

### P3-1: Built-in Telemetry Logger
- **From**: 06_telemetry.md (Gap 2)
- **Description**: Human-readable telemetry logging with one-line attach
- **Repo**: portfolio_index
- **Complexity**: Low

### P3-2: Span-Based Telemetry
- **From**: 06_telemetry.md (Gap 1)
- **Description**: Use :telemetry.span for all operations
- **Repo**: portfolio_index
- **Complexity**: Medium

### P3-3: LLM Telemetry Enrichment
- **From**: 06_telemetry.md (Gap 3)
- **Description**: Track model, prompt length, response length in events
- **Repo**: portfolio_index
- **Complexity**: Low

### P3-4: Agent Pipeline Telemetry
- **From**: 06_telemetry.md (Gap 4)
- **Description**: Events for each RAG pipeline step
- **Repo**: portfolio_index
- **Complexity**: Medium

### P3-5: Exception Event Consistency
- **From**: 06_telemetry.md (Gap 8)
- **Description**: All operations emit exception events
- **Repo**: portfolio_index
- **Complexity**: Medium

### P3-6: Evaluation CLI Tasks
- **From**: 07_mix_tasks.md (Gaps 4, 5), 04_evaluation_system.md (Gap 5)
- **Description**: mix tasks for eval generate and eval run
- **Repo**: portfolio_manager
- **Complexity**: Low

---

## Priority 4: Extended Features

### P4-1: Reranker Integration in Strategies
- **From**: 01_agent_system.md (Gap 8)
- **Description**: Wire up existing Reranker.LLM into RAG strategies
- **Repo**: portfolio_index
- **Complexity**: Low

### P4-2: Self-Correcting Answers
- **From**: 01_agent_system.md (Gap 6)
- **Description**: Grounding evaluation with correction loop
- **Repo**: portfolio_index
- **Complexity**: Medium

### P4-3: Customizable Prompt Functions
- **From**: 05_llm_integration.md (Gap 9)
- **Description**: :prompt option for all LLM components
- **Repo**: portfolio_index
- **Complexity**: Low

### P4-4: Unified Pipeline Context (Extension)
- **From**: 05_llm_integration.md (Gap 7)
- **Description**: Extend Generation struct with query transformations
- **Repo**: portfolio_manager
- **Complexity**: Medium

### P4-5: File Parser with PDF Support
- **From**: 08_maintenance_and_documents.md (Gap 6)
- **Description**: Parse text/markdown/PDF with format detection
- **Repo**: portfolio_index
- **Complexity**: Low

### P4-6: Backend Override at Runtime
- **From**: 03_vector_store.md (Gap 3)
- **Description**: Per-call backend switching for vector store
- **Repo**: portfolio_index
- **Complexity**: Medium

---

## Grouped Implementation Prompts

Based on the gaps, the following prompt files should be created:

### Prompt 1: Query Processing Pipeline
- Query Rewriter port + adapter
- Query Expander port + adapter
- Query Decomposer port + adapter
- Pipeline Context struct
- **Repos**: portfolio_core, portfolio_index

### Prompt 2: Document Management Schemas
- Document Ecto schema
- Collection Ecto schema
- Chunk Ecto schema with pgvector
- Migrations
- **Repo**: portfolio_index

### Prompt 3: Production Maintenance
- Maintenance module (reembed, diagnostics)
- mix portfolio.install task
- mix portfolio.gen.embedding_migration task
- mix portfolio.reembed task
- **Repos**: portfolio_index, portfolio_manager

### Prompt 4: Evaluation System
- Retrieval metrics port + adapter
- Test case schema and generation
- Evaluation run tracking
- mix portfolio.eval.generate/run tasks
- **Repos**: portfolio_core, portfolio_index, portfolio_manager

### Prompt 5: Embedder Enhancements
- OpenAI adapter implementation
- Local Bumblebee adapter
- Custom function embedder
- Model dimension registry
- **Repo**: portfolio_index

### Prompt 6: Vector Store Enhancements
- In-memory HNSWLib adapter
- Backend override pattern
- Auto index creation
- **Repo**: portfolio_index

### Prompt 7: Telemetry Standardization
- Telemetry.Logger module
- Span-based instrumentation
- LLM telemetry enrichment
- Agent pipeline events
- **Repos**: portfolio_index, portfolio_core

### Prompt 8: Collection Selector & Self-Correction
- Collection selector port + adapter
- Self-correcting search
- Self-correcting answers
- Reranker integration in strategies
- **Repo**: portfolio_index

---

## Gap Count by Area

| Analysis Area | Forward Gaps | Reverse Gaps | Total |
|---------------|-------------|--------------|-------|
| Agent System | 10 | 0 | 10 |
| Embedder System | 8 | 2 | 10 |
| Vector Store | 9 | 6 | 15 |
| Evaluation System | 12 | 4 | 16 |
| LLM Integration | 10 | 0 | 10 |
| Telemetry | 12 | 0 | 12 |
| Mix Tasks | 8 | 0 | 8 |
| Maintenance/Documents | 14 | 0 | 14 |
| **TOTAL** | **83** | **12** | **95** |

*Note: Forward gaps = Arcana features missing from Portfolio. Reverse gaps = Portfolio features missing from Arcana.*

---

## Recommended Implementation Order

1. **Sprint 1**: Query Processing (P1-1 through P1-4)
2. **Sprint 2**: Document Schemas + Maintenance (P1-5, P1-6)
3. **Sprint 3**: Evaluation System (P2-1, P2-2)
4. **Sprint 4**: Embedder Enhancements (P2-5, P2-6)
5. **Sprint 5**: Telemetry + Observability (P3-1 through P3-5)
6. **Sprint 6**: Vector Store + Collection Selection (P2-4, P2-7, P4-6)
7. **Sprint 7**: Self-Correction Features (P2-3, P4-2)
8. **Sprint 8**: Extended Features (P4-1, P4-3, P4-4, P4-5)
