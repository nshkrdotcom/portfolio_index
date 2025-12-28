defmodule PortfolioIndex.Adapters.GraphStore.Neo4jTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.GraphStore.Neo4j

  # =============================================================================
  # Unit Tests (no database required)
  # =============================================================================

  describe "module attributes" do
    test "implements GraphStore behaviour" do
      behaviours = Neo4j.__info__(:attributes)[:behaviour] || []
      assert PortfolioCore.Ports.GraphStore in behaviours
    end

    test "exports traverse/3" do
      assert Code.ensure_loaded?(Neo4j)
      assert function_exported?(Neo4j, :traverse, 3)
    end
  end

  # =============================================================================
  # Integration Tests (require running Neo4j)
  # Run with: mix test --include integration
  # =============================================================================

  describe "create_graph/2 integration" do
    @tag :integration
    test "creates a new graph namespace" do
      graph_id = "test_graph_#{System.unique_integer([:positive])}"

      assert :ok = Neo4j.create_graph(graph_id, %{})

      # Cleanup
      cleanup_graph(graph_id)
    end

    @tag :integration
    test "create_graph is idempotent" do
      graph_id = "test_graph_#{System.unique_integer([:positive])}"

      assert :ok = Neo4j.create_graph(graph_id, %{})
      assert :ok = Neo4j.create_graph(graph_id, %{})

      cleanup_graph(graph_id)
    end
  end

  describe "create_node/2 integration" do
    @tag :integration
    test "creates a node with labels and properties" do
      graph_id = setup_test_graph()

      {:ok, node} =
        Neo4j.create_node(graph_id, %{
          labels: ["Person", "Developer"],
          properties: %{name: "Alice", age: 30}
        })

      assert is_binary(node.id)
      assert "Person" in node.labels
      assert "Developer" in node.labels
      assert node.properties["name"] == "Alice"
      assert node.properties["age"] == 30

      cleanup_graph(graph_id)
    end

    @tag :integration
    test "creates node with empty properties" do
      graph_id = setup_test_graph()

      {:ok, node} =
        Neo4j.create_node(graph_id, %{
          labels: ["Empty"],
          properties: %{}
        })

      assert is_binary(node.id)
      assert "Empty" in node.labels

      cleanup_graph(graph_id)
    end
  end

  describe "get_node/2 integration" do
    @tag :integration
    test "retrieves an existing node" do
      graph_id = setup_test_graph()

      {:ok, created} =
        Neo4j.create_node(graph_id, %{
          labels: ["Test"],
          properties: %{key: "value"}
        })

      {:ok, fetched} = Neo4j.get_node(graph_id, created.id)

      assert fetched.id == created.id
      assert fetched.properties["key"] == "value"

      cleanup_graph(graph_id)
    end

    @tag :integration
    test "returns error for non-existent node" do
      graph_id = setup_test_graph()

      assert {:error, :not_found} = Neo4j.get_node(graph_id, "nonexistent_id")

      cleanup_graph(graph_id)
    end
  end

  describe "create_edge/2 integration" do
    @tag :integration
    test "creates an edge between nodes" do
      graph_id = setup_test_graph()

      {:ok, node1} = Neo4j.create_node(graph_id, %{labels: ["A"], properties: %{}})
      {:ok, node2} = Neo4j.create_node(graph_id, %{labels: ["B"], properties: %{}})

      {:ok, edge} =
        Neo4j.create_edge(graph_id, %{
          from_id: node1.id,
          to_id: node2.id,
          type: "CONNECTS_TO",
          properties: %{weight: 1.5}
        })

      assert is_binary(edge.id)
      assert edge.type == "CONNECTS_TO"
      assert edge.from_id == node1.id
      assert edge.to_id == node2.id
      assert edge.properties["weight"] == 1.5

      cleanup_graph(graph_id)
    end
  end

  describe "get_neighbors/3 integration" do
    @tag :integration
    test "retrieves outgoing neighbors" do
      graph_id = setup_test_graph()

      {:ok, center} =
        Neo4j.create_node(graph_id, %{labels: ["Center"], properties: %{name: "center"}})

      {:ok, out1} = Neo4j.create_node(graph_id, %{labels: ["Out"], properties: %{name: "out1"}})
      {:ok, out2} = Neo4j.create_node(graph_id, %{labels: ["Out"], properties: %{name: "out2"}})
      {:ok, in1} = Neo4j.create_node(graph_id, %{labels: ["In"], properties: %{name: "in1"}})

      Neo4j.create_edge(graph_id, %{
        from_id: center.id,
        to_id: out1.id,
        type: "KNOWS",
        properties: %{}
      })

      Neo4j.create_edge(graph_id, %{
        from_id: center.id,
        to_id: out2.id,
        type: "KNOWS",
        properties: %{}
      })

      Neo4j.create_edge(graph_id, %{
        from_id: in1.id,
        to_id: center.id,
        type: "KNOWS",
        properties: %{}
      })

      {:ok, neighbors} = Neo4j.get_neighbors(graph_id, center.id, direction: :outgoing)

      assert length(neighbors) == 2
      neighbor_names = Enum.map(neighbors, & &1.properties["name"])
      assert "out1" in neighbor_names
      assert "out2" in neighbor_names

      cleanup_graph(graph_id)
    end

    @tag :integration
    test "retrieves incoming neighbors" do
      graph_id = setup_test_graph()

      {:ok, center} =
        Neo4j.create_node(graph_id, %{labels: ["Center"], properties: %{name: "center"}})

      {:ok, in1} = Neo4j.create_node(graph_id, %{labels: ["In"], properties: %{name: "in1"}})

      Neo4j.create_edge(graph_id, %{
        from_id: in1.id,
        to_id: center.id,
        type: "KNOWS",
        properties: %{}
      })

      {:ok, neighbors} = Neo4j.get_neighbors(graph_id, center.id, direction: :incoming)

      assert length(neighbors) == 1
      assert hd(neighbors).properties["name"] == "in1"

      cleanup_graph(graph_id)
    end

    @tag :integration
    test "filters neighbors by relationship type" do
      graph_id = setup_test_graph()

      {:ok, center} = Neo4j.create_node(graph_id, %{labels: ["Center"], properties: %{}})

      {:ok, friend} =
        Neo4j.create_node(graph_id, %{labels: ["Person"], properties: %{name: "friend"}})

      {:ok, colleague} =
        Neo4j.create_node(graph_id, %{labels: ["Person"], properties: %{name: "colleague"}})

      Neo4j.create_edge(graph_id, %{
        from_id: center.id,
        to_id: friend.id,
        type: "FRIEND_OF",
        properties: %{}
      })

      Neo4j.create_edge(graph_id, %{
        from_id: center.id,
        to_id: colleague.id,
        type: "WORKS_WITH",
        properties: %{}
      })

      {:ok, friends} =
        Neo4j.get_neighbors(graph_id, center.id, direction: :outgoing, edge_types: ["FRIEND_OF"])

      assert length(friends) == 1
      assert hd(friends).properties["name"] == "friend"

      cleanup_graph(graph_id)
    end
  end

  describe "query/3 integration" do
    @tag :integration
    test "executes a Cypher query" do
      graph_id = setup_test_graph()

      Neo4j.create_node(graph_id, %{labels: ["Person"], properties: %{name: "Alice"}})
      Neo4j.create_node(graph_id, %{labels: ["Person"], properties: %{name: "Bob"}})

      cypher = """
      MATCH (p:Person {_graph_id: $graph_id})
      RETURN p.name AS name
      ORDER BY name
      """

      {:ok, result} = Neo4j.query(graph_id, cypher, %{})

      assert length(result.records) == 2
      names = Enum.map(result.records, & &1["name"])
      assert names == ["Alice", "Bob"]

      cleanup_graph(graph_id)
    end
  end

  describe "delete_node/2 integration" do
    @tag :integration
    test "deletes a node" do
      graph_id = setup_test_graph()

      {:ok, node} = Neo4j.create_node(graph_id, %{labels: ["ToDelete"], properties: %{}})
      assert {:ok, _} = Neo4j.get_node(graph_id, node.id)

      assert :ok = Neo4j.delete_node(graph_id, node.id)
      assert {:error, :not_found} = Neo4j.get_node(graph_id, node.id)

      cleanup_graph(graph_id)
    end
  end

  describe "graph_stats/1 integration" do
    @tag :integration
    test "returns graph statistics" do
      graph_id = setup_test_graph()

      # Create some nodes and edges
      {:ok, n1} = Neo4j.create_node(graph_id, %{labels: ["A"], properties: %{}})
      {:ok, n2} = Neo4j.create_node(graph_id, %{labels: ["B"], properties: %{}})
      {:ok, n3} = Neo4j.create_node(graph_id, %{labels: ["A"], properties: %{}})
      Neo4j.create_edge(graph_id, %{from_id: n1.id, to_id: n2.id, type: "REL", properties: %{}})
      Neo4j.create_edge(graph_id, %{from_id: n2.id, to_id: n3.id, type: "REL", properties: %{}})

      {:ok, stats} = Neo4j.graph_stats(graph_id)

      assert stats.node_count == 3
      assert stats.edge_count == 2
      assert stats.graph_id == graph_id

      cleanup_graph(graph_id)
    end
  end

  describe "delete_graph/1 integration" do
    @tag :integration
    test "deletes all nodes in a graph" do
      graph_id = setup_test_graph()

      Neo4j.create_node(graph_id, %{labels: ["A"], properties: %{}})
      Neo4j.create_node(graph_id, %{labels: ["B"], properties: %{}})

      {:ok, stats_before} = Neo4j.graph_stats(graph_id)
      assert stats_before.node_count == 2

      assert :ok = Neo4j.delete_graph(graph_id)

      {:ok, stats_after} = Neo4j.graph_stats(graph_id)
      assert stats_after.node_count == 0
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp setup_test_graph do
    graph_id = "test_#{System.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
    :ok = Neo4j.create_graph(graph_id, %{})
    graph_id
  end

  defp cleanup_graph(graph_id) do
    Neo4j.delete_graph(graph_id)
  end
end
