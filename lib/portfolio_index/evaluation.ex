defmodule PortfolioIndex.Evaluation do
  @moduledoc """
  Main entry point for retrieval evaluation.
  Orchestrates test case execution and metrics computation.

  ## Overview

  The Evaluation module provides a complete workflow for measuring
  retrieval quality:

  1. Create/generate test cases with ground truth
  2. Run evaluation against those test cases
  3. Store results for historical comparison
  4. Compare runs to track improvements

  ## Usage

      # Run evaluation
      {:ok, run} = Evaluation.run(Repo, [
        mode: :semantic,
        search_fn: &MySearch.search/2
      ])

      # View results
      run.aggregate_metrics
      # => %{recall_at_k: %{5 => 0.85}, mrr: 0.9, ...}

      # Compare runs
      Evaluation.compare_runs(run1, run2)
      # => %{recall_at_k_diff: %{5 => 0.05}, ...}
  """

  import Ecto.Query

  alias PortfolioIndex.Adapters.RetrievalMetrics.Standard
  alias PortfolioIndex.Schemas.{Chunk, EvaluationRun, TestCase}

  # Dialyzer struggles with Map.put type inference in Ecto changeset contexts
  @dialyzer {:nowarn_function, create_test_case: 2}

  @type run_opts :: [
          mode: :semantic | :fulltext | :hybrid,
          collection: String.t() | nil,
          limit: pos_integer() | nil,
          search_fn: (String.t(), keyword() -> [map()]),
          evaluate_answer: boolean()
        ]

  @doc """
  Run evaluation against all or filtered test cases.

  Executes the search function for each test case and computes
  retrieval metrics. Stores results in an EvaluationRun record.

  ## Options
    - `:mode` - Search mode (default: :semantic)
    - `:collection` - Filter test cases by collection
    - `:limit` - Max test cases to evaluate
    - `:search_fn` - Custom search function (required)
    - `:evaluate_answer` - Also evaluate answer quality (default: false)

  ## Returns
    - `{:ok, EvaluationRun.t()}` - Completed run with metrics
    - `{:error, :no_test_cases}` - No test cases found
    - `{:error, term()}` - Other error
  """
  @spec run(Ecto.Repo.t(), run_opts()) :: {:ok, EvaluationRun.t()} | {:error, term()}
  def run(repo, opts \\ []) do
    mode = Keyword.get(opts, :mode, :semantic)
    collection = Keyword.get(opts, :collection)
    limit = Keyword.get(opts, :limit)
    search_fn = Keyword.get(opts, :search_fn)

    if is_nil(search_fn) do
      {:error, :search_fn_required}
    else
      test_cases = list_test_cases(repo, collection: collection, limit: limit)

      if Enum.empty?(test_cases) do
        {:error, :no_test_cases}
      else
        run_config = %{mode: mode, collection: collection}

        # Create a run record
        {:ok, run} =
          %EvaluationRun{}
          |> EvaluationRun.changeset(%{
            status: :running,
            config: run_config,
            started_at: DateTime.utc_now()
          })
          |> repo.insert()

        # Evaluate each test case
        case_results =
          Enum.map(test_cases, fn test_case ->
            search_results = search_fn.(test_case.question, mode: mode)
            evaluate_test_case(test_case, search_results, opts)
          end)

        # Aggregate metrics
        {:ok, aggregate} = Standard.aggregate(case_results)

        # Update run with results
        {:ok, completed_run} =
          run
          |> EvaluationRun.complete(aggregate, case_results)
          |> repo.update()

        {:ok, completed_run}
      end
    end
  end

  @doc """
  List all test cases.

  ## Options
    - `:collection` - Filter by collection
    - `:limit` - Max number to return
  """
  @spec list_test_cases(Ecto.Repo.t(), keyword()) :: [TestCase.t()]
  def list_test_cases(repo, opts \\ []) do
    collection = Keyword.get(opts, :collection)
    limit = Keyword.get(opts, :limit)

    query =
      from(tc in TestCase,
        preload: [:relevant_chunks],
        order_by: [desc: tc.inserted_at]
      )

    query =
      if collection do
        from(tc in query, where: tc.collection == ^collection)
      else
        query
      end

    query =
      if limit do
        from(tc in query, limit: ^limit)
      else
        query
      end

    repo.all(query)
  end

  @doc """
  Create a manual test case.

  ## Attributes
    - `:question` - The question text (required)
    - `:collection` - Collection name
    - `:metadata` - Arbitrary metadata
  """
  @spec create_test_case(Ecto.Repo.t(), map()) ::
          {:ok, TestCase.t()} | {:error, Ecto.Changeset.t()}
  def create_test_case(repo, attrs) when is_map(attrs) do
    %TestCase{}
    |> TestCase.changeset(Map.put(attrs, :source, :manual))
    |> repo.insert()
  end

  @doc """
  Add relevant chunks to a test case (ground truth).

  Links the specified chunks to the test case via the join table.
  """
  @spec add_ground_truth(Ecto.Repo.t(), TestCase.t(), [String.t()]) ::
          {:ok, TestCase.t()} | {:error, term()}
  def add_ground_truth(repo, test_case, chunk_ids) when is_list(chunk_ids) do
    chunks = repo.all(from(c in Chunk, where: c.id in ^chunk_ids))

    test_case
    |> repo.preload(:relevant_chunks)
    |> TestCase.add_relevant_chunks(chunks)
    |> repo.update()
  end

  @doc """
  Get historical evaluation runs.

  ## Options
    - `:limit` - Max runs to return (default: 20)
    - `:status` - Filter by status
  """
  @spec list_runs(Ecto.Repo.t(), keyword()) :: [EvaluationRun.t()]
  def list_runs(repo, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    status = Keyword.get(opts, :status)

    query =
      from(r in EvaluationRun,
        order_by: [desc: r.inserted_at],
        limit: ^limit
      )

    query =
      if status do
        from(r in query, where: r.status == ^status)
      else
        query
      end

    repo.all(query)
  end

  @doc """
  Compare two evaluation runs.

  Returns differences in metrics between the runs.
  Positive values indicate run2 improved over run1.
  """
  @spec compare_runs(EvaluationRun.t(), EvaluationRun.t()) :: map()
  def compare_runs(run1, run2) do
    m1 = run1.aggregate_metrics || %{}
    m2 = run2.aggregate_metrics || %{}

    %{
      recall_at_k_diff: diff_at_k(get_metric(m1, :recall_at_k), get_metric(m2, :recall_at_k)),
      precision_at_k_diff:
        diff_at_k(get_metric(m1, :precision_at_k), get_metric(m2, :precision_at_k)),
      hit_rate_at_k_diff:
        diff_at_k(get_metric(m1, :hit_rate_at_k), get_metric(m2, :hit_rate_at_k)),
      mrr_diff: get_metric(m2, :mrr, 0.0) - get_metric(m1, :mrr, 0.0)
    }
  end

  @doc """
  Evaluate a single test case against search results.

  Computes retrieval metrics by comparing expected chunks (ground truth)
  with actually retrieved chunks.
  """
  @spec evaluate_test_case(TestCase.t(), [map()], keyword()) :: map()
  def evaluate_test_case(test_case, search_results, _opts) do
    expected_ids = extract_chunk_ids(test_case.relevant_chunks)
    retrieved_ids = extract_result_ids(search_results)

    {:ok, metrics} = Standard.compute(expected_ids, retrieved_ids, [])

    %{
      test_case_id: test_case.id,
      question: test_case.question,
      expected_ids: expected_ids,
      retrieved_ids: retrieved_ids,
      metrics: metrics
    }
  end

  @doc """
  Build the final run result from case results.
  """
  @spec build_run_result(EvaluationRun.t(), [map()]) :: map()
  def build_run_result(_run, case_results) do
    {:ok, aggregate} = Standard.aggregate(case_results)

    %{
      status: :completed,
      aggregate_metrics: aggregate,
      per_case_results: case_results
    }
  end

  @doc """
  Extract chunk IDs from a list of chunk structs.
  """
  @spec extract_chunk_ids([Chunk.t()] | term()) :: [String.t()]
  def extract_chunk_ids(chunks) when is_list(chunks) do
    Enum.map(chunks, fn chunk ->
      case chunk do
        %{id: id} -> id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def extract_chunk_ids(_), do: []

  @doc """
  Extract IDs from search result maps.
  """
  @spec extract_result_ids([map()]) :: [String.t()]
  def extract_result_ids(results) when is_list(results) do
    Enum.map(results, fn result ->
      result[:id] || result["id"]
    end)
    |> Enum.reject(&is_nil/1)
  end

  def extract_result_ids(_), do: []

  # Private helpers

  defp get_metric(metrics, key, default \\ nil) do
    metrics[key] || metrics[Atom.to_string(key)] || default
  end

  defp diff_at_k(nil, nil), do: %{}
  defp diff_at_k(nil, _), do: %{}
  defp diff_at_k(_, nil), do: %{}

  defp diff_at_k(m1, m2) when is_map(m1) and is_map(m2) do
    keys = Map.keys(m1) ++ Map.keys(m2)
    keys = Enum.uniq(keys)

    Map.new(keys, fn k ->
      v1 = m1[k] || 0.0
      v2 = m2[k] || 0.0
      {k, v2 - v1}
    end)
  end
end
