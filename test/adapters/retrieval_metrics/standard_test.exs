defmodule PortfolioIndex.Adapters.RetrievalMetrics.StandardTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.RetrievalMetrics.Standard

  describe "compute/3" do
    test "computes all metrics for typical case" do
      expected_ids = ["c1", "c2"]
      retrieved_ids = ["c1", "c3", "c2", "c4", "c5"]

      assert {:ok, metrics} = Standard.compute(expected_ids, retrieved_ids, [])

      # Verify structure
      assert is_map(metrics.recall_at_k)
      assert is_map(metrics.precision_at_k)
      assert is_float(metrics.mrr)
      assert is_map(metrics.hit_rate_at_k)

      # Check K values
      for k <- [1, 3, 5, 10] do
        assert Map.has_key?(metrics.recall_at_k, k)
        assert Map.has_key?(metrics.precision_at_k, k)
        assert Map.has_key?(metrics.hit_rate_at_k, k)
      end
    end

    test "handles empty expected_ids" do
      assert {:ok, metrics} = Standard.compute([], ["c1", "c2"], [])

      # All recall and hit rates should be 0 for empty expected
      for k <- [1, 3, 5, 10] do
        assert metrics.recall_at_k[k] == 0.0
        assert metrics.hit_rate_at_k[k] == 0.0
      end

      assert metrics.mrr == 0.0
    end

    test "handles empty retrieved_ids" do
      assert {:ok, metrics} = Standard.compute(["c1", "c2"], [], [])

      # All metrics should be 0 for empty retrieved
      for k <- [1, 3, 5, 10] do
        assert metrics.recall_at_k[k] == 0.0
        assert metrics.precision_at_k[k] == 0.0
        assert metrics.hit_rate_at_k[k] == 0.0
      end

      assert metrics.mrr == 0.0
    end

    test "handles custom k_values option" do
      expected_ids = ["c1"]
      retrieved_ids = ["c1", "c2", "c3"]

      assert {:ok, metrics} = Standard.compute(expected_ids, retrieved_ids, k_values: [1, 2])

      # Should only have specified K values
      assert Map.keys(metrics.recall_at_k) |> Enum.sort() == [1, 2]
      assert Map.keys(metrics.precision_at_k) |> Enum.sort() == [1, 2]
      assert Map.keys(metrics.hit_rate_at_k) |> Enum.sort() == [1, 2]
    end
  end

  describe "recall_at_k/3" do
    test "returns 1.0 when all expected are in top K" do
      expected = ["c1", "c2"]
      retrieved = ["c1", "c2", "c3"]

      assert Standard.recall_at_k(expected, retrieved, 3) == 1.0
    end

    test "returns 0.5 when half of expected are in top K" do
      expected = ["c1", "c2"]
      retrieved = ["c1", "c3", "c4"]

      assert Standard.recall_at_k(expected, retrieved, 3) == 0.5
    end

    test "returns 0.0 when none of expected are in top K" do
      expected = ["c1", "c2"]
      retrieved = ["c3", "c4", "c5"]

      assert Standard.recall_at_k(expected, retrieved, 3) == 0.0
    end

    test "returns 0.0 for empty expected" do
      assert Standard.recall_at_k([], ["c1", "c2"], 3) == 0.0
    end

    test "returns 0.0 for empty retrieved" do
      assert Standard.recall_at_k(["c1", "c2"], [], 3) == 0.0
    end

    test "handles K larger than retrieved list" do
      expected = ["c1", "c2"]
      retrieved = ["c1"]

      # Should still work, just with fewer items
      assert Standard.recall_at_k(expected, retrieved, 10) == 0.5
    end
  end

  describe "precision_at_k/3" do
    test "returns 1.0 when all top K are relevant" do
      expected = ["c1", "c2", "c3"]
      retrieved = ["c1", "c2", "c3", "c4"]

      assert Standard.precision_at_k(expected, retrieved, 3) == 1.0
    end

    test "returns 0.5 when half of top K are relevant" do
      expected = ["c1"]
      retrieved = ["c1", "c2"]

      assert Standard.precision_at_k(expected, retrieved, 2) == 0.5
    end

    test "returns 0.0 when none of top K are relevant" do
      expected = ["c1"]
      retrieved = ["c2", "c3", "c4"]

      assert Standard.precision_at_k(expected, retrieved, 3) == 0.0
    end

    test "handles K larger than retrieved list" do
      expected = ["c1"]
      retrieved = ["c1"]

      # Precision@10 with only 1 item should be 1/10 = 0.1
      assert Standard.precision_at_k(expected, retrieved, 10) == 0.1
    end

    test "returns 0.0 for empty expected" do
      assert Standard.precision_at_k([], ["c1", "c2"], 3) == 0.0
    end

    test "returns 0.0 for empty retrieved" do
      assert Standard.precision_at_k(["c1", "c2"], [], 3) == 0.0
    end
  end

  describe "mrr/2" do
    test "returns 1.0 when first result is relevant" do
      expected = ["c1", "c2"]
      retrieved = ["c1", "c3", "c4"]

      assert Standard.mrr(expected, retrieved) == 1.0
    end

    test "returns 0.5 when second result is first relevant" do
      expected = ["c2"]
      retrieved = ["c1", "c2", "c3"]

      assert Standard.mrr(expected, retrieved) == 0.5
    end

    test "returns 0.33 when third result is first relevant" do
      expected = ["c3"]
      retrieved = ["c1", "c2", "c3", "c4"]

      assert_in_delta Standard.mrr(expected, retrieved), 0.333, 0.01
    end

    test "returns 0.0 when no relevant results" do
      expected = ["c1"]
      retrieved = ["c2", "c3", "c4"]

      assert Standard.mrr(expected, retrieved) == 0.0
    end

    test "returns 0.0 for empty expected" do
      assert Standard.mrr([], ["c1", "c2"]) == 0.0
    end

    test "returns 0.0 for empty retrieved" do
      assert Standard.mrr(["c1", "c2"], []) == 0.0
    end
  end

  describe "hit_rate_at_k/3" do
    test "returns 1.0 when any relevant in top K" do
      expected = ["c2"]
      retrieved = ["c1", "c2", "c3"]

      assert Standard.hit_rate_at_k(expected, retrieved, 3) == 1.0
    end

    test "returns 0.0 when no relevant in top K" do
      expected = ["c4"]
      retrieved = ["c1", "c2", "c3"]

      assert Standard.hit_rate_at_k(expected, retrieved, 3) == 0.0
    end

    test "returns 1.0 when first result is relevant" do
      expected = ["c1"]
      retrieved = ["c1", "c2", "c3"]

      assert Standard.hit_rate_at_k(expected, retrieved, 1) == 1.0
    end

    test "returns 0.0 for empty expected" do
      assert Standard.hit_rate_at_k([], ["c1", "c2"], 3) == 0.0
    end

    test "returns 0.0 for empty retrieved" do
      assert Standard.hit_rate_at_k(["c1", "c2"], [], 3) == 0.0
    end
  end

  describe "aggregate/1" do
    test "averages metrics across test cases" do
      results = [
        %{
          test_case_id: "tc1",
          question: "Q1",
          expected_ids: ["c1"],
          retrieved_ids: ["c1"],
          metrics: %{
            recall_at_k: %{1 => 1.0, 3 => 1.0, 5 => 1.0, 10 => 1.0},
            precision_at_k: %{1 => 1.0, 3 => 0.33, 5 => 0.2, 10 => 0.1},
            mrr: 1.0,
            hit_rate_at_k: %{1 => 1.0, 3 => 1.0, 5 => 1.0, 10 => 1.0}
          }
        },
        %{
          test_case_id: "tc2",
          question: "Q2",
          expected_ids: ["c2"],
          retrieved_ids: ["c1", "c2"],
          metrics: %{
            recall_at_k: %{1 => 0.0, 3 => 1.0, 5 => 1.0, 10 => 1.0},
            precision_at_k: %{1 => 0.0, 3 => 0.33, 5 => 0.2, 10 => 0.1},
            mrr: 0.5,
            hit_rate_at_k: %{1 => 0.0, 3 => 1.0, 5 => 1.0, 10 => 1.0}
          }
        }
      ]

      assert {:ok, aggregated} = Standard.aggregate(results)

      # Average of 1.0 and 0.0 = 0.5
      assert aggregated.recall_at_k[1] == 0.5
      # Average of 1.0 and 1.0 = 1.0
      assert aggregated.recall_at_k[3] == 1.0

      # Average MRR: (1.0 + 0.5) / 2 = 0.75
      assert aggregated.mrr == 0.75

      # Average hit rate at 1: (1.0 + 0.0) / 2 = 0.5
      assert aggregated.hit_rate_at_k[1] == 0.5
    end

    test "returns zeros for empty list" do
      assert {:ok, metrics} = Standard.aggregate([])

      for k <- [1, 3, 5, 10] do
        assert metrics.recall_at_k[k] == 0.0
        assert metrics.precision_at_k[k] == 0.0
        assert metrics.hit_rate_at_k[k] == 0.0
      end

      assert metrics.mrr == 0.0
    end

    test "handles single result" do
      results = [
        %{
          test_case_id: "tc1",
          question: "Q1",
          expected_ids: ["c1"],
          retrieved_ids: ["c1"],
          metrics: %{
            recall_at_k: %{1 => 1.0, 3 => 1.0, 5 => 1.0, 10 => 1.0},
            precision_at_k: %{1 => 1.0, 3 => 0.33, 5 => 0.2, 10 => 0.1},
            mrr: 1.0,
            hit_rate_at_k: %{1 => 1.0, 3 => 1.0, 5 => 1.0, 10 => 1.0}
          }
        }
      ]

      assert {:ok, aggregated} = Standard.aggregate(results)

      # Should equal the single result
      assert aggregated.recall_at_k[1] == 1.0
      assert aggregated.mrr == 1.0
    end
  end
end
