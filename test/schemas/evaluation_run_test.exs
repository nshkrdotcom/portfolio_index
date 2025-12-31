defmodule PortfolioIndex.Schemas.EvaluationRunTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Schemas.EvaluationRun

  setup tags do
    if tags[:integration] do
      pid = Sandbox.start_owner!(PortfolioIndex.Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    :ok
  end

  # =============================================================================
  # Unit Tests (no database required)
  # =============================================================================

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        started_at: DateTime.utc_now()
      }

      changeset = EvaluationRun.changeset(%EvaluationRun{}, attrs)

      assert changeset.valid?
    end

    test "valid changeset with all fields" do
      now = DateTime.utc_now()

      attrs = %{
        status: :completed,
        config: %{mode: :semantic, collection: "test"},
        aggregate_metrics: %{recall_at_5: 0.85},
        per_case_results: [%{test_case_id: "tc1", recall_at_5: 1.0}],
        started_at: now,
        completed_at: now
      }

      changeset = EvaluationRun.changeset(%EvaluationRun{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == :completed

      assert Ecto.Changeset.get_change(changeset, :config) == %{
               mode: :semantic,
               collection: "test"
             }
    end

    test "default status is :running" do
      run = %EvaluationRun{}
      assert run.status == :running
    end

    test "default config is empty map" do
      run = %EvaluationRun{}
      assert run.config == %{}
    end

    test "default aggregate_metrics is empty map" do
      run = %EvaluationRun{}
      assert run.aggregate_metrics == %{}
    end

    test "default per_case_results is empty list" do
      run = %EvaluationRun{}
      assert run.per_case_results == []
    end
  end

  describe "schema structure" do
    test "has correct primary key type" do
      assert :id in EvaluationRun.__schema__(:primary_key)
      assert EvaluationRun.__schema__(:type, :id) == :binary_id
    end

    test "has expected fields" do
      fields = EvaluationRun.__schema__(:fields)

      assert :id in fields
      assert :status in fields
      assert :config in fields
      assert :aggregate_metrics in fields
      assert :per_case_results in fields
      assert :error_message in fields
      assert :started_at in fields
      assert :completed_at in fields
      assert :inserted_at in fields
      assert :updated_at in fields
    end
  end

  describe "complete/3" do
    test "marks run as completed with results" do
      run = %EvaluationRun{id: Ecto.UUID.generate(), status: :running}

      aggregate = %{
        recall_at_k: %{1 => 0.8, 3 => 0.9, 5 => 0.95, 10 => 1.0},
        precision_at_k: %{1 => 1.0, 3 => 0.8, 5 => 0.6, 10 => 0.4},
        mrr: 0.85,
        hit_rate_at_k: %{1 => 0.8, 3 => 0.9, 5 => 0.95, 10 => 1.0}
      }

      per_case = [
        %{test_case_id: "tc1", recall_at_5: 1.0},
        %{test_case_id: "tc2", recall_at_5: 0.9}
      ]

      changeset = EvaluationRun.complete(run, aggregate, per_case)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == :completed
      assert Ecto.Changeset.get_change(changeset, :aggregate_metrics) == aggregate
      assert Ecto.Changeset.get_change(changeset, :per_case_results) == per_case
      assert Ecto.Changeset.get_change(changeset, :completed_at) != nil
    end
  end

  describe "fail/2" do
    test "marks run as failed with error message" do
      run = %EvaluationRun{id: Ecto.UUID.generate(), status: :running}

      changeset = EvaluationRun.fail(run, "LLM timeout after 30s")

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == :failed
      assert Ecto.Changeset.get_change(changeset, :error_message) == "LLM timeout after 30s"
      assert Ecto.Changeset.get_change(changeset, :completed_at) != nil
    end
  end

  describe "status transitions" do
    test "valid status values" do
      for status <- [:running, :completed, :failed] do
        changeset = EvaluationRun.changeset(%EvaluationRun{}, %{status: status})
        assert changeset.valid?
      end
    end
  end
end
