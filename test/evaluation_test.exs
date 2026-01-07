defmodule PortfolioIndex.EvaluationTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Evaluation
  alias PortfolioIndex.Schemas.{Chunk, EvaluationRun, TestCase}

  describe "evaluate_test_case/3" do
    test "computes metrics for a single test case" do
      test_case = %TestCase{
        id: Ecto.UUID.generate(),
        question: "What is Elixir?",
        relevant_chunks: [
          %Chunk{id: "chunk1", content: "C1", chunk_index: 0},
          %Chunk{id: "chunk2", content: "C2", chunk_index: 1}
        ]
      }

      search_results = [
        %{id: "chunk1"},
        %{id: "chunk3"},
        %{id: "chunk2"}
      ]

      result = Evaluation.evaluate_test_case(test_case, search_results, [])

      assert result.test_case_id == test_case.id
      assert result.question == test_case.question
      assert result.expected_ids == ["chunk1", "chunk2"]
      assert result.retrieved_ids == ["chunk1", "chunk3", "chunk2"]
      assert is_map(result.metrics)
      assert is_map(result.metrics.recall_at_k)
    end
  end

  describe "build_run_result/2" do
    test "builds result with metrics and per-case results" do
      case_results = [
        %{
          test_case_id: "tc1",
          question: "Q1",
          expected_ids: ["c1"],
          retrieved_ids: ["c1", "c2"],
          metrics: %{
            recall_at_k: %{1 => 1.0, 3 => 1.0, 5 => 1.0, 10 => 1.0},
            precision_at_k: %{1 => 1.0, 3 => 0.33, 5 => 0.2, 10 => 0.1},
            mrr: 1.0,
            hit_rate_at_k: %{1 => 1.0, 3 => 1.0, 5 => 1.0, 10 => 1.0}
          }
        }
      ]

      run = %EvaluationRun{id: Ecto.UUID.generate(), status: :running}

      result = Evaluation.build_run_result(run, case_results)

      assert result.status == :completed
      assert is_map(result.aggregate_metrics)
      assert is_list(result.per_case_results)
    end
  end

  describe "compare_runs/2" do
    test "compares two evaluation runs" do
      run1 = %EvaluationRun{
        id: Ecto.UUID.generate(),
        aggregate_metrics: %{
          recall_at_k: %{1 => 0.8, 3 => 0.85, 5 => 0.9, 10 => 0.95},
          precision_at_k: %{1 => 1.0, 3 => 0.8, 5 => 0.6, 10 => 0.4},
          mrr: 0.85,
          hit_rate_at_k: %{1 => 0.8, 3 => 0.9, 5 => 0.95, 10 => 1.0}
        }
      }

      run2 = %EvaluationRun{
        id: Ecto.UUID.generate(),
        aggregate_metrics: %{
          recall_at_k: %{1 => 0.9, 3 => 0.92, 5 => 0.95, 10 => 0.98},
          precision_at_k: %{1 => 1.0, 3 => 0.85, 5 => 0.65, 10 => 0.45},
          mrr: 0.90,
          hit_rate_at_k: %{1 => 0.9, 3 => 0.95, 5 => 0.98, 10 => 1.0}
        }
      }

      comparison = Evaluation.compare_runs(run1, run2)

      assert is_map(comparison)
      assert Map.has_key?(comparison, :recall_at_k_diff)
      assert Map.has_key?(comparison, :mrr_diff)
      assert_in_delta comparison.mrr_diff, 0.05, 0.001
    end

    test "handles comparison with empty metrics" do
      run1 = %EvaluationRun{aggregate_metrics: %{}}
      run2 = %EvaluationRun{aggregate_metrics: %{}}

      comparison = Evaluation.compare_runs(run1, run2)
      assert is_map(comparison)
    end
  end

  describe "extract_chunk_ids/1" do
    test "extracts ids from chunks" do
      chunks = [
        %Chunk{id: "a", content: "A", chunk_index: 0},
        %Chunk{id: "b", content: "B", chunk_index: 1}
      ]

      ids = Evaluation.extract_chunk_ids(chunks)
      assert ids == ["a", "b"]
    end

    test "handles empty list" do
      assert Evaluation.extract_chunk_ids([]) == []
    end
  end

  describe "extract_result_ids/1" do
    test "extracts ids from search results" do
      results = [
        %{id: "x", score: 0.9},
        %{id: "y", score: 0.8}
      ]

      ids = Evaluation.extract_result_ids(results)
      assert ids == ["x", "y"]
    end

    test "handles results with string keys" do
      results = [
        %{"id" => "x"},
        %{"id" => "y"}
      ]

      ids = Evaluation.extract_result_ids(results)
      assert ids == ["x", "y"]
    end
  end
end
