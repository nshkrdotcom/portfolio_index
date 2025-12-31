defmodule PortfolioIndex.Schemas.EvaluationRun do
  @moduledoc """
  Ecto schema for tracking evaluation runs.
  Stores configuration, status, and results for historical comparison.

  ## Overview

  An evaluation run captures a complete evaluation session including:
    - Configuration used (search mode, filters, etc.)
    - Aggregate metrics across all test cases
    - Per-case results for drill-down analysis
    - Timing and status information

  ## Status Values

    - `:running` - Evaluation is in progress
    - `:completed` - Evaluation finished successfully
    - `:failed` - Evaluation encountered an error

  ## Usage

      # Start a new run
      {:ok, run} =
        %EvaluationRun{}
        |> EvaluationRun.changeset(%{
          config: %{mode: :semantic},
          started_at: DateTime.utc_now()
        })
        |> Repo.insert()

      # Complete the run
      run
      |> EvaluationRun.complete(aggregate_metrics, per_case_results)
      |> Repo.update()

      # Or mark as failed
      run
      |> EvaluationRun.fail("Connection timeout")
      |> Repo.update()
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
    field(:status, Ecto.Enum, values: [:running, :completed, :failed], default: :running)
    field(:config, :map, default: %{})
    field(:aggregate_metrics, :map, default: %{})
    field(:per_case_results, {:array, :map}, default: [])
    field(:error_message, :string)
    field(:started_at, :utc_datetime)
    field(:completed_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating evaluation runs.

  ## Fields
    - `:status` - Run status (`:running`, `:completed`, `:failed`)
    - `:config` - Configuration used for this run
    - `:aggregate_metrics` - Summary metrics across all test cases
    - `:per_case_results` - List of per-test-case results
    - `:error_message` - Error message if run failed
    - `:started_at` - When the run started
    - `:completed_at` - When the run finished
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :config,
      :aggregate_metrics,
      :per_case_results,
      :error_message,
      :started_at,
      :completed_at
    ])
  end

  @doc """
  Mark run as completed with results.

  Sets the status to `:completed` and stores the aggregate metrics
  and per-case results. Also sets `completed_at` to the current time.

  ## Parameters
    - `run` - The evaluation run to complete
    - `aggregate_metrics` - Summary metrics (recall@K, precision@K, etc.)
    - `per_case_results` - List of results for each test case

  ## Example

      run
      |> EvaluationRun.complete(
        %{recall_at_k: %{5 => 0.85}, mrr: 0.9},
        [%{test_case_id: "tc1", ...}]
      )
      |> Repo.update()
  """
  @spec complete(t(), map(), [map()]) :: Ecto.Changeset.t()
  def complete(run, aggregate_metrics, per_case_results) do
    run
    |> changeset(%{
      status: :completed,
      aggregate_metrics: aggregate_metrics,
      per_case_results: per_case_results,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Mark run as failed with error.

  Sets the status to `:failed` and stores the error message.
  Also sets `completed_at` to the current time.

  ## Parameters
    - `run` - The evaluation run that failed
    - `error_message` - Description of what went wrong

  ## Example

      run
      |> EvaluationRun.fail("LLM rate limited after 50 requests")
      |> Repo.update()
  """
  @spec fail(t(), String.t()) :: Ecto.Changeset.t()
  def fail(run, error_message) do
    run
    |> changeset(%{
      status: :failed,
      error_message: error_message,
      completed_at: DateTime.utc_now()
    })
  end
end
