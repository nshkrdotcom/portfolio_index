# Evaluation

PortfolioIndex includes a retrieval evaluation system for measuring and tracking
RAG pipeline quality using standard information retrieval metrics.

## Quick Start

```elixir
alias PortfolioIndex.Evaluation

# Generate synthetic test cases from your data
{:ok, test_cases} = Evaluation.Generator.generate(repo,
  collection: "my_docs",
  count: 20
)

# Run evaluation
{:ok, run} = Evaluation.run(repo,
  test_case_ids: Enum.map(test_cases, & &1.id),
  strategy: :hybrid,
  k: 10
)

# View results
IO.inspect(run.metrics)
# %{recall_at_10: 0.85, precision_at_10: 0.72, mrr: 0.91, hit_rate_at_10: 0.95}
```

## Metrics

`PortfolioIndex.Adapters.RetrievalMetrics.Standard` implements standard IR metrics:

| Metric | Function | Description |
|--------|----------|-------------|
| Recall@K | `recall_at_k/3` | Fraction of relevant items retrieved in top K |
| Precision@K | `precision_at_k/3` | Fraction of retrieved items that are relevant |
| MRR | `mrr/2` | Mean Reciprocal Rank (inverse of first relevant rank) |
| Hit Rate@K | `hit_rate_at_k/3` | 1 if any relevant item appears in top K |

All metrics support aggregation with mean calculation across test cases.

## Test Cases

`PortfolioIndex.Schemas.TestCase` links questions to ground truth chunks:

```elixir
alias PortfolioIndex.Evaluation

# Create a manual test case
{:ok, test_case} = Evaluation.create_test_case(repo, %{
  question: "What is GenServer?",
  source: :manual,
  collection: "elixir_docs"
})

# Link ground truth chunks
Evaluation.add_ground_truth(repo, test_case.id, [chunk_id_1, chunk_id_2])
```

Sources:
- `:manual` -- human-curated test cases
- `:synthetic` -- LLM-generated from chunk content

## Test Case Generation

`PortfolioIndex.Evaluation.Generator` uses an LLM to generate test cases from
your existing chunks:

```elixir
alias PortfolioIndex.Evaluation.Generator

# Generate from a collection
{:ok, test_cases} = Generator.generate(repo,
  collection: "my_docs",
  count: 20
)

# Generate a single question from a chunk
{:ok, question} = Generator.generate_question(repo, chunk_id)
```

The generator samples chunks (with optional collection/source filtering),
generates questions an LLM would need those chunks to answer, and links
the chunks as ground truth.

## Evaluation Runs

`PortfolioIndex.Schemas.EvaluationRun` tracks evaluation history:

```elixir
alias PortfolioIndex.Evaluation

# List past runs
{:ok, runs} = Evaluation.list_runs(repo, limit: 10)

# Compare two runs
{:ok, comparison} = Evaluation.compare_runs(repo, [run_id_1, run_id_2])
```

Run fields:
- `status` -- `:running`, `:completed`, `:failed`
- `metrics` -- aggregate metrics across all test cases
- `per_case_results` -- individual test case scores
- `config` -- strategy, parameters, and settings used
- `started_at` / `completed_at` -- timing information

## Database Tables

The evaluation system uses three tables (created via `mix portfolio.install`):

- `portfolio_evaluation_test_cases` -- questions with source and collection metadata
- `portfolio_evaluation_test_case_chunks` -- join table linking test cases to ground truth chunks
- `portfolio_evaluation_runs` -- run history with metrics and configuration

## Workflow

A typical evaluation workflow:

1. **Ingest documents** using the ingestion pipeline
2. **Generate test cases** from your data using the Generator
3. **Curate** -- review and optionally edit synthetic test cases
4. **Run evaluation** against your RAG strategy
5. **Iterate** -- adjust strategy parameters, re-run, compare results
6. **Track** -- use run history to measure improvements over time
