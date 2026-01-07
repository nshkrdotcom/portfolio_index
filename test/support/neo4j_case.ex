defmodule PortfolioIndex.Neo4jCase do
  @moduledoc """
  Test case for Neo4j integration tests.

  Provides graph isolation per test using unique graph IDs,
  and automatic cleanup after each test.

  ## Usage

      defmodule MyTest do
        use PortfolioIndex.Neo4jCase, async: true

        test "creates a node", %{graph_id: graph_id} do
          {:ok, node} = Neo4j.create_node(graph_id, %{
            labels: ["Test"],
            properties: %{name: "test"}
          })

          assert node.id
        end
      end

  ## Options

  - `:async` - Whether tests can run concurrently (default: true)
  - `:cleanup` - Whether to clean up after tests (default: true)
  """

  use ExUnit.CaseTemplate

  alias PortfolioIndex.Adapters.GraphStore.Neo4j
  alias PortfolioIndex.Adapters.GraphStore.Neo4j.Schema

  using do
    quote do
      import PortfolioIndex.Neo4jCase
      alias PortfolioIndex.Adapters.GraphStore.Neo4j
    end
  end

  setup tags do
    # Generate unique graph ID for test isolation
    graph_id = "test_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"

    # Create the graph namespace
    case Neo4j.create_graph(graph_id, %{}) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Failed to create test graph: #{inspect(reason)}"
    end

    # Register cleanup unless disabled
    unless tags[:cleanup] == false do
      on_exit(fn ->
        Schema.clean_graph!(graph_id)
      end)
    end

    {:ok, graph_id: graph_id}
  end

  @doc """
  Create a test node with default properties.
  """
  def create_test_node(graph_id, opts \\ []) do
    labels = Keyword.get(opts, :labels, ["TestNode"])
    name = Keyword.get(opts, :name, "test_node_#{:rand.uniform(10000)}")

    properties =
      Keyword.get(opts, :properties, %{})
      |> Map.put(:name, name)
      |> Map.put(:created_at, DateTime.utc_now() |> DateTime.to_iso8601())

    Neo4j.create_node(graph_id, %{
      labels: labels,
      properties: properties
    })
  end

  @doc """
  Create a test edge between nodes.
  """
  def create_test_edge(graph_id, from_id, to_id, opts \\ []) do
    type = Keyword.get(opts, :type, "TEST_RELATES_TO")
    properties = Keyword.get(opts, :properties, %{})

    Neo4j.create_edge(graph_id, %{
      from_id: from_id,
      to_id: to_id,
      type: type,
      properties: properties
    })
  end

  @doc """
  Create a connected graph of test nodes.
  Returns {nodes, edges} tuple.
  """
  def create_test_graph(graph_id, node_count \\ 5) do
    # Create nodes
    nodes =
      for i <- 1..node_count do
        {:ok, node} = create_test_node(graph_id, name: "node_#{i}", labels: ["TestNode"])
        node
      end

    # Create edges (chain pattern: 1->2->3->4->5)
    edges =
      for {from, to} <- Enum.zip(Enum.drop(nodes, -1), Enum.drop(nodes, 1)) do
        {:ok, edge} = create_test_edge(graph_id, from.id, to.id)
        edge
      end

    {nodes, edges}
  end

  @doc """
  Wait for Neo4j to be available.
  Useful for ensuring connection is ready in async tests.
  """
  def await_neo4j(timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn -> check_neo4j_connection(deadline) end)
    |> Enum.find(&(&1 != :retry))
  end

  defp check_neo4j_connection(deadline) do
    case Boltx.query(Boltx, "RETURN 1") do
      {:ok, _} -> :ok
      {:error, _} -> handle_connection_retry(deadline)
    end
  end

  defp handle_connection_retry(deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      receive do
      after
        100 -> :ok
      end

      :retry
    else
      :timeout
    end
  end
end
