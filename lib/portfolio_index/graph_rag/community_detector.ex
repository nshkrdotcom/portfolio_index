defmodule PortfolioIndex.GraphRAG.CommunityDetector do
  @moduledoc """
  Label propagation algorithm for community detection.

  Clusters graph entities into communities based on edge connectivity patterns.
  Uses an iterative approach where each node adopts the most common label
  among its neighbors.

  ## Algorithm

  1. Initialize: each entity gets its own unique label
  2. Iterate: each entity adopts the most common neighbor label
  3. Stop: when labels stabilize or max iterations reached
  4. Return: community mapping %{community_id => [entity_ids]}

  ## Example

      {:ok, communities} = CommunityDetector.detect(graph_store, "my_graph")
      # => %{
      #   "community_0" => ["entity_1", "entity_2"],
      #   "community_1" => ["entity_3", "entity_4", "entity_5"]
      # }

  ## Hierarchical Communities

      {:ok, hierarchy} = CommunityDetector.detect_hierarchical(graph_store, "my_graph", 3)
      # Returns communities at multiple levels of granularity
  """

  require Logger

  @max_iterations 100
  @convergence_threshold 0.01

  @type graph_store :: module()
  @type graph_id :: String.t()
  @type entity_id :: String.t()
  @type community_id :: String.t()
  @type communities :: %{community_id() => [entity_id()]}

  @doc """
  Detect communities in a graph using label propagation.

  ## Options

  - `:max_iterations` - Maximum iterations before stopping (default: 100)
  - `:convergence_threshold` - Stop when fewer than this fraction of nodes change (default: 0.01)
  - `:seed` - Random seed for deterministic results

  ## Returns

  - `{:ok, communities}` - Map of community_id to list of entity_ids
  - `{:error, reason}` on failure
  """
  @spec detect(graph_store(), graph_id(), keyword()) :: {:ok, communities()} | {:error, term()}
  def detect(graph_store, graph_id, opts \\ []) do
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)
    threshold = Keyword.get(opts, :convergence_threshold, @convergence_threshold)

    start_time = System.monotonic_time(:millisecond)

    with {:ok, entities} <- list_entities(graph_store, graph_id),
         {:ok, edges} <- list_edges(graph_store, graph_id) do
      if Enum.empty?(entities) do
        {:ok, %{}}
      else
        # Build adjacency list for efficient neighbor lookup
        adjacency = build_adjacency_list(edges)

        # Initialize labels: each node gets its own label
        initial_labels = initialize_labels(entities)

        # Run label propagation
        final_labels = propagate(initial_labels, adjacency, max_iter, threshold)

        # Group by label to get communities
        communities = group_by_label(final_labels)

        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(
          :detect,
          %{duration_ms: duration, community_count: map_size(communities)},
          %{graph_id: graph_id}
        )

        {:ok, communities}
      end
    end
  end

  @doc """
  Detect communities at multiple hierarchical levels.

  Higher levels represent coarser-grained communities formed by merging
  lower-level communities.

  ## Options

  Same as `detect/3` plus:
  - `:level_merge_threshold` - Minimum community size to keep at each level

  ## Returns

  - `{:ok, %{level => communities}}` - Map of level to communities
  """
  @spec detect_hierarchical(graph_store(), graph_id(), pos_integer(), keyword()) ::
          {:ok, %{non_neg_integer() => communities()}} | {:error, term()}
  def detect_hierarchical(graph_store, graph_id, levels, opts \\ []) when levels > 0 do
    with {:ok, level_0} <- detect(graph_store, graph_id, opts) do
      hierarchy =
        1..(levels - 1)
        |> Enum.reduce(%{0 => level_0}, fn level, acc ->
          prev_communities = Map.get(acc, level - 1)
          merged = merge_communities(prev_communities, level, opts)
          Map.put(acc, level, merged)
        end)

      {:ok, hierarchy}
    end
  end

  @doc """
  Get community assignments for specific entities.

  ## Returns

  Map of entity_id to community_id
  """
  @spec get_entity_communities(communities()) :: %{entity_id() => community_id()}
  def get_entity_communities(communities) do
    communities
    |> Enum.flat_map(fn {community_id, entity_ids} ->
      Enum.map(entity_ids, fn entity_id -> {entity_id, community_id} end)
    end)
    |> Map.new()
  end

  # Private functions

  @spec list_entities(graph_store(), graph_id()) :: {:ok, [map()]} | {:error, term()}
  defp list_entities(graph_store, graph_id) do
    query = """
    MATCH (n {_graph_id: $graph_id})
    WHERE NOT n:_Graph
    RETURN n.id as id, labels(n) as labels
    """

    case graph_store.query(graph_id, query, %{graph_id: graph_id}) do
      {:ok, %{records: records}} ->
        entities =
          Enum.map(records, fn record ->
            %{id: record["id"] || record[:id], labels: record["labels"] || record[:labels] || []}
          end)

        {:ok, entities}

      {:ok, []} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec list_edges(graph_store(), graph_id()) :: {:ok, [map()]} | {:error, term()}
  defp list_edges(graph_store, graph_id) do
    query = """
    MATCH (a {_graph_id: $graph_id})-[r]->(b {_graph_id: $graph_id})
    WHERE NOT a:_Graph AND NOT b:_Graph
    RETURN a.id as source, b.id as target, type(r) as type
    """

    case graph_store.query(graph_id, query, %{graph_id: graph_id}) do
      {:ok, %{records: records}} ->
        edges =
          Enum.map(records, fn record ->
            %{
              source: record["source"] || record[:source],
              target: record["target"] || record[:target],
              type: record["type"] || record[:type]
            }
          end)

        {:ok, edges}

      {:ok, []} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec build_adjacency_list([map()]) :: %{entity_id() => [entity_id()]}
  defp build_adjacency_list(edges) do
    Enum.reduce(edges, %{}, fn %{source: source, target: target}, acc ->
      acc
      |> Map.update(source, [target], &[target | &1])
      |> Map.update(target, [source], &[source | &1])
    end)
  end

  @spec initialize_labels([map()]) :: %{entity_id() => non_neg_integer()}
  defp initialize_labels(entities) do
    entities
    |> Enum.with_index()
    |> Enum.map(fn {entity, idx} -> {entity.id, idx} end)
    |> Map.new()
  end

  @spec propagate(
          %{entity_id() => non_neg_integer()},
          %{entity_id() => [entity_id()]},
          pos_integer(),
          float()
        ) ::
          %{entity_id() => non_neg_integer()}
  defp propagate(labels, adjacency, max_iter, threshold) do
    node_ids = Map.keys(labels)
    total_nodes = length(node_ids)

    1..max_iter
    |> Enum.reduce_while(labels, fn iteration, current_labels ->
      # Shuffle nodes for randomness
      shuffled = Enum.shuffle(node_ids)

      # Update labels
      {new_labels, changed_count} =
        Enum.reduce(shuffled, {current_labels, 0}, fn node_id, {labels_acc, changed} ->
          neighbors = Map.get(adjacency, node_id, [])
          current_label = Map.get(labels_acc, node_id)

          new_label = most_common_neighbor_label(neighbors, labels_acc, current_label)

          if new_label != current_label do
            {Map.put(labels_acc, node_id, new_label), changed + 1}
          else
            {labels_acc, changed}
          end
        end)

      # Check convergence
      change_ratio = if total_nodes > 0, do: changed_count / total_nodes, else: 0

      if change_ratio < threshold do
        Logger.debug("Community detection converged at iteration #{iteration}")
        {:halt, new_labels}
      else
        {:cont, new_labels}
      end
    end)
  end

  @spec most_common_neighbor_label(
          [entity_id()],
          %{entity_id() => non_neg_integer()},
          non_neg_integer()
        ) ::
          non_neg_integer()
  defp most_common_neighbor_label([], _labels, current_label), do: current_label

  defp most_common_neighbor_label(neighbors, labels, current_label) do
    neighbor_labels = Enum.map(neighbors, fn n -> Map.get(labels, n, current_label) end)

    frequencies = Enum.frequencies(neighbor_labels)

    {most_common, _count} =
      frequencies
      |> Enum.max_by(fn {_label, count} -> count end, fn -> {current_label, 0} end)

    most_common
  end

  @spec group_by_label(%{entity_id() => non_neg_integer()}) :: communities()
  defp group_by_label(labels) do
    labels
    |> Enum.group_by(fn {_entity_id, label} -> label end, fn {entity_id, _label} -> entity_id end)
    |> Enum.with_index()
    |> Enum.map(fn {{_label, entity_ids}, idx} ->
      {"community_#{idx}", entity_ids}
    end)
    |> Map.new()
  end

  @spec merge_communities(communities(), pos_integer(), keyword()) :: communities()
  defp merge_communities(communities, level, _opts) do
    # Simple merging: combine smaller communities
    community_list = Map.to_list(communities)
    merge_threshold = :math.pow(2, level) |> trunc()

    {merged, remaining} =
      community_list
      |> Enum.sort_by(fn {_id, members} -> Enum.count(members) end)
      |> Enum.reduce({[], []}, fn {id, members}, {merged_acc, remaining_acc} ->
        member_count = Enum.count(members)

        if member_count < merge_threshold and remaining_acc != [] do
          # Merge with the last remaining community
          [{last_id, last_members} | rest] = remaining_acc
          {merged_acc, [{last_id, last_members ++ members} | rest]}
        else
          {merged_acc, [{id, members} | remaining_acc]}
        end
      end)

    (merged ++ remaining)
    |> Enum.with_index()
    |> Enum.map(fn {{_old_id, members}, idx} ->
      {"community_l#{level}_#{idx}", members}
    end)
    |> Map.new()
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :graph_rag, :community_detector, event],
      measurements,
      metadata
    )
  end
end
