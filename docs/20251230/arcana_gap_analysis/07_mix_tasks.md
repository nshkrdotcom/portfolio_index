# Mix Tasks Gap Analysis

This document analyzes the mix tasks in Arcana and compares them against the portfolio libraries (portfolio_manager and portfolio_coder) to identify gaps in RAG-related functionality.

## Arcana Mix Tasks

### 1. `mix arcana.install`
**File:** `/home/home/p/g/n/portfolio_index/arcana/lib/mix/tasks/arcana.install.ex`

A comprehensive installation task that sets up Arcana in a Phoenix application.

**Features:**
- Generates migrations for `arcana_documents`, `arcana_chunks`, and `arcana_collections` tables
- Creates pgvector extension setup
- Sets up HNSW index for vector similarity search
- Creates evaluation tables (`arcana_evaluation_test_cases`, `arcana_evaluation_runs`)
- Generates Postgrex types module for pgvector support
- Configures repo types automatically
- Adds dashboard route to Phoenix router (optional)
- Supports Igniter for automatic project modification
- Falls back to basic migration generation if Igniter not available

**Options:**
- `--no-dashboard` - Skip adding dashboard route
- `--repo` - Specify custom repo module

### 2. `mix arcana.gen.embedding_migration`
**File:** `/home/home/p/g/n/portfolio_index/arcana/lib/mix/tasks/arcana.gen.embedding_migration.ex`

Generates a migration for updating vector column dimensions when switching embedding models.

**Features:**
- Auto-detects current embedding configuration dimensions
- Generates migration to drop and recreate HNSW index
- Updates vector column size
- Provides clear post-migration instructions

**Options:**
- `--dimensions` - Override auto-detected dimensions

### 3. `mix arcana.reembed`
**File:** `/home/home/p/g/n/portfolio_index/arcana/lib/mix/tasks/arcana.reembed.ex`

Re-embeds all documents with the current embedding configuration.

**Features:**
- Batch processing with configurable size
- Progress bar visualization
- Shows current embedding configuration (model, dimensions)
- Reports rechunked documents and total chunks
- Quiet mode for scripting

**Options:**
- `--batch-size` - Number of chunks per batch (default: 50)
- `--quiet` - Suppress progress output

### 4. `mix arcana.eval.generate`
**File:** `/home/home/p/g/n/portfolio_index/arcana/lib/mix/tasks/arcana.eval.generate.ex`

Generates synthetic test cases for retrieval evaluation.

**Features:**
- Samples chunks from existing data
- Uses LLM to generate evaluation questions
- Filters by source ID or collection
- Stores test cases in database

**Options:**
- `--sample-size` - Number of chunks to sample (default: 50)
- `--source-id` - Limit to specific source
- `--collection` - Limit to specific collection

### 5. `mix arcana.eval.run`
**File:** `/home/home/p/g/n/portfolio_index/arcana/lib/mix/tasks/arcana.eval.run.ex`

Runs retrieval evaluation and reports metrics.

**Features:**
- Multiple search modes: semantic, fulltext, hybrid
- Comprehensive metrics: Recall@1/3/5/10, Precision@1/5, MRR, Hit Rate@5
- Table and JSON output formats
- CI integration with `--fail-under` threshold
- Auto-generate test cases if none exist

**Options:**
- `--mode` - Search mode (semantic, fulltext, hybrid)
- `--source-id` - Limit to specific source
- `--generate` - Generate test cases first
- `--sample-size` - Sample size for generation
- `--format` - Output format (table, json)
- `--fail-under` - CI threshold for Recall@5

---

## Portfolio Libraries Mix Tasks

### PortfolioManager Tasks

#### 1. `mix portfolio.index`
**File:** `/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.index.ex`

Indexes a repository for RAG queries.

**Features:**
- Path-based indexing
- Configurable file extensions
- Named index support

**Options:**
- `--index` - Index name (default: default)
- `--extensions` - File extensions to include (default: .ex,.exs,.md)

#### 2. `mix portfolio.search`
**File:** `/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.search.ex`

Searches portfolio content using RAG retrieval.

**Features:**
- Query-based search
- Configurable result count
- Score display
- Content snippets

**Options:**
- `--index` - Vector index to query
- `--k` - Number of results (default: 10)

#### 3. `mix portfolio.graph`
**File:** `/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.graph.ex`

Graph operations for portfolio analysis.

**Features:**
- Build dependency graphs
- Show graph statistics
- Language-specific analysis

**Options:**
- `--graph` - Graph ID
- `--language` - Dependency language

#### 4. `mix portfolio.ask`
**File:** `/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.ask.ex`

Ask questions using RAG.

**Features:**
- Multiple RAG strategies (hybrid, self_rag, graph_rag)
- Streaming support
- Configurable result count

**Options:**
- `--strategy` - RAG strategy
- `--index` - Vector index
- `--k` - Number of results
- `--stream` - Stream response

### PortfolioCoder Tasks

#### 1. `mix code.index`
**File:** `/home/home/p/g/n/portfolio_coder/lib/mix/tasks/code.index.ex`

Indexes a code repository for semantic search.

**Features:**
- Multi-language support
- Exclude patterns
- Detailed indexing results

**Options:**
- `--index` - Index name
- `--languages` - Languages to index
- `--exclude` - Patterns to exclude

#### 2. `mix code.search`
**File:** `/home/home/p/g/n/portfolio_coder/lib/mix/tasks/code.search.ex`

Searches indexed code repositories.

**Features:**
- Language filtering
- File pattern filtering
- Score-based ranking

**Options:**
- `--index` - Index to search
- `--language` - Filter by language
- `--limit` - Max results
- `--file` - File pattern filter

#### 3. `mix code.ask`
**File:** `/home/home/p/g/n/portfolio_coder/lib/mix/tasks/code.ask.ex`

Ask questions about indexed code.

**Features:**
- RAG-based Q&A
- Streaming support

**Options:**
- `--index` - Index to use
- `--stream` - Stream response

#### 4. `mix code.deps`
**File:** `/home/home/p/g/n/portfolio_coder/lib/mix/tasks/code.deps.ex`

Analyze code dependencies.

**Features:**
- Build dependency graphs
- Show forward dependencies
- Show reverse dependencies
- Find circular dependencies

**Options:**
- `--graph` - Graph name
- `--language` - Project language
- `--depth` - Traversal depth

---

## Identified Gaps

### Gap 1: Installation/Setup Task
- **Arcana Task**: `mix arcana.install` - Comprehensive setup with migrations, pgvector config, dashboard routes, and Igniter integration
- **Missing From**: Both portfolio_manager and portfolio_coder
- **Implementation Complexity**: High
- **Technical Details**:
  - Portfolio libs lack any installation task
  - No migration generation for vector store setup
  - No pgvector types configuration automation
  - No dashboard route injection
  - Would need to create migrations for indexes, document schemas, and chunk tables
  - Consider Igniter integration for automatic project modification

### Gap 2: Embedding Migration Generator
- **Arcana Task**: `mix arcana.gen.embedding_migration` - Auto-detects dimensions, generates migration for dimension changes
- **Missing From**: Both portfolio_manager and portfolio_coder
- **Implementation Complexity**: Medium
- **Technical Details**:
  - Portfolio libs have no mechanism for embedding model dimension changes
  - HNSW index recreation is not automated
  - Manual migrations would be required for each dimension change
  - Requires access to embedder configuration to detect dimensions
  - Depends on: Embedding adapter with `dimensions/1` callback

### Gap 3: Re-embedding Task
- **Arcana Task**: `mix arcana.reembed` - Batch re-embeds all documents with current config
- **Missing From**: Both portfolio_manager and portfolio_coder
- **Implementation Complexity**: Medium
- **Technical Details**:
  - No way to re-embed existing documents after model change
  - Would require batch processing infrastructure
  - Progress tracking needed for large datasets
  - Depends on: Maintenance module with `reembed/2` function
  - Should detect rechunked documents vs. re-embedded only

### Gap 4: Evaluation Test Case Generation
- **Arcana Task**: `mix arcana.eval.generate` - LLM-based synthetic test case generation
- **Missing From**: Both portfolio_manager and portfolio_coder
- **Implementation Complexity**: High
- **Technical Details**:
  - No RAG evaluation infrastructure in portfolio libs
  - Requires LLM integration for question generation
  - Needs evaluation database schema (test_cases, test_case_chunks)
  - Sampling strategy needed for chunk selection
  - Collection/source filtering for targeted evaluation
  - Depends on: LLM adapter, Evaluation module

### Gap 5: Evaluation Runner
- **Arcana Task**: `mix arcana.eval.run` - Comprehensive retrieval metrics
- **Missing From**: Both portfolio_manager and portfolio_coder
- **Implementation Complexity**: High
- **Technical Details**:
  - No retrieval quality metrics in portfolio libs
  - Missing metrics: Recall@k, Precision@k, MRR, Hit Rate
  - No CI integration for quality thresholds
  - Requires evaluation infrastructure from Gap 4
  - Multiple output formats needed (table, JSON)
  - Search mode comparison (semantic vs fulltext vs hybrid)
  - Depends on: Evaluation module, test cases from Gap 4

### Gap 6: Collection/Source Filtering
- **Arcana Task**: Multiple tasks support `--collection` and `--source-id` filtering
- **Missing From**: portfolio_manager (partial), portfolio_coder (missing collection concept)
- **Implementation Complexity**: Low
- **Technical Details**:
  - Arcana has first-class collection support
  - Portfolio libs use index_id but lack collection hierarchy
  - Source ID filtering useful for multi-repo setups

### Gap 7: Dashboard Integration
- **Arcana Task**: `mix arcana.install --dashboard` adds dashboard routes
- **Missing From**: Both portfolio_manager and portfolio_coder
- **Implementation Complexity**: Medium (if dashboard exists)
- **Technical Details**:
  - Portfolio libs have no web dashboard
  - No visualization of indexes, chunks, or search results
  - Would require Phoenix LiveView components
  - Router integration for mounting dashboard

### Gap 8: Quiet/Scripting Mode
- **Arcana Task**: `mix arcana.reembed --quiet` suppresses progress output
- **Missing From**: All portfolio_manager and portfolio_coder tasks
- **Implementation Complexity**: Low
- **Technical Details**:
  - Portfolio tasks always produce output
  - No scripting-friendly quiet mode
  - Impacts automation and CI pipelines

---

## Implementation Priority

### Priority 1 (Critical for RAG Operations)
1. **Re-embedding Task** - Essential for model changes, common operation
2. **Embedding Migration Generator** - Required when switching models
3. **Installation Task** - Streamlines adoption, reduces setup friction

### Priority 2 (Important for Quality Assurance)
4. **Evaluation Test Case Generation** - Enables quality measurement
5. **Evaluation Runner** - Critical for RAG quality validation in CI

### Priority 3 (Nice to Have)
6. **Collection/Source Filtering** - Improves multi-project support
7. **Quiet Mode** - Better CI/scripting support
8. **Dashboard Integration** - Visualization and debugging

---

## Technical Dependencies

### For portfolio_index
To implement these gaps, portfolio_index needs:
1. **Maintenance Module** - For reembed functionality
2. **Evaluation Module** - For test case generation and running
3. **Embedder Adapter with Dimensions** - For auto-detection
4. **Database Schema for Evaluation** - Test cases, runs, metrics

### For portfolio_manager
1. Depends on portfolio_index for underlying RAG functionality
2. Needs to expose maintenance operations via Mix tasks
3. Evaluation should wrap portfolio_index evaluation

### For portfolio_coder
1. Similar dependencies as portfolio_manager
2. Code-specific evaluation metrics may be needed
3. Language-aware test case generation could be valuable

### Cross-Cutting Concerns
1. **Igniter Integration** - Optional but valuable for all install tasks
2. **Progress Callbacks** - Standardize progress reporting across tasks
3. **Output Formatting** - JSON output for all tasks (CI integration)
4. **Threshold Validation** - `--fail-under` pattern for CI gates

---

## Summary Table

| Task | Arcana | portfolio_manager | portfolio_coder | Gap Severity |
|------|--------|-------------------|-----------------|--------------|
| Install/Setup | Yes | No | No | High |
| Index | Via API | Yes | Yes | None |
| Search | Via API | Yes | Yes | None |
| Ask/Query | Via API | Yes | Yes | None |
| Graph/Deps | Via API | Yes | Yes | None |
| Embedding Migration | Yes | No | No | Medium |
| Re-embed | Yes | No | No | High |
| Eval Generate | Yes | No | No | High |
| Eval Run | Yes | No | No | High |
| Dashboard | Yes | No | No | Medium |
| Quiet Mode | Partial | No | No | Low |
