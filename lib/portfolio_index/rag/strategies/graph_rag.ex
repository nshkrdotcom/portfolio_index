defmodule PortfolioIndex.RAG.Strategies.GraphRAG do
  @moduledoc """
  Graph-aware RAG strategy.

  Combines vector similarity search with knowledge graph traversal:
  1. Extract entities from query
  2. Find matching nodes in graph
  3. Traverse to related entities
  4. Aggregate context from graph
  5. Combine with vector search results
  6. Return unified results
  """

  @behaviour PortfolioIndex.RAG.Strategy

  @dialyzer [{:nowarn_function, retrieve: 3}]

  alias PortfolioIndex.Adapters.Embedder.Gemini, as: DefaultEmbedder
  alias PortfolioIndex.Adapters.GraphStore.Neo4j, as: DefaultGraphStore
  alias PortfolioIndex.Adapters.LLM.Gemini, as: DefaultLLM
  alias PortfolioIndex.Adapters.VectorStore.Pgvector, as: DefaultVectorStore
  alias PortfolioIndex.RAG.AdapterResolver

  require Logger

  @default_depth 2
  @default_k 5
  @default_graph_id "default"

  @impl true
  def name, do: :graph_rag

  @impl true
  def required_adapters, do: [:vector_store, :embedder, :graph_store, :llm]

  @impl true
  def retrieve(query, context, opts) do
    start_time = System.monotonic_time(:millisecond)
    depth = Keyword.get(opts, :depth, @default_depth)
    k = Keyword.get(opts, :k, @default_k)
    graph_id = Keyword.get(opts, :graph_id, context[:graph_id] || @default_graph_id)
    index_id = context[:index_id] || "default"
    filter = context[:filters]

    {embedder, embedder_opts} = AdapterResolver.resolve(context, :embedder, DefaultEmbedder)

    {vector_store, vector_opts} =
      AdapterResolver.resolve(context, :vector_store, DefaultVectorStore)

    {graph_store, _graph_opts} = AdapterResolver.resolve(context, :graph_store, DefaultGraphStore)
    {llm, llm_opts} = AdapterResolver.resolve(context, :llm, DefaultLLM)

    {entities, entity_tokens} =
      case extract_entities(query, llm, llm_opts) do
        {:ok, extracted, tokens} ->
          {extracted, tokens}

        {:error, reason} ->
          Logger.warning("Entity extraction failed: #{inspect(reason)}")
          {[], 0}
      end

    graph_results = traverse_graph(entities, graph_id, depth, graph_store)

    case vector_search(
           query,
           index_id,
           k,
           filter,
           embedder,
           embedder_opts,
           vector_store,
           vector_opts
         ) do
      {:ok, vector_results, embed_tokens} ->
        combined = combine_results(graph_results, vector_results, opts)
        duration = System.monotonic_time(:millisecond) - start_time
        tokens_used = entity_tokens + embed_tokens

        emit_telemetry(
          :retrieve,
          %{
            duration_ms: duration,
            graph_count: length(graph_results),
            vector_count: length(vector_results),
            tokens_used: tokens_used
          },
          %{index_id: index_id}
        )

        {:ok,
         %{
           items: combined,
           query: query,
           answer: nil,
           strategy: :graph_rag,
           timing_ms: duration,
           tokens_used: tokens_used
         }}

      {:error, reason} ->
        Logger.error("GraphRAG retrieval failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_entities(query, llm, llm_opts) do
    prompt = """
    Extract key entities (functions, modules, classes, concepts) from this query.
    Return as JSON: {"entities": ["entity1", "entity2"]}

    Query: #{query}
    """

    case llm.complete([%{role: :user, content: prompt}], llm_opts) do
      {:ok, %{content: content} = response} ->
        {:ok, entities} = parse_entities(content)
        {:ok, entities, usage_tokens(response[:usage] || %{})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_entities(content) do
    case Regex.run(~r/\{[^}]+\}/, content) do
      [json] ->
        case Jason.decode(json) do
          {:ok, %{"entities" => entities}} when is_list(entities) ->
            {:ok, entities}

          _ ->
            {:ok, []}
        end

      _ ->
        {:ok, []}
    end
  end

  defp traverse_graph([], _graph_id, _depth, _graph_store), do: []

  defp traverse_graph(entities, graph_id, depth, graph_store) do
    entities
    |> Enum.flat_map(fn entity ->
      case find_node(entity, graph_id, graph_store) do
        {:ok, node} ->
          [node | get_neighbors(node, graph_id, depth, graph_store)]

        _ ->
          []
      end
    end)
    |> Enum.reject(&is_nil(&1.id))
    |> Enum.uniq_by(& &1.id)
  end

  defp find_node(entity, graph_id, graph_store) do
    query = """
    MATCH (n)
    WHERE n._graph_id = $graph_id
      AND (toLower(n.name) CONTAINS toLower($entity)
           OR toLower(n.label) CONTAINS toLower($entity))
    RETURN n, labels(n) as labels
    LIMIT 1
    """

    case graph_store.query(graph_id, query, %{entity: entity, graph_id: graph_id}) do
      {:ok, %{nodes: [node | _]}} ->
        {:ok, normalize_node(node)}

      {:ok, %{records: [record | _]}} ->
        normalize_record_node(record)

      {:ok, [node | _]} when is_map(node) ->
        {:ok, normalize_node(node)}

      {:ok, _} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  defp normalize_record_node(%{"n" => node, "labels" => labels}) do
    {:ok, normalize_node(node, labels)}
  end

  defp normalize_record_node(%{n: node, labels: labels}) do
    {:ok, normalize_node(node, labels)}
  end

  defp normalize_record_node(%{"n" => node}) do
    {:ok, normalize_node(node)}
  end

  defp normalize_record_node(%{n: node}) do
    {:ok, normalize_node(node)}
  end

  defp normalize_record_node(_), do: {:error, :not_found}

  defp normalize_node(%{id: id, labels: labels, properties: properties}) do
    %{
      id: id,
      labels: labels || [],
      properties: properties || %{}
    }
  end

  defp normalize_node(%{"id" => id, "labels" => labels, "properties" => properties}) do
    %{
      id: id,
      labels: labels || [],
      properties: properties || %{}
    }
  end

  defp normalize_node(%Boltx.Types.Node{properties: props, labels: labels}) do
    %{
      id: props["id"] || props[:id],
      labels: labels -- ["_Graph"],
      properties: Map.drop(props, ["id", "_graph_id", :id, :_graph_id])
    }
  end

  defp normalize_node(node_props) when is_map(node_props) do
    %{
      id: Map.get(node_props, "id") || Map.get(node_props, :id),
      labels: Map.get(node_props, :labels) || Map.get(node_props, "labels") || [],
      properties:
        node_props
        |> Map.drop(["id", "_graph_id", :id, :_graph_id, :labels, "labels"])
    }
  end

  defp normalize_node(%Boltx.Types.Node{properties: props, labels: node_labels}, labels) do
    %{
      id: props["id"] || props[:id],
      labels: (labels || node_labels || []) -- ["_Graph"],
      properties: Map.drop(props, ["id", "_graph_id", :id, :_graph_id])
    }
  end

  defp normalize_node(node_props, labels) when is_map(node_props) do
    %{
      id: Map.get(node_props, "id") || Map.get(node_props, :id),
      labels: labels || [],
      properties: Map.drop(node_props, ["id", "_graph_id", :id, :_graph_id])
    }
  end

  defp get_neighbors(%{id: nil}, _graph_id, _depth, _graph_store), do: []

  defp get_neighbors(node, graph_id, depth, graph_store) do
    case graph_store.get_neighbors(graph_id, node.id, depth: depth) do
      {:ok, neighbors} -> neighbors
      _ -> []
    end
  end

  defp vector_search(
         query,
         index_id,
         k,
         filter,
         embedder,
         embedder_opts,
         vector_store,
         vector_opts
       ) do
    with {:ok, embed_result} <- embedder.embed(query, embedder_opts),
         embedding when is_list(embedding) <-
           embed_result.vector || embed_result[:vector],
         {:ok, results} <-
           vector_store.search(index_id, embedding, k, build_vector_opts(vector_opts, filter)) do
      tokens = embed_result.token_count || embed_result[:token_count] || 0
      {:ok, results, tokens}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_embedding}
    end
  end

  defp build_vector_opts(vector_opts, nil), do: vector_opts
  defp build_vector_opts(vector_opts, filter), do: Keyword.put(vector_opts, :filter, filter)

  defp combine_results(graph_results, vector_results, opts) do
    graph_weight = Keyword.get(opts, :graph_weight, 0.4)
    vector_weight = Keyword.get(opts, :vector_weight, 0.6)

    graph_docs =
      Enum.map(graph_results, fn node ->
        %{
          id: "graph:#{node.id}",
          content: format_node_content(node),
          score: graph_weight,
          source: :graph,
          metadata: %{
            labels: node.labels,
            properties: node.properties
          }
        }
      end)

    vector_docs =
      Enum.map(vector_results, fn result ->
        %{
          id: result.id || result[:id],
          content: extract_content(result),
          score: (result.score || result[:score] || 0) * vector_weight,
          source: :vector,
          metadata: result.metadata || result[:metadata] || %{}
        }
      end)

    (graph_docs ++ vector_docs)
    |> deduplicate_results()
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp format_node_content(node) do
    name = node.properties[:name] || node.properties["name"] || node.id
    labels = Enum.join(node.labels || [], ", ")

    props =
      node.properties
      |> Map.drop([:name, "name", :_graph_id, "_graph_id"])
      |> Enum.map_join("\n", fn {k, v} -> "  #{k}: #{inspect(v)}" end)

    """
    [#{labels}] #{name}
    #{props}
    """
  end

  defp extract_content(result) do
    metadata = result.metadata || result[:metadata] || %{}

    result[:content] ||
      metadata[:content] ||
      metadata["content"] ||
      metadata[:text] ||
      metadata["text"] ||
      ""
  end

  defp deduplicate_results(results) do
    results
    |> Enum.reduce(%{}, fn result, acc ->
      key = result.id

      case Map.get(acc, key) do
        nil -> Map.put(acc, key, result)
        existing when existing.score < result.score -> Map.put(acc, key, result)
        _ -> acc
      end
    end)
    |> Map.values()
  end

  defp usage_tokens(usage) do
    (usage[:input_tokens] || usage["input_tokens"] || 0) +
      (usage[:output_tokens] || usage["output_tokens"] || 0)
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :rag, :graph_rag, event],
      measurements,
      metadata
    )
  end
end
