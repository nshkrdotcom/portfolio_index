defmodule PortfolioIndex.Repo.Migrations.CreatePortfolioEvaluationTables do
  @moduledoc """
  Creates tables for retrieval evaluation.

  Tables:
    - portfolio_evaluation_test_cases: Questions with ground truth
    - portfolio_evaluation_test_case_chunks: Join table for relevant chunks
    - portfolio_evaluation_runs: Historical evaluation results
  """

  use Ecto.Migration

  def change do
    # Test cases table
    create table(:portfolio_evaluation_test_cases, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:question, :text, null: false)
      add(:source, :string, default: "manual")
      add(:collection, :string)
      add(:metadata, :map, default: %{})

      timestamps(type: :utc_datetime)
    end

    create(index(:portfolio_evaluation_test_cases, [:collection]))
    create(index(:portfolio_evaluation_test_cases, [:source]))

    # Join table for test case chunks (ground truth)
    create table(:portfolio_evaluation_test_case_chunks, primary_key: false) do
      add(
        :test_case_id,
        references(:portfolio_evaluation_test_cases, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(
        :chunk_id,
        references(:portfolio_chunks, type: :binary_id, on_delete: :delete_all),
        null: false
      )
    end

    create(unique_index(:portfolio_evaluation_test_case_chunks, [:test_case_id, :chunk_id]))
    create(index(:portfolio_evaluation_test_case_chunks, [:chunk_id]))

    # Evaluation runs table
    create table(:portfolio_evaluation_runs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:status, :string, default: "running")
      add(:config, :map, default: %{})
      add(:aggregate_metrics, :map, default: %{})
      add(:per_case_results, {:array, :map}, default: [])
      add(:error_message, :text)
      add(:started_at, :utc_datetime)
      add(:completed_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:portfolio_evaluation_runs, [:status]))
    create(index(:portfolio_evaluation_runs, [:inserted_at]))
  end
end
