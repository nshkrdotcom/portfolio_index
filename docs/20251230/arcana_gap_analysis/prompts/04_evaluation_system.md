# Prompt 4: Evaluation System Implementation

## Target Repositories
- **portfolio_core**: `/home/home/p/g/n/portfolio_core`
- **portfolio_index**: `/home/home/p/g/n/portfolio_index`
- **portfolio_manager**: `/home/home/p/g/n/portfolio_manager`

## Required Reading Before Implementation

### Reference Implementation (Arcana)
Read these files to understand the reference implementation:
```
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/evaluation.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/evaluation/test_case.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/evaluation/generator.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/evaluation/metrics.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/evaluation/answer_metrics.ex
/home/home/p/g/n/portfolio_index/arcana/lib/arcana/evaluation/run.ex
/home/home/p/g/n/portfolio_index/arcana/lib/mix/tasks/arcana.eval.generate.ex
/home/home/p/g/n/portfolio_index/arcana/lib/mix/tasks/arcana.eval.run.ex
```

### Existing Portfolio Code
Read these files to understand existing patterns:
```
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/evaluation.ex
/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/evaluation.ex
/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/llm/anthropic.ex
```

### Gap Analysis Documentation
```
/home/home/p/g/n/portfolio_index/docs/20251230/arcana_gap_analysis/04_evaluation_system.md
```

---

## Implementation Tasks

### Task 1: Retrieval Metrics Port (portfolio_core)

Create `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/retrieval_metrics.ex`:

```elixir
defmodule PortfolioCore.Ports.RetrievalMetrics do
  @moduledoc """
  Behaviour for computing information retrieval quality metrics.
  Measures how well a search system retrieves relevant documents.
  """

  @type metric_result :: %{
    recall_at_k: %{1 => float(), 3 => float(), 5 => float(), 10 => float()},
    precision_at_k: %{1 => float(), 3 => float(), 5 => float(), 10 => float()},
    mrr: float(),
    hit_rate_at_k: %{1 => float(), 3 => float(), 5 => float(), 10 => float()}
  }

  @type test_case_result :: %{
    test_case_id: String.t(),
    question: String.t(),
    expected_ids: [String.t()],
    retrieved_ids: [String.t()],
    metrics: metric_result()
  }

  @doc """
  Compute retrieval metrics for a single test case.

  ## Parameters
  - `expected_ids` - List of relevant document/chunk IDs (ground truth)
  - `retrieved_ids` - List of retrieved document/chunk IDs (in rank order)
  - `opts` - Options including `:k_values` (default [1, 3, 5, 10])
  """
  @callback compute(expected_ids :: [String.t()], retrieved_ids :: [String.t()], opts :: keyword()) ::
    {:ok, metric_result()} | {:error, term()}

  @doc """
  Aggregate metrics across multiple test cases.
  """
  @callback aggregate(results :: [test_case_result()]) :: {:ok, metric_result()} | {:error, term()}
end
```

**Test file**: `/home/home/p/g/n/portfolio_core/test/ports/retrieval_metrics_test.exs`

---

### Task 2: Retrieval Metrics Adapter (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/adapters/retrieval_metrics/standard.ex`:

```elixir
defmodule PortfolioIndex.Adapters.RetrievalMetrics.Standard do
  @moduledoc """
  Standard information retrieval metrics implementation.
  Computes Recall@K, Precision@K, MRR, and Hit Rate@K.
  """

  @behaviour PortfolioCore.Ports.RetrievalMetrics

  @default_k_values [1, 3, 5, 10]

  @impl true
  def compute(expected_ids, retrieved_ids, opts \\ [])

  @impl true
  def aggregate(results)

  @doc "Compute Recall@K - fraction of relevant docs in top K"
  @spec recall_at_k([String.t()], [String.t()], pos_integer()) :: float()
  def recall_at_k(expected_ids, retrieved_ids, k)

  @doc "Compute Precision@K - fraction of top K that are relevant"
  @spec precision_at_k([String.t()], [String.t()], pos_integer()) :: float()
  def precision_at_k(expected_ids, retrieved_ids, k)

  @doc "Compute MRR - 1/position of first relevant result"
  @spec mrr([String.t()], [String.t()]) :: float()
  def mrr(expected_ids, retrieved_ids)

  @doc "Compute Hit Rate@K - 1 if any relevant in top K, else 0"
  @spec hit_rate_at_k([String.t()], [String.t()], pos_integer()) :: float()
  def hit_rate_at_k(expected_ids, retrieved_ids, k)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/adapters/retrieval_metrics/standard_test.exs`

---

### Task 3: Test Case Schema (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/schemas/test_case.ex`:

```elixir
defmodule PortfolioIndex.Schemas.TestCase do
  @moduledoc """
  Ecto schema for evaluation test cases.
  Links questions to their expected relevant chunks (ground truth).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type source :: :synthetic | :manual

  @type t :: %__MODULE__{
    id: Ecto.UUID.t() | nil,
    question: String.t(),
    source: source(),
    collection: String.t() | nil,
    metadata: map(),
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_evaluation_test_cases" do
    field :question, :string
    field :source, Ecto.Enum, values: [:synthetic, :manual], default: :manual
    field :collection, :string
    field :metadata, :map, default: %{}

    many_to_many :relevant_chunks, PortfolioIndex.Schemas.Chunk,
      join_through: "portfolio_evaluation_test_case_chunks",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating test cases"
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(test_case, attrs)

  @doc "Add relevant chunks to a test case"
  @spec add_relevant_chunks(t(), [PortfolioIndex.Schemas.Chunk.t()]) :: Ecto.Changeset.t()
  def add_relevant_chunks(test_case, chunks)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/schemas/test_case_test.exs`

---

### Task 4: Evaluation Run Schema (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/schemas/evaluation_run.ex`:

```elixir
defmodule PortfolioIndex.Schemas.EvaluationRun do
  @moduledoc """
  Ecto schema for tracking evaluation runs.
  Stores configuration, status, and results for historical comparison.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :running | :completed | :failed

  @type t :: %__MODULE__{
    id: Ecto.UUID.t() | nil,
    status: status(),
    config: map(),
    aggregate_metrics: map(),
    per_case_results: [map()],
    error_message: String.t() | nil,
    started_at: DateTime.t() | nil,
    completed_at: DateTime.t() | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "portfolio_evaluation_runs" do
    field :status, Ecto.Enum, values: [:running, :completed, :failed], default: :running
    field :config, :map, default: %{}
    field :aggregate_metrics, :map, default: %{}
    field :per_case_results, {:array, :map}, default: []
    field :error_message, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating evaluation runs"
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs)

  @doc "Mark run as completed with results"
  @spec complete(t(), map(), [map()]) :: Ecto.Changeset.t()
  def complete(run, aggregate_metrics, per_case_results)

  @doc "Mark run as failed with error"
  @spec fail(t(), String.t()) :: Ecto.Changeset.t()
  def fail(run, error_message)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/schemas/evaluation_run_test.exs`

---

### Task 5: Test Case Generator (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/evaluation/generator.ex`:

```elixir
defmodule PortfolioIndex.Evaluation.Generator do
  @moduledoc """
  LLM-powered synthetic test case generation.
  Creates questions from document chunks for evaluation.
  """

  alias PortfolioIndex.Schemas.{TestCase, Chunk}

  @default_prompt """
  Based on the following text chunk, generate a specific question that could be answered using this content.
  The question should be clear, searchable, and directly related to the information in the chunk.
  Return ONLY the question, nothing else.

  Text chunk:
  {chunk_text}
  """

  @type generate_opts :: [
    sample_size: pos_integer(),
    collection: String.t() | nil,
    prompt: String.t() | (String.t() -> String.t()),
    llm: (String.t() -> {:ok, String.t()} | {:error, term()})
  ]

  @doc """
  Generate synthetic test cases from chunks.

  Options:
  - `:sample_size` - Number of chunks to sample (default: 10)
  - `:collection` - Filter chunks by collection
  - `:prompt` - Custom prompt template with {chunk_text} placeholder
  - `:llm` - LLM function for question generation
  """
  @spec generate(Ecto.Repo.t(), generate_opts()) :: {:ok, [TestCase.t()]} | {:error, term()}
  def generate(repo, opts \\ [])

  @doc "Generate a question for a single chunk"
  @spec generate_question(Chunk.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_question(chunk, opts)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/evaluation/generator_test.exs`

---

### Task 6: Evaluation Orchestrator (portfolio_index)

Create `/home/home/p/g/n/portfolio_index/lib/portfolio_index/evaluation.ex`:

```elixir
defmodule PortfolioIndex.Evaluation do
  @moduledoc """
  Main entry point for retrieval evaluation.
  Orchestrates test case execution and metrics computation.
  """

  alias PortfolioIndex.Schemas.{TestCase, EvaluationRun}
  alias PortfolioIndex.Adapters.RetrievalMetrics.Standard

  @type run_opts :: [
    mode: :semantic | :fulltext | :hybrid,
    collection: String.t() | nil,
    limit: pos_integer() | nil,
    search_fn: (String.t(), keyword() -> [map()]),
    evaluate_answer: boolean()
  ]

  @doc """
  Run evaluation against all or filtered test cases.

  Options:
  - `:mode` - Search mode (default: :semantic)
  - `:collection` - Filter test cases by collection
  - `:limit` - Max test cases to evaluate
  - `:search_fn` - Custom search function
  - `:evaluate_answer` - Also evaluate answer quality (default: false)
  """
  @spec run(Ecto.Repo.t(), run_opts()) :: {:ok, EvaluationRun.t()} | {:error, term()}
  def run(repo, opts \\ [])

  @doc "List all test cases"
  @spec list_test_cases(Ecto.Repo.t(), keyword()) :: [TestCase.t()]
  def list_test_cases(repo, opts \\ [])

  @doc "Create a manual test case"
  @spec create_test_case(Ecto.Repo.t(), map()) :: {:ok, TestCase.t()} | {:error, term()}
  def create_test_case(repo, attrs)

  @doc "Add relevant chunks to a test case"
  @spec add_ground_truth(Ecto.Repo.t(), TestCase.t(), [String.t()]) :: {:ok, TestCase.t()} | {:error, term()}
  def add_ground_truth(repo, test_case, chunk_ids)

  @doc "Get historical evaluation runs"
  @spec list_runs(Ecto.Repo.t(), keyword()) :: [EvaluationRun.t()]
  def list_runs(repo, opts \\ [])

  @doc "Compare two evaluation runs"
  @spec compare_runs(EvaluationRun.t(), EvaluationRun.t()) :: map()
  def compare_runs(run1, run2)
end
```

**Test file**: `/home/home/p/g/n/portfolio_index/test/evaluation_test.exs`

---

### Task 7: Evaluation Migration (portfolio_index)

Create migration `/home/home/p/g/n/portfolio_index/priv/repo/migrations/YYYYMMDDHHMMSS_create_portfolio_evaluation_tables.exs`:

```elixir
defmodule PortfolioIndex.Repo.Migrations.CreatePortfolioEvaluationTables do
  use Ecto.Migration

  def change do
    # Test cases table
    create table(:portfolio_evaluation_test_cases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :question, :text, null: false
      add :source, :string, default: "manual"
      add :collection, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:portfolio_evaluation_test_cases, [:collection])
    create index(:portfolio_evaluation_test_cases, [:source])

    # Join table for test case chunks
    create table(:portfolio_evaluation_test_case_chunks, primary_key: false) do
      add :test_case_id, references(:portfolio_evaluation_test_cases, type: :binary_id, on_delete: :delete_all), null: false
      add :chunk_id, references(:portfolio_chunks, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:portfolio_evaluation_test_case_chunks, [:test_case_id, :chunk_id])

    # Evaluation runs table
    create table(:portfolio_evaluation_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, default: "running"
      add :config, :map, default: %{}
      add :aggregate_metrics, :map, default: %{}
      add :per_case_results, {:array, :map}, default: []
      add :error_message, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:portfolio_evaluation_runs, [:status])
  end
end
```

---

### Task 8: Eval Generate Mix Task (portfolio_manager)

Create `/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.eval.generate.ex`:

```elixir
defmodule Mix.Tasks.Portfolio.Eval.Generate do
  @moduledoc """
  Generate synthetic test cases from document chunks.

  ## Usage

      mix portfolio.eval.generate

  ## Options

  - `--sample-size` - Number of chunks to sample (default: 10)
  - `--collection` - Only sample from this collection
  - `--source-id` - Only sample from documents with this source ID
  """

  use Mix.Task

  @shortdoc "Generate synthetic evaluation test cases"

  @impl Mix.Task
  def run(args)
end
```

**Test file**: `/home/home/p/g/n/portfolio_manager/test/mix/tasks/portfolio.eval.generate_test.exs`

---

### Task 9: Eval Run Mix Task (portfolio_manager)

Create `/home/home/p/g/n/portfolio_manager/lib/mix/tasks/portfolio.eval.run.ex`:

```elixir
defmodule Mix.Tasks.Portfolio.Eval.Run do
  @moduledoc """
  Run evaluation against test cases.

  ## Usage

      mix portfolio.eval.run

  ## Options

  - `--mode` - Search mode: semantic, fulltext, hybrid (default: semantic)
  - `--collection` - Only evaluate test cases for this collection
  - `--generate` - Generate test cases if none exist
  - `--format` - Output format: table, json (default: table)
  - `--fail-under` - Exit with code 1 if recall@5 below threshold
  """

  use Mix.Task

  @shortdoc "Run retrieval evaluation"

  @impl Mix.Task
  def run(args)
end
```

**Test file**: `/home/home/p/g/n/portfolio_manager/test/mix/tasks/portfolio.eval.run_test.exs`

---

## TDD Requirements

For each task:

1. **Write tests FIRST** following existing test patterns in the repos
2. Tests must cover:
   - Metric computations with known values
   - Edge cases (empty lists, no relevant docs)
   - Schema validations
   - Generator with mock LLM
   - CLI option parsing
   - Integration tests with test database
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

# In portfolio_manager
cd /home/home/p/g/n/portfolio_manager
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
- `PortfolioCore.Ports.RetrievalMetrics` behaviour for IR quality metrics
```

### portfolio_index
Update `/home/home/p/g/n/portfolio_index/CHANGELOG.md` - add entry to version 0.3.1:
```markdown
### Added
- `PortfolioIndex.Adapters.RetrievalMetrics.Standard` - Recall@K, Precision@K, MRR, Hit Rate
- `PortfolioIndex.Schemas.TestCase` - Ecto schema for evaluation test cases
- `PortfolioIndex.Schemas.EvaluationRun` - Ecto schema for evaluation run tracking
- `PortfolioIndex.Evaluation.Generator` - LLM-powered synthetic test case generation
- `PortfolioIndex.Evaluation` - Evaluation orchestrator
- Database migrations for evaluation tables
```

### portfolio_manager
Update `/home/home/p/g/n/portfolio_manager/CHANGELOG.md` - add entry to version 0.3.1:
```markdown
### Added
- `mix portfolio.eval.generate` - Generate synthetic evaluation test cases
- `mix portfolio.eval.run` - Run retrieval evaluation with metrics output
```

## Verification Checklist

- [ ] All new files created in correct locations across all three repos
- [ ] All tests pass
- [ ] No credo warnings
- [ ] No dialyzer errors
- [ ] Changelogs updated for all three repos
- [ ] Module documentation complete
- [ ] Type specifications complete

