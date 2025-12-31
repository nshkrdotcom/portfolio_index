defmodule PortfolioIndex.Adapters.RetrievalMetrics.Standard do
  @moduledoc """
  Standard information retrieval metrics implementation.
  Computes Recall@K, Precision@K, MRR, and Hit Rate@K.

  ## Metrics

    * **Recall@K** - What fraction of relevant documents appear in top K?
    * **Precision@K** - What fraction of top K results are relevant?
    * **MRR** - Mean Reciprocal Rank: 1/position of first relevant result
    * **Hit Rate@K** - Did we find at least one relevant document in top K?

  ## Usage

      expected_ids = ["chunk1", "chunk2", "chunk3"]
      retrieved_ids = ["chunk1", "chunk5", "chunk2", "chunk6"]

      {:ok, metrics} = Standard.compute(expected_ids, retrieved_ids, [])
      # => %{
      #   recall_at_k: %{1 => 0.33, 3 => 0.67, 5 => 0.67, 10 => 0.67},
      #   precision_at_k: %{1 => 1.0, 3 => 0.67, 5 => 0.4, 10 => 0.2},
      #   mrr: 1.0,
      #   hit_rate_at_k: %{1 => 1.0, 3 => 1.0, 5 => 1.0, 10 => 1.0}
      # }
  """

  @behaviour PortfolioCore.Ports.RetrievalMetrics

  @default_k_values [1, 3, 5, 10]

  @impl true
  @spec compute([String.t()], [String.t()], keyword()) ::
          {:ok, PortfolioCore.Ports.RetrievalMetrics.metric_result()} | {:error, term()}
  def compute(expected_ids, retrieved_ids, opts \\ []) do
    k_values = Keyword.get(opts, :k_values, @default_k_values)

    recall = compute_recall_at_k(expected_ids, retrieved_ids, k_values)
    precision = compute_precision_at_k(expected_ids, retrieved_ids, k_values)
    mrr_value = mrr(expected_ids, retrieved_ids)
    hit_rate = compute_hit_rate_at_k(expected_ids, retrieved_ids, k_values)

    {:ok,
     %{
       recall_at_k: recall,
       precision_at_k: precision,
       mrr: mrr_value,
       hit_rate_at_k: hit_rate
     }}
  end

  @impl true
  @spec aggregate([PortfolioCore.Ports.RetrievalMetrics.test_case_result()]) ::
          {:ok, PortfolioCore.Ports.RetrievalMetrics.metric_result()} | {:error, term()}
  def aggregate(results) when is_list(results) do
    n = length(results)

    if n == 0 do
      {:ok, empty_metrics()}
    else
      recall = aggregate_metric_at_k(results, :recall_at_k, n)
      precision = aggregate_metric_at_k(results, :precision_at_k, n)
      mrr_avg = avg_field(results, :mrr, n)
      hit_rate = aggregate_metric_at_k(results, :hit_rate_at_k, n)

      {:ok,
       %{
         recall_at_k: recall,
         precision_at_k: precision,
         mrr: mrr_avg,
         hit_rate_at_k: hit_rate
       }}
    end
  end

  @doc """
  Compute Recall@K - fraction of relevant docs in top K.

  Recall answers: "What fraction of relevant documents did we find?"

  ## Examples

      iex> Standard.recall_at_k(["a", "b"], ["a", "c", "b"], 3)
      1.0

      iex> Standard.recall_at_k(["a", "b"], ["a", "c", "d"], 3)
      0.5
  """
  @spec recall_at_k([String.t()], [String.t()], pos_integer()) :: float()
  def recall_at_k(expected_ids, retrieved_ids, k)
      when is_list(expected_ids) and is_list(retrieved_ids) and is_integer(k) and k > 0 do
    expected_set = MapSet.new(expected_ids)
    expected_size = MapSet.size(expected_set)

    if expected_size == 0 do
      0.0
    else
      top_k = retrieved_ids |> Enum.take(k) |> MapSet.new()
      hits = MapSet.intersection(top_k, expected_set) |> MapSet.size()
      hits / expected_size
    end
  end

  @doc """
  Compute Precision@K - fraction of top K that are relevant.

  Precision answers: "Of the documents we returned, how many were relevant?"

  ## Examples

      iex> Standard.precision_at_k(["a", "b"], ["a", "b", "c"], 3)
      0.667

      iex> Standard.precision_at_k(["a"], ["a", "b"], 2)
      0.5
  """
  @spec precision_at_k([String.t()], [String.t()], pos_integer()) :: float()
  def precision_at_k(expected_ids, retrieved_ids, k)
      when is_list(expected_ids) and is_list(retrieved_ids) and is_integer(k) and k > 0 do
    if retrieved_ids == [] or expected_ids == [] do
      0.0
    else
      expected_set = MapSet.new(expected_ids)
      top_k = Enum.take(retrieved_ids, k)
      hits = Enum.count(top_k, &MapSet.member?(expected_set, &1))
      hits / k
    end
  end

  @doc """
  Compute MRR - 1/position of first relevant result.

  Mean Reciprocal Rank measures how high the first relevant result appears.

  ## Examples

      iex> Standard.mrr(["a"], ["a", "b", "c"])
      1.0

      iex> Standard.mrr(["b"], ["a", "b", "c"])
      0.5

      iex> Standard.mrr(["c"], ["a", "b", "c"])
      0.333
  """
  @spec mrr([String.t()], [String.t()]) :: float()
  def mrr(expected_ids, retrieved_ids) when is_list(expected_ids) and is_list(retrieved_ids) do
    if expected_ids == [] or retrieved_ids == [] do
      0.0
    else
      expected_set = MapSet.new(expected_ids)

      case Enum.find_index(retrieved_ids, &MapSet.member?(expected_set, &1)) do
        nil -> 0.0
        idx -> 1.0 / (idx + 1)
      end
    end
  end

  @doc """
  Compute Hit Rate@K - 1 if any relevant in top K, else 0.

  Hit Rate answers: "Did we find at least one relevant document?"

  ## Examples

      iex> Standard.hit_rate_at_k(["b"], ["a", "b", "c"], 3)
      1.0

      iex> Standard.hit_rate_at_k(["d"], ["a", "b", "c"], 3)
      0.0
  """
  @spec hit_rate_at_k([String.t()], [String.t()], pos_integer()) :: float()
  def hit_rate_at_k(expected_ids, retrieved_ids, k)
      when is_list(expected_ids) and is_list(retrieved_ids) and is_integer(k) and k > 0 do
    if expected_ids == [] or retrieved_ids == [] do
      0.0
    else
      expected_set = MapSet.new(expected_ids)
      top_k = retrieved_ids |> Enum.take(k) |> MapSet.new()
      has_hit = MapSet.intersection(top_k, expected_set) |> MapSet.size() > 0
      if has_hit, do: 1.0, else: 0.0
    end
  end

  # Private helpers

  defp compute_recall_at_k(expected_ids, retrieved_ids, k_values) do
    Map.new(k_values, fn k -> {k, recall_at_k(expected_ids, retrieved_ids, k)} end)
  end

  defp compute_precision_at_k(expected_ids, retrieved_ids, k_values) do
    Map.new(k_values, fn k -> {k, precision_at_k(expected_ids, retrieved_ids, k)} end)
  end

  defp compute_hit_rate_at_k(expected_ids, retrieved_ids, k_values) do
    Map.new(k_values, fn k -> {k, hit_rate_at_k(expected_ids, retrieved_ids, k)} end)
  end

  defp aggregate_metric_at_k(results, metric_key, n) do
    k_values = @default_k_values

    Map.new(k_values, fn k ->
      sum =
        Enum.reduce(results, 0.0, fn result, acc ->
          acc + get_in(result, [:metrics, metric_key, k])
        end)

      {k, sum / n}
    end)
  end

  defp avg_field(results, field, n) do
    sum = Enum.reduce(results, 0.0, fn result, acc -> acc + get_in(result, [:metrics, field]) end)
    sum / n
  end

  defp empty_metrics do
    %{
      recall_at_k: Map.new(@default_k_values, &{&1, 0.0}),
      precision_at_k: Map.new(@default_k_values, &{&1, 0.0}),
      mrr: 0.0,
      hit_rate_at_k: Map.new(@default_k_values, &{&1, 0.0})
    }
  end
end
