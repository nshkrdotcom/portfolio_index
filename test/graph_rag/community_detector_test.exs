# Mock graph store for testing
defmodule PortfolioIndex.Test.MockGraphStore do
  def query(_graph_id, query, _params) do
    cond do
      String.contains?(query, "RETURN n.id") ->
        {:ok,
         %{
           records: [
             %{"id" => "entity_1", "labels" => ["Entity"]},
             %{"id" => "entity_2", "labels" => ["Entity"]},
             %{"id" => "entity_3", "labels" => ["Entity"]},
             %{"id" => "entity_4", "labels" => ["Entity"]}
           ]
         }}

      String.contains?(query, "RETURN a.id as source") ->
        {:ok,
         %{
           records: [
             %{"source" => "entity_1", "target" => "entity_2", "type" => "RELATED"},
             %{"source" => "entity_2", "target" => "entity_1", "type" => "RELATED"},
             %{"source" => "entity_3", "target" => "entity_4", "type" => "RELATED"},
             %{"source" => "entity_4", "target" => "entity_3", "type" => "RELATED"}
           ]
         }}

      true ->
        {:ok, %{records: []}}
    end
  end
end

defmodule PortfolioIndex.Test.EmptyGraphStore do
  def query(_graph_id, _query, _params) do
    {:ok, %{records: []}}
  end
end

defmodule PortfolioIndex.GraphRAG.CommunityDetectorTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.GraphRAG.CommunityDetector
  alias PortfolioIndex.Test.EmptyGraphStore
  alias PortfolioIndex.Test.MockGraphStore

  describe "detect/3" do
    test "detects communities from connected graph" do
      {:ok, communities} = CommunityDetector.detect(MockGraphStore, "test_graph", [])

      # Should detect at least one community
      assert map_size(communities) >= 1
      # All entities should be in some community
      all_entities = communities |> Map.values() |> List.flatten()
      assert "entity_1" in all_entities
    end

    test "returns empty map for empty graph" do
      {:ok, communities} = CommunityDetector.detect(EmptyGraphStore, "empty", [])
      assert communities == %{}
    end

    test "respects max_iterations option" do
      {:ok, communities} =
        CommunityDetector.detect(MockGraphStore, "test_graph", max_iterations: 5)

      assert map_size(communities) >= 1
    end

    test "converges with convergence_threshold" do
      {:ok, communities} =
        CommunityDetector.detect(MockGraphStore, "test_graph", convergence_threshold: 0.5)

      assert map_size(communities) >= 1
    end
  end

  describe "detect_hierarchical/4" do
    test "returns multiple levels of communities" do
      {:ok, hierarchy} =
        CommunityDetector.detect_hierarchical(MockGraphStore, "test_graph", 3, [])

      assert Map.has_key?(hierarchy, 0)
      assert Map.has_key?(hierarchy, 1)
      assert Map.has_key?(hierarchy, 2)
    end

    test "higher levels have fewer or equal communities" do
      {:ok, hierarchy} =
        CommunityDetector.detect_hierarchical(MockGraphStore, "test_graph", 2, [])

      level_0_count = map_size(hierarchy[0])
      level_1_count = map_size(hierarchy[1])

      # Higher levels should have fewer or equal communities due to merging
      assert level_1_count <= level_0_count
    end
  end

  describe "get_entity_communities/1" do
    test "returns entity to community mapping" do
      communities = %{
        "community_0" => ["entity_1", "entity_2"],
        "community_1" => ["entity_3"]
      }

      mapping = CommunityDetector.get_entity_communities(communities)

      assert mapping["entity_1"] == "community_0"
      assert mapping["entity_2"] == "community_0"
      assert mapping["entity_3"] == "community_1"
    end
  end
end
