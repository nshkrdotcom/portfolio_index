# Portfolio Index Implementation Prompt

## Overview

You are implementing `portfolio_index`, the production-ready adapter and pipeline layer for the PortfolioCore hexagonal architecture. This package provides concrete implementations of all ports, Broadway-based ingestion pipelines, advanced RAG strategies, and multi-graph federation.

---

## Required Reading

Before implementation, read these files in order:

### Architecture Documentation
```
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/00_executive_summary.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/01_beam_otp_architecture.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/02_hexagonal_core_design.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/03_multigraph_architecture.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/04_vector_embedding_systems.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/05_pipeline_orchestration.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/06_advanced_rag_patterns.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/07_data_modeling_schemas.md
/home/home/p/g/n/portfolio_manager/docs/20251226/expert_architecture_review/08_security_observability.md
```

### Original Design Context
```
/home/home/p/g/n/portfolio_manager/docs/20251226/ecosystem design docs/00_overview.md
/home/home/p/g/n/portfolio_manager/docs/20251226/ecosystem design docs/05_storage_graph_vector.md
/home/home/p/g/n/portfolio_manager/docs/20251226/ecosystem design docs/06_pipeline_and_ops.md
```

### Portfolio Core Port Specifications
```
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/vector_store.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/graph_store.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/document_store.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/embedder.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/llm.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/chunker.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/retriever.ex
/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/reranker.ex
```

---

## Package Scope

### What portfolio_index IS:
- Concrete adapter implementations for all PortfolioCore ports
- Broadway-based ingestion pipelines with backpressure
- Advanced RAG strategies (Self-RAG, CRAG, GraphRAG, Agentic)
- Multi-graph federation layer
- Rate limiting and cost tracking
- Observability integration (OpenTelemetry)

### What portfolio_index IS NOT:
- No port definitions (those are in portfolio_core)
- No CLI interface (that's in portfolio_manager)
- No web API (that's in portfolio_manager)

---

## Implementation Tasks

### 1. Project Setup

```bash
cd /home/home/p/g/n/portfolio_index
mix new . --module PortfolioIndex --app portfolio_index
```

Create `mix.exs`:

```elixir
defmodule PortfolioIndex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/portfolio_index"

  def project do
    [
      app: :portfolio_index,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :unknown, :unmatched_returns]
      ],
      preferred_cli_env: [
        "test.watch": :test,
        coveralls: :test,
        "coveralls.html": :test
      ],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PortfolioIndex.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependency
      {:portfolio_core, path: "../portfolio_core"},

      # Database adapters
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},
      {:pgvector, "~> 0.2"},

      # Graph database
      {:bolt_sips, "~> 2.0"},  # Neo4j driver

      # HTTP clients for APIs
      {:req, "~> 0.4"},
      {:finch, "~> 0.18"},

      # Pipeline processing
      {:broadway, "~> 1.0"},
      {:gen_stage, "~> 1.2"},

      # Rate limiting
      {:hammer, "~> 6.1"},

      # Telemetry
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_api, "~> 1.2"},
      {:opentelemetry_exporter, "~> 1.6"},

      # JSON
      {:jason, "~> 1.4"},

      # Dev/test only
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp aliases do
    [
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.all": ["quality", "test"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
```

### 2. Vector Store Adapters

#### 2.1 Pgvector Adapter
`lib/portfolio_index/adapters/vector_store/pgvector.ex`

```elixir
defmodule PortfolioIndex.Adapters.VectorStore.Pgvector do
  @moduledoc """
  PostgreSQL pgvector adapter for vector storage.

  Requires pgvector extension and proper schema setup.
  Supports IVFFlat and HNSW indexes.
  """

  @behaviour PortfolioCore.Ports.VectorStore

  alias PortfolioIndex.Repo
  import Ecto.Query

  defstruct [:repo, :table_prefix, :default_index_type]

  @impl true
  def create_index(index_id, config) do
    table_name = table_name(index_id)
    dimensions = config.dimensions
    metric = config.metric || :cosine

    # Create table with vector column
    sql = """
    CREATE TABLE IF NOT EXISTS #{table_name} (
      id VARCHAR(255) PRIMARY KEY,
      embedding vector(#{dimensions}),
      metadata JSONB DEFAULT '{}',
      created_at TIMESTAMP DEFAULT NOW()
    )
    """

    case Repo.query(sql) do
      {:ok, _} -> create_vector_index(table_name, metric, config)
      {:error, _} = err -> err
    end
  end

  @impl true
  def delete_index(index_id) do
    table_name = table_name(index_id)
    sql = "DROP TABLE IF EXISTS #{table_name}"

    case Repo.query(sql) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def store(index_id, id, vector, metadata) do
    table_name = table_name(index_id)
    vector_string = "[" <> Enum.join(vector, ",") <> "]"

    sql = """
    INSERT INTO #{table_name} (id, embedding, metadata)
    VALUES ($1, $2::vector, $3)
    ON CONFLICT (id) DO UPDATE SET
      embedding = EXCLUDED.embedding,
      metadata = EXCLUDED.metadata
    """

    case Repo.query(sql, [id, vector_string, metadata]) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def store_batch(index_id, items) do
    results = Enum.map(items, fn {id, vector, metadata} ->
      store(index_id, id, vector, metadata)
    end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      {:ok, length(items)}
    else
      {:error, {:partial_failure, length(items) - length(errors), errors}}
    end
  end

  @impl true
  def search(index_id, query_vector, k, opts) do
    table_name = table_name(index_id)
    vector_string = "[" <> Enum.join(query_vector, ",") <> "]"
    include_vector = Keyword.get(opts, :include_vector, false)
    filter = Keyword.get(opts, :filter, nil)

    base_sql = """
    SELECT id, metadata, 1 - (embedding <=> $1::vector) as score
    #{if include_vector, do: ", embedding", else: ""}
    FROM #{table_name}
    """

    {where_clause, params} = build_filter(filter, 2)
    sql = base_sql <> where_clause <> " ORDER BY embedding <=> $1::vector LIMIT $#{length(params) + 2}"

    case Repo.query(sql, [vector_string] ++ params ++ [k]) do
      {:ok, %{rows: rows, columns: columns}} ->
        results = Enum.map(rows, fn row ->
          parse_row(row, columns, include_vector)
        end)
        {:ok, results}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def delete(index_id, id) do
    table_name = table_name(index_id)
    sql = "DELETE FROM #{table_name} WHERE id = $1"

    case Repo.query(sql, [id]) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, %{num_rows: 0}} -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  @impl true
  def index_stats(index_id) do
    table_name = table_name(index_id)

    sql = """
    SELECT
      COUNT(*) as count,
      pg_total_relation_size('#{table_name}') as size_bytes
    FROM #{table_name}
    """

    case Repo.query(sql) do
      {:ok, %{rows: [[count, size]]}} ->
        {:ok, %{
          count: count,
          dimensions: get_dimensions(table_name),
          metric: get_metric(table_name),
          size_bytes: size
        }}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  @impl true
  def index_exists?(index_id) do
    table_name = table_name(index_id)

    sql = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_name = $1
    )
    """

    case Repo.query(sql, [table_name]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  end

  # Private functions

  defp table_name(index_id) do
    "vectors_#{String.replace(index_id, "-", "_")}"
  end

  defp create_vector_index(table_name, metric, config) do
    index_type = config[:index_type] || :ivfflat
    op_class = metric_to_op_class(metric)

    sql = case index_type do
      :ivfflat ->
        lists = config[:lists] || 100
        """
        CREATE INDEX IF NOT EXISTS #{table_name}_embedding_idx
        ON #{table_name}
        USING ivfflat (embedding #{op_class})
        WITH (lists = #{lists})
        """

      :hnsw ->
        m = config[:m] || 16
        ef_construction = config[:ef_construction] || 64
        """
        CREATE INDEX IF NOT EXISTS #{table_name}_embedding_idx
        ON #{table_name}
        USING hnsw (embedding #{op_class})
        WITH (m = #{m}, ef_construction = #{ef_construction})
        """
    end

    case Repo.query(sql) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  defp metric_to_op_class(:cosine), do: "vector_cosine_ops"
  defp metric_to_op_class(:euclidean), do: "vector_l2_ops"
  defp metric_to_op_class(:dot_product), do: "vector_ip_ops"

  defp build_filter(nil, _), do: {"", []}
  defp build_filter(filter, start_param) when is_map(filter) do
    {clauses, params, _} = Enum.reduce(filter, {[], [], start_param}, fn {key, value}, {clauses, params, idx} ->
      clause = "metadata->>$#{idx} = $#{idx + 1}"
      {[clause | clauses], params ++ [to_string(key), to_string(value)], idx + 2}
    end)

    where = if Enum.empty?(clauses), do: "", else: " WHERE " <> Enum.join(clauses, " AND ")
    {where, params}
  end

  defp parse_row(row, columns, include_vector) do
    map = Enum.zip(columns, row) |> Map.new()

    %{
      id: map["id"],
      score: map["score"],
      metadata: map["metadata"] || %{},
      vector: if(include_vector, do: parse_vector(map["embedding"]), else: nil)
    }
  end

  defp parse_vector(nil), do: nil
  defp parse_vector(pgvector) when is_struct(pgvector), do: Pgvector.to_list(pgvector)
  defp parse_vector(str) when is_binary(str) do
    str
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&String.to_float/1)
  end

  defp get_dimensions(_table_name), do: 1536  # Would query column definition
  defp get_metric(_table_name), do: :cosine   # Would query index definition
end
```

#### 2.2 Qdrant Adapter
`lib/portfolio_index/adapters/vector_store/qdrant.ex`

```elixir
defmodule PortfolioIndex.Adapters.VectorStore.Qdrant do
  @moduledoc """
  Qdrant vector database adapter.
  """

  @behaviour PortfolioCore.Ports.VectorStore

  defstruct [:base_url, :api_key, :timeout]

  def new(opts) do
    %__MODULE__{
      base_url: Keyword.fetch!(opts, :base_url),
      api_key: Keyword.get(opts, :api_key),
      timeout: Keyword.get(opts, :timeout, 30_000)
    }
  end

  @impl true
  def create_index(index_id, config) do
    body = %{
      vectors: %{
        size: config.dimensions,
        distance: distance_name(config.metric || :cosine)
      }
    }

    case request(:put, "/collections/#{index_id}", body) do
      {:ok, %{status: status}} when status in [200, 201] -> :ok
      {:ok, %{status: 409}} -> :ok  # Already exists
      {:error, _} = err -> err
    end
  end

  @impl true
  def delete_index(index_id) do
    case request(:delete, "/collections/#{index_id}") do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  @impl true
  def store(index_id, id, vector, metadata) do
    body = %{
      points: [
        %{id: id, vector: vector, payload: metadata}
      ]
    }

    case request(:put, "/collections/#{index_id}/points", body) do
      {:ok, %{status: 200}} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def store_batch(index_id, items) do
    points = Enum.map(items, fn {id, vector, metadata} ->
      %{id: id, vector: vector, payload: metadata}
    end)

    body = %{points: points}

    case request(:put, "/collections/#{index_id}/points", body) do
      {:ok, %{status: 200}} -> {:ok, length(items)}
      {:error, _} = err -> err
    end
  end

  @impl true
  def search(index_id, query_vector, k, opts) do
    body = %{
      vector: query_vector,
      limit: k,
      with_payload: true,
      with_vector: Keyword.get(opts, :include_vector, false)
    }

    body = if filter = Keyword.get(opts, :filter) do
      Map.put(body, :filter, build_qdrant_filter(filter))
    else
      body
    end

    case request(:post, "/collections/#{index_id}/points/search", body) do
      {:ok, %{status: 200, body: %{"result" => results}}} ->
        parsed = Enum.map(results, fn r ->
          %{
            id: r["id"],
            score: r["score"],
            metadata: r["payload"] || %{},
            vector: r["vector"]
          }
        end)
        {:ok, parsed}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def delete(index_id, id) do
    body = %{points: [id]}

    case request(:post, "/collections/#{index_id}/points/delete", body) do
      {:ok, %{status: 200}} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def index_stats(index_id) do
    case request(:get, "/collections/#{index_id}") do
      {:ok, %{status: 200, body: %{"result" => info}}} ->
        {:ok, %{
          count: info["points_count"],
          dimensions: info["config"]["params"]["vectors"]["size"],
          metric: parse_distance(info["config"]["params"]["vectors"]["distance"]),
          size_bytes: nil
        }}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:error, _} = err ->
        err
    end
  end

  # Private

  defp request(method, path, body \\ nil) do
    url = config().base_url <> path

    headers = [
      {"content-type", "application/json"}
    ]

    headers = if api_key = config().api_key do
      [{"api-key", api_key} | headers]
    else
      headers
    end

    opts = [
      method: method,
      url: url,
      headers: headers,
      json: body,
      receive_timeout: config().timeout
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)

    Req.request(opts)
  end

  defp config do
    Application.get_env(:portfolio_index, :qdrant, [])
    |> Keyword.put_new(:base_url, "http://localhost:6333")
    |> then(&struct(__MODULE__, &1))
  end

  defp distance_name(:cosine), do: "Cosine"
  defp distance_name(:euclidean), do: "Euclid"
  defp distance_name(:dot_product), do: "Dot"

  defp parse_distance("Cosine"), do: :cosine
  defp parse_distance("Euclid"), do: :euclidean
  defp parse_distance("Dot"), do: :dot_product

  defp build_qdrant_filter(filter) when is_map(filter) do
    conditions = Enum.map(filter, fn {key, value} ->
      %{key: to_string(key), match: %{value: value}}
    end)

    %{must: conditions}
  end
end
```

### 3. Graph Store Adapters

#### 3.1 Neo4j Adapter
`lib/portfolio_index/adapters/graph_store/neo4j.ex`

```elixir
defmodule PortfolioIndex.Adapters.GraphStore.Neo4j do
  @moduledoc """
  Neo4j graph database adapter using Bolt protocol.
  Supports multi-database and graph namespacing.
  """

  @behaviour PortfolioCore.Ports.GraphStore

  alias Bolt.Sips, as: Bolt

  @impl true
  def create_graph(graph_id, config) do
    # In Neo4j, graphs are databases or just namespaced nodes
    # For simplicity, we use property-based namespacing
    query = """
    MERGE (g:_Graph {id: $graph_id})
    SET g.created_at = datetime(), g.config = $config
    RETURN g
    """

    case Bolt.query(Bolt.conn(), query, %{graph_id: graph_id, config: Jason.encode!(config)}) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def delete_graph(graph_id) do
    query = """
    MATCH (n {_graph_id: $graph_id})
    DETACH DELETE n
    """

    case Bolt.query(Bolt.conn(), query, %{graph_id: graph_id}) do
      {:ok, _} ->
        # Also delete the graph metadata node
        Bolt.query(Bolt.conn(), "MATCH (g:_Graph {id: $graph_id}) DELETE g", %{graph_id: graph_id})
        :ok

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def create_node(graph_id, node) do
    labels = Enum.join(node.labels, ":")
    label_clause = if labels == "", do: "", else: ":#{labels}"

    query = """
    CREATE (n#{label_clause} $props)
    SET n._graph_id = $graph_id, n.id = $node_id
    RETURN n
    """

    props = Map.merge(node.properties, %{id: node.id})

    case Bolt.query(Bolt.conn(), query, %{props: props, graph_id: graph_id, node_id: node.id}) do
      {:ok, %{results: [%{"n" => created}]}} ->
        {:ok, parse_node(created)}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def create_edge(graph_id, edge) do
    query = """
    MATCH (a {id: $from_id, _graph_id: $graph_id})
    MATCH (b {id: $to_id, _graph_id: $graph_id})
    CREATE (a)-[r:#{edge.type} $props]->(b)
    SET r.id = $edge_id, r._graph_id = $graph_id
    RETURN r
    """

    params = %{
      from_id: edge.from_id,
      to_id: edge.to_id,
      graph_id: graph_id,
      edge_id: edge.id,
      props: edge.properties
    }

    case Bolt.query(Bolt.conn(), query, params) do
      {:ok, %{results: [%{"r" => created}]}} ->
        {:ok, parse_edge(created, edge.from_id, edge.to_id)}

      {:ok, %{results: []}} ->
        {:error, :nodes_not_found}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def get_node(graph_id, node_id) do
    query = """
    MATCH (n {id: $node_id, _graph_id: $graph_id})
    RETURN n, labels(n) as labels
    """

    case Bolt.query(Bolt.conn(), query, %{node_id: node_id, graph_id: graph_id}) do
      {:ok, %{results: [%{"n" => node, "labels" => labels}]}} ->
        {:ok, parse_node(node, labels)}

      {:ok, %{results: []}} ->
        {:error, :not_found}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def get_neighbors(graph_id, node_id, opts) do
    direction = Keyword.get(opts, :direction, :both)
    edge_types = Keyword.get(opts, :edge_types, [])
    limit = Keyword.get(opts, :limit, 100)

    rel_pattern = build_rel_pattern(direction, edge_types)

    query = """
    MATCH (n {id: $node_id, _graph_id: $graph_id})#{rel_pattern}(neighbor)
    WHERE neighbor._graph_id = $graph_id
    RETURN DISTINCT neighbor, labels(neighbor) as labels
    LIMIT $limit
    """

    case Bolt.query(Bolt.conn(), query, %{node_id: node_id, graph_id: graph_id, limit: limit}) do
      {:ok, %{results: results}} ->
        nodes = Enum.map(results, fn %{"neighbor" => n, "labels" => l} ->
          parse_node(n, l)
        end)
        {:ok, nodes}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def query(graph_id, cypher_query, params) do
    # Inject graph_id filter for safety
    enhanced_params = Map.put(params, :_graph_id, graph_id)

    case Bolt.query(Bolt.conn(), cypher_query, enhanced_params) do
      {:ok, %{results: results}} ->
        {:ok, parse_query_results(results)}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def delete_node(graph_id, node_id) do
    query = """
    MATCH (n {id: $node_id, _graph_id: $graph_id})
    DETACH DELETE n
    """

    case Bolt.query(Bolt.conn(), query, %{node_id: node_id, graph_id: graph_id}) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def delete_edge(graph_id, edge_id) do
    query = """
    MATCH ()-[r {id: $edge_id, _graph_id: $graph_id}]-()
    DELETE r
    """

    case Bolt.query(Bolt.conn(), query, %{edge_id: edge_id, graph_id: graph_id}) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def graph_stats(graph_id) do
    query = """
    MATCH (n {_graph_id: $graph_id})
    WITH count(n) as node_count
    MATCH ()-[r {_graph_id: $graph_id}]-()
    RETURN node_count, count(r) as edge_count
    """

    case Bolt.query(Bolt.conn(), query, %{graph_id: graph_id}) do
      {:ok, %{results: [%{"node_count" => nodes, "edge_count" => edges}]}} ->
        {:ok, %{
          node_count: nodes,
          edge_count: edges,
          graph_id: graph_id
        }}

      {:ok, %{results: []}} ->
        {:ok, %{node_count: 0, edge_count: 0, graph_id: graph_id}}

      {:error, _} = err ->
        err
    end
  end

  # Private functions

  defp build_rel_pattern(:outgoing, []), do: "-->"
  defp build_rel_pattern(:incoming, []), do: "<--"
  defp build_rel_pattern(:both, []), do: "--"
  defp build_rel_pattern(:outgoing, types), do: "-[:#{Enum.join(types, "|")}]->"
  defp build_rel_pattern(:incoming, types), do: "<-[:#{Enum.join(types, "|")}]-"
  defp build_rel_pattern(:both, types), do: "-[:#{Enum.join(types, "|")}]-"

  defp parse_node(bolt_node, labels \\ nil) do
    props = bolt_node.properties
    %{
      id: props["id"],
      labels: labels || [],
      properties: Map.drop(props, ["id", "_graph_id"])
    }
  end

  defp parse_edge(bolt_rel, from_id, to_id) do
    props = bolt_rel.properties
    %{
      id: props["id"],
      type: bolt_rel.type,
      from_id: from_id,
      to_id: to_id,
      properties: Map.drop(props, ["id", "_graph_id"])
    }
  end

  defp parse_query_results(results) do
    %{
      nodes: [],
      edges: [],
      records: results
    }
  end
end
```

### 4. Embedder Adapters

#### 4.1 OpenAI Embedder
`lib/portfolio_index/adapters/embedder/openai.ex`

```elixir
defmodule PortfolioIndex.Adapters.Embedder.OpenAI do
  @moduledoc """
  OpenAI embeddings adapter with rate limiting and batching.
  """

  @behaviour PortfolioCore.Ports.Embedder

  require Logger

  @default_model "text-embedding-3-small"
  @models %{
    "text-embedding-3-small" => %{dimensions: 1536, max_tokens: 8191},
    "text-embedding-3-large" => %{dimensions: 3072, max_tokens: 8191},
    "text-embedding-ada-002" => %{dimensions: 1536, max_tokens: 8191}
  }

  @impl true
  def embed(text, opts) do
    model = Keyword.get(opts, :model, @default_model)

    body = %{
      model: model,
      input: text
    }

    body = if dims = Keyword.get(opts, :dimensions) do
      Map.put(body, :dimensions, dims)
    else
      body
    end

    case request("/embeddings", body) do
      {:ok, %{status: 200, body: response}} ->
        [%{"embedding" => vector}] = response["data"]
        {:ok, %{
          vector: vector,
          model: model,
          dimensions: length(vector),
          token_count: response["usage"]["total_tokens"]
        }}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def embed_batch(texts, opts) do
    model = Keyword.get(opts, :model, @default_model)
    batch_size = Keyword.get(opts, :batch_size, 100)

    texts
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, [], 0}, fn batch, {:ok, acc, total_tokens} ->
      body = %{model: model, input: batch}

      case request("/embeddings", body) do
        {:ok, %{status: 200, body: response}} ->
          embeddings = Enum.map(response["data"], fn %{"embedding" => vec, "index" => idx} ->
            %{
              vector: vec,
              model: model,
              dimensions: length(vec),
              token_count: 0  # Per-item tokens not provided in batch
            }
          end)

          new_total = total_tokens + response["usage"]["total_tokens"]
          {:cont, {:ok, acc ++ embeddings, new_total}}

        {:ok, %{status: 429}} ->
          {:halt, {:error, :rate_limited}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> case do
      {:ok, embeddings, total_tokens} ->
        {:ok, %{embeddings: embeddings, total_tokens: total_tokens}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def dimensions(model) do
    case Map.get(@models, model) do
      %{dimensions: dims} -> dims
      nil -> raise ArgumentError, "Unknown model: #{model}"
    end
  end

  @impl true
  def supported_models do
    Map.keys(@models)
  end

  defp request(path, body) do
    url = "https://api.openai.com/v1" <> path

    headers = [
      {"authorization", "Bearer #{api_key()}"},
      {"content-type", "application/json"}
    ]

    Req.post(url, headers: headers, json: body, receive_timeout: 60_000)
  end

  defp api_key do
    Application.get_env(:portfolio_index, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY") ||
      raise "OPENAI_API_KEY not configured"
  end
end
```

### 5. LLM Adapters

#### 5.1 Anthropic Adapter
`lib/portfolio_index/adapters/llm/anthropic.ex`

```elixir
defmodule PortfolioIndex.Adapters.LLM.Anthropic do
  @moduledoc """
  Anthropic Claude adapter for LLM operations.
  """

  @behaviour PortfolioCore.Ports.LLM

  @default_model "claude-3-sonnet-20240229"
  @models %{
    "claude-3-opus-20240229" => %{context_window: 200_000, max_output: 4096, supports_tools: true},
    "claude-3-sonnet-20240229" => %{context_window: 200_000, max_output: 4096, supports_tools: true},
    "claude-3-haiku-20240307" => %{context_window: 200_000, max_output: 4096, supports_tools: true}
  }

  @impl true
  def complete(messages, opts) do
    model = Keyword.get(opts, :model, @default_model)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    {system, messages} = extract_system(messages)

    body = %{
      model: model,
      max_tokens: max_tokens,
      messages: format_messages(messages)
    }

    body = if system, do: Map.put(body, :system, system), else: body

    case request("/messages", body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, %{
          content: extract_content(response["content"]),
          model: response["model"],
          usage: %{
            input_tokens: response["usage"]["input_tokens"],
            output_tokens: response["usage"]["output_tokens"]
          },
          finish_reason: parse_stop_reason(response["stop_reason"])
        }}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def stream(messages, opts) do
    model = Keyword.get(opts, :model, @default_model)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    {system, messages} = extract_system(messages)

    body = %{
      model: model,
      max_tokens: max_tokens,
      messages: format_messages(messages),
      stream: true
    }

    body = if system, do: Map.put(body, :system, system), else: body

    # Return a stream that yields chunks
    stream = Stream.resource(
      fn -> start_stream(body) end,
      fn
        {:error, _} = err -> {:halt, err}
        {:done, _} -> {:halt, nil}
        state -> read_stream_chunk(state)
      end,
      fn _ -> :ok end
    )

    {:ok, stream}
  end

  @impl true
  def supported_models, do: Map.keys(@models)

  @impl true
  def model_info(model), do: Map.get(@models, model)

  # Private functions

  defp extract_system(messages) do
    case Enum.split_with(messages, &(&1.role == :system)) do
      {[%{content: sys} | _], rest} -> {sys, rest}
      {[], messages} -> {nil, messages}
    end
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{role: to_string(msg.role), content: msg.content}
    end)
  end

  defp extract_content([%{"type" => "text", "text" => text} | _]), do: text
  defp extract_content(content) when is_binary(content), do: content

  defp parse_stop_reason("end_turn"), do: :stop
  defp parse_stop_reason("max_tokens"), do: :length
  defp parse_stop_reason("tool_use"), do: :tool_use
  defp parse_stop_reason(_), do: :stop

  defp request(path, body) do
    url = "https://api.anthropic.com/v1" <> path

    headers = [
      {"x-api-key", api_key()},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    Req.post(url, headers: headers, json: body, receive_timeout: 120_000)
  end

  defp start_stream(_body) do
    # Simplified - real implementation would use Finch for streaming
    {:error, :streaming_not_implemented}
  end

  defp read_stream_chunk(_state) do
    {:halt, nil}
  end

  defp api_key do
    Application.get_env(:portfolio_index, :anthropic_api_key) ||
      System.get_env("ANTHROPIC_API_KEY") ||
      raise "ANTHROPIC_API_KEY not configured"
  end
end
```

### 6. Broadway Pipelines

#### 6.1 Ingestion Pipeline
`lib/portfolio_index/pipelines/ingestion.ex`

```elixir
defmodule PortfolioIndex.Pipelines.Ingestion do
  @moduledoc """
  Broadway pipeline for document ingestion.
  Handles file reading, parsing, chunking, and queuing for embedding.
  """

  use Broadway
  require Logger

  alias Broadway.Message
  alias PortfolioCore.Telemetry

  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: opts[:name] || __MODULE__,
      producer: [
        module: {PortfolioIndex.Pipelines.Producers.FileProducer, opts[:producer] || []},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: opts[:concurrency] || 10,
          min_demand: 1,
          max_demand: 10
        ]
      ],
      batchers: [
        embedding: [
          concurrency: 2,
          batch_size: opts[:batch_size] || 50,
          batch_timeout: 5000
        ]
      ]
    )
  end

  @impl true
  def handle_message(_, %Message{data: file_info} = message, _context) do
    start_time = System.monotonic_time(:millisecond)

    case process_file(file_info) do
      {:ok, chunks} ->
        duration = System.monotonic_time(:millisecond) - start_time

        :telemetry.execute(
          [:portfolio_index, :ingestion, :file_processed],
          %{duration_ms: duration, chunk_count: length(chunks)},
          %{path: file_info.path}
        )

        message
        |> Message.update_data(fn _ -> chunks end)
        |> Message.put_batcher(:embedding)

      {:error, reason} ->
        Logger.warning("Failed to process #{file_info.path}: #{inspect(reason)}")
        Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:embedding, messages, _batch_info, _context) do
    chunks = Enum.flat_map(messages, fn msg -> msg.data end)

    Logger.info("Sending #{length(chunks)} chunks for embedding")

    # Queue chunks for embedding pipeline
    Enum.each(chunks, fn chunk ->
      PortfolioIndex.Pipelines.Embedding.enqueue(chunk)
    end)

    messages
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn msg ->
      Logger.error("Message failed: #{inspect(msg.data)}, status: #{inspect(msg.status)}")
    end)

    messages
  end

  defp process_file(%{path: path, type: type}) do
    with {:ok, content} <- File.read(path),
         {:ok, parsed} <- parse_content(content, type),
         {:ok, chunks} <- chunk_content(parsed, path) do
      {:ok, chunks}
    end
  end

  defp parse_content(content, :elixir) do
    {:ok, %{text: content, format: :code, language: :elixir}}
  end

  defp parse_content(content, :markdown) do
    {:ok, %{text: content, format: :markdown}}
  end

  defp parse_content(content, _type) do
    {:ok, %{text: content, format: :plain}}
  end

  defp chunk_content(parsed, source_path) do
    chunker = get_chunker()
    config = %{chunk_size: 1000, chunk_overlap: 200, separators: nil}

    case chunker.chunk(parsed.text, parsed.format, config) do
      {:ok, chunks} ->
        enriched = Enum.map(chunks, fn chunk ->
          Map.merge(chunk, %{
            source: source_path,
            format: parsed.format,
            language: parsed[:language]
          })
        end)
        {:ok, enriched}

      error ->
        error
    end
  end

  defp get_chunker do
    PortfolioCore.Registry.get(:chunker) ||
      PortfolioIndex.Adapters.Chunker.Recursive
  end
end
```

#### 6.2 Embedding Pipeline
`lib/portfolio_index/pipelines/embedding.ex`

```elixir
defmodule PortfolioIndex.Pipelines.Embedding do
  @moduledoc """
  Broadway pipeline for generating embeddings with rate limiting.
  """

  use Broadway
  require Logger

  alias Broadway.Message

  @queue_name :embedding_queue

  def start_link(opts) do
    # Initialize the queue
    :ets.new(@queue_name, [:named_table, :public, :ordered_set])

    Broadway.start_link(__MODULE__,
      name: opts[:name] || __MODULE__,
      producer: [
        module: {PortfolioIndex.Pipelines.Producers.ETSProducer, table: @queue_name},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: opts[:concurrency] || 5,
          min_demand: 1,
          max_demand: 5
        ]
      ],
      batchers: [
        store: [
          concurrency: 2,
          batch_size: opts[:batch_size] || 100,
          batch_timeout: 2000
        ]
      ],
      rate_limiting: [
        allowed_messages: opts[:rate_limit] || 100,
        interval: 60_000  # per minute
      ]
    )
  end

  def enqueue(chunk) do
    key = System.unique_integer([:monotonic, :positive])
    :ets.insert(@queue_name, {key, chunk})
  end

  @impl true
  def handle_message(_, %Message{data: chunk} = message, _context) do
    embedder = get_embedder()

    case embedder.embed(chunk.content, []) do
      {:ok, result} ->
        enriched = Map.merge(chunk, %{
          embedding: result.vector,
          token_count: result.token_count,
          model: result.model
        })

        :telemetry.execute(
          [:portfolio_index, :embedding, :generated],
          %{tokens: result.token_count, dimensions: result.dimensions},
          %{model: result.model}
        )

        message
        |> Message.update_data(fn _ -> enriched end)
        |> Message.put_batcher(:store)

      {:error, :rate_limited} ->
        # Re-queue for later
        enqueue(chunk)
        Message.failed(message, :rate_limited)

      {:error, reason} ->
        Logger.error("Embedding failed: #{inspect(reason)}")
        Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:store, messages, _batch_info, _context) do
    vector_store = get_vector_store()
    index_id = Application.get_env(:portfolio_index, :default_index, "default")

    items = Enum.map(messages, fn msg ->
      chunk = msg.data
      id = generate_chunk_id(chunk)
      metadata = %{
        source: chunk.source,
        index: chunk.index,
        format: chunk.format
      }
      {id, chunk.embedding, metadata}
    end)

    case vector_store.store_batch(index_id, items) do
      {:ok, count} ->
        Logger.info("Stored #{count} embeddings")

      {:error, reason} ->
        Logger.error("Failed to store batch: #{inspect(reason)}")
    end

    messages
  end

  defp get_embedder do
    case PortfolioCore.Registry.get(:embedder) do
      {module, _config} -> module
      nil -> PortfolioIndex.Adapters.Embedder.OpenAI
    end
  end

  defp get_vector_store do
    case PortfolioCore.Registry.get(:vector_store) do
      {module, _config} -> module
      nil -> PortfolioIndex.Adapters.VectorStore.Pgvector
    end
  end

  defp generate_chunk_id(chunk) do
    content_hash = :crypto.hash(:md5, chunk.content) |> Base.encode16(case: :lower)
    "#{chunk.source}:#{chunk.index}:#{String.slice(content_hash, 0..7)}"
  end
end
```

### 7. RAG Strategies

#### 7.1 Base Strategy Behaviour
`lib/portfolio_index/rag/strategy.ex`

```elixir
defmodule PortfolioIndex.RAG.Strategy do
  @moduledoc """
  Behaviour for RAG retrieval strategies.
  """

  @type query :: String.t()
  @type context :: map()
  @type opts :: keyword()

  @type retrieved_item :: %{
    content: String.t(),
    score: float(),
    source: String.t(),
    metadata: map()
  }

  @type result :: %{
    items: [retrieved_item()],
    answer: String.t() | nil,
    strategy: atom(),
    timing_ms: non_neg_integer(),
    tokens_used: non_neg_integer()
  }

  @callback retrieve(query(), context(), opts()) :: {:ok, result()} | {:error, term()}
  @callback name() :: atom()
end
```

#### 7.2 Hybrid RAG Strategy
`lib/portfolio_index/rag/strategies/hybrid.ex`

```elixir
defmodule PortfolioIndex.RAG.Strategies.Hybrid do
  @moduledoc """
  Hybrid retrieval combining vector search with keyword search.
  Uses Reciprocal Rank Fusion (RRF) for result merging.
  """

  @behaviour PortfolioIndex.RAG.Strategy

  alias PortfolioIndex.Adapters.Embedder.OpenAI, as: Embedder
  alias PortfolioIndex.Adapters.VectorStore.Pgvector, as: VectorStore

  @impl true
  def name, do: :hybrid

  @impl true
  def retrieve(query, context, opts) do
    start_time = System.monotonic_time(:millisecond)

    k = Keyword.get(opts, :k, 10)
    index_id = context[:index_id] || "default"

    with {:ok, %{vector: query_vector}} <- Embedder.embed(query, []),
         {:ok, vector_results} <- VectorStore.search(index_id, query_vector, k * 2, []),
         {:ok, keyword_results} <- keyword_search(query, index_id, k * 2) do

      # Merge results with RRF
      merged = reciprocal_rank_fusion([
        {:vector, vector_results},
        {:keyword, keyword_results}
      ], k: 60)

      final = Enum.take(merged, k)

      duration = System.monotonic_time(:millisecond) - start_time

      {:ok, %{
        items: final,
        answer: nil,
        strategy: :hybrid,
        timing_ms: duration,
        tokens_used: 0
      }}
    end
  end

  defp keyword_search(query, _index_id, _k) do
    # Simplified - would use PostgreSQL full-text search
    {:ok, []}
  end

  defp reciprocal_rank_fusion(ranked_lists, opts) do
    k = Keyword.get(opts, :k, 60)

    # Calculate RRF scores
    all_scores = Enum.reduce(ranked_lists, %{}, fn {_source, items}, acc ->
      items
      |> Enum.with_index(1)
      |> Enum.reduce(acc, fn {item, rank}, inner_acc ->
        rrf_score = 1.0 / (k + rank)
        Map.update(inner_acc, item.id, {item, rrf_score}, fn {existing, score} ->
          {existing, score + rrf_score}
        end)
      end)
    end)

    # Sort by combined score
    all_scores
    |> Map.values()
    |> Enum.sort_by(fn {_item, score} -> -score end)
    |> Enum.map(fn {item, score} -> %{item | score: score} end)
  end
end
```

#### 7.3 Self-RAG Strategy
`lib/portfolio_index/rag/strategies/self_rag.ex`

```elixir
defmodule PortfolioIndex.RAG.Strategies.SelfRAG do
  @moduledoc """
  Self-RAG with retrieval and self-reflection.
  """

  @behaviour PortfolioIndex.RAG.Strategy

  alias PortfolioIndex.Adapters.LLM.Anthropic, as: LLM
  alias PortfolioIndex.RAG.Strategies.Hybrid

  @impl true
  def name, do: :self_rag

  @impl true
  def retrieve(query, context, opts) do
    start_time = System.monotonic_time(:millisecond)

    # Step 1: Determine if retrieval is needed
    with {:ok, needs_retrieval} <- assess_retrieval_need(query),
         {:ok, retrieved} <- maybe_retrieve(query, context, opts, needs_retrieval),
         {:ok, answer, critique} <- generate_with_critique(query, retrieved),
         {:ok, final_answer} <- maybe_refine(query, answer, critique, retrieved) do

      duration = System.monotonic_time(:millisecond) - start_time

      {:ok, %{
        items: retrieved.items,
        answer: final_answer,
        strategy: :self_rag,
        timing_ms: duration,
        tokens_used: 0,
        critique: critique
      }}
    end
  end

  defp assess_retrieval_need(query) do
    messages = [
      %{role: :system, content: "Determine if external knowledge is needed to answer this query. Respond with YES or NO."},
      %{role: :user, content: query}
    ]

    case LLM.complete(messages, max_tokens: 10) do
      {:ok, %{content: response}} ->
        {:ok, String.contains?(String.upcase(response), "YES")}

      error ->
        error
    end
  end

  defp maybe_retrieve(query, context, opts, true) do
    Hybrid.retrieve(query, context, opts)
  end

  defp maybe_retrieve(_query, _context, _opts, false) do
    {:ok, %{items: []}}
  end

  defp generate_with_critique(query, retrieved) do
    context_text = retrieved.items
    |> Enum.map(& &1.content)
    |> Enum.join("\n\n---\n\n")

    messages = [
      %{role: :system, content: """
      Answer the question using the provided context.
      After your answer, provide a self-critique on a scale of 1-5:
      - Relevance: How relevant is your answer to the question?
      - Support: How well is your answer supported by the context?
      - Completeness: How complete is your answer?

      Format:
      ANSWER: [your answer]
      CRITIQUE:
      - Relevance: [1-5]
      - Support: [1-5]
      - Completeness: [1-5]
      """},
      %{role: :user, content: "Context:\n#{context_text}\n\nQuestion: #{query}"}
    ]

    case LLM.complete(messages, max_tokens: 2000) do
      {:ok, %{content: response}} ->
        {answer, critique} = parse_critique(response)
        {:ok, answer, critique}

      error ->
        error
    end
  end

  defp parse_critique(response) do
    case String.split(response, "CRITIQUE:", parts: 2) do
      [answer, critique_text] ->
        critique = %{
          relevance: extract_score(critique_text, "Relevance"),
          support: extract_score(critique_text, "Support"),
          completeness: extract_score(critique_text, "Completeness")
        }
        {String.trim(String.replace(answer, "ANSWER:", "")), critique}

      _ ->
        {response, %{relevance: 3, support: 3, completeness: 3}}
    end
  end

  defp extract_score(text, metric) do
    case Regex.run(~r/#{metric}:\s*(\d)/, text) do
      [_, score] -> String.to_integer(score)
      nil -> 3
    end
  end

  defp maybe_refine(query, answer, critique, retrieved) do
    min_score = Enum.min([critique.relevance, critique.support, critique.completeness])

    if min_score < 3 do
      # Low score - try to refine
      refine_answer(query, answer, critique, retrieved)
    else
      {:ok, answer}
    end
  end

  defp refine_answer(query, previous_answer, critique, retrieved) do
    context_text = retrieved.items
    |> Enum.map(& &1.content)
    |> Enum.join("\n\n---\n\n")

    messages = [
      %{role: :system, content: """
      The previous answer received low scores. Please provide an improved answer.
      Previous scores: Relevance=#{critique.relevance}, Support=#{critique.support}, Completeness=#{critique.completeness}
      """},
      %{role: :user, content: """
      Context: #{context_text}
      Question: #{query}
      Previous answer: #{previous_answer}

      Provide an improved answer:
      """}
    ]

    case LLM.complete(messages, max_tokens: 2000) do
      {:ok, %{content: response}} -> {:ok, response}
      error -> error
    end
  end
end
```

### 8. Test Structure

#### 8.1 Test Helper
`test/test_helper.exs`

```elixir
ExUnit.start()

# Define mocks
Mox.defmock(PortfolioIndex.Mocks.VectorStore, for: PortfolioCore.Ports.VectorStore)
Mox.defmock(PortfolioIndex.Mocks.GraphStore, for: PortfolioCore.Ports.GraphStore)
Mox.defmock(PortfolioIndex.Mocks.Embedder, for: PortfolioCore.Ports.Embedder)
Mox.defmock(PortfolioIndex.Mocks.LLM, for: PortfolioCore.Ports.LLM)
```

#### 8.2 Adapter Tests with Bypass
`test/adapters/embedder/openai_test.exs`

```elixir
defmodule PortfolioIndex.Adapters.Embedder.OpenAITest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.Embedder.OpenAI

  setup do
    bypass = Bypass.open()
    Application.put_env(:portfolio_index, :openai_base_url, "http://localhost:#{bypass.port}")
    Application.put_env(:portfolio_index, :openai_api_key, "test-key")

    on_exit(fn ->
      Application.delete_env(:portfolio_index, :openai_base_url)
      Application.delete_env(:portfolio_index, :openai_api_key)
    end)

    {:ok, bypass: bypass}
  end

  describe "embed/2" do
    test "returns embedding for text", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/embeddings", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["input"] == "test text"

        response = %{
          "data" => [%{"embedding" => List.duplicate(0.1, 1536)}],
          "usage" => %{"total_tokens" => 2}
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      assert {:ok, result} = OpenAI.embed("test text", [])
      assert length(result.vector) == 1536
      assert result.token_count == 2
    end

    test "handles rate limiting", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/embeddings", fn conn ->
        conn
        |> Plug.Conn.resp(429, "Rate limited")
      end)

      assert {:error, :rate_limited} = OpenAI.embed("test", [])
    end
  end
end
```

### 9. Examples

#### 9.1 examples/README.md

```markdown
# Portfolio Index Examples

## Running Examples

Ensure environment variables are set:
```bash
export OPENAI_API_KEY=your-key
export ANTHROPIC_API_KEY=your-key
export NEO4J_URI=bolt://localhost:7687
```

Run examples:
```bash
# Basic embedding
mix run examples/embedding_example.exs

# Vector search
mix run examples/vector_search_example.exs

# RAG query
mix run examples/rag_query_example.exs

# Graph operations
mix run examples/graph_example.exs
```
```

#### 9.2 examples/rag_query_example.exs

```elixir
# RAG Query Example
# Run: mix run examples/rag_query_example.exs

alias PortfolioIndex.RAG.Strategies.Hybrid
alias PortfolioIndex.Adapters.VectorStore.Pgvector
alias PortfolioIndex.Adapters.Embedder.OpenAI

# Setup - create and populate index
IO.puts("Setting up vector index...")

:ok = Pgvector.create_index("demo", %{dimensions: 1536, metric: :cosine})

# Sample documents
docs = [
  "Elixir is a dynamic, functional language for building scalable applications.",
  "Phoenix is a web framework written in Elixir that uses the MVC pattern.",
  "GenServer is an Elixir behaviour for implementing server processes.",
  "Broadway is a library for building data ingestion pipelines.",
  "Ecto is a database wrapper and query generator for Elixir."
]

IO.puts("Generating embeddings and storing documents...")

Enum.with_index(docs)
|> Enum.each(fn {doc, idx} ->
  {:ok, %{vector: vec}} = OpenAI.embed(doc, [])
  :ok = Pgvector.store("demo", "doc_#{idx}", vec, %{content: doc})
  IO.puts("  Stored doc_#{idx}")
end)

# Query
query = "What is used for building web applications in Elixir?"
IO.puts("\nQuery: #{query}")

{:ok, result} = Hybrid.retrieve(query, %{index_id: "demo"}, k: 3)

IO.puts("\nResults (#{result.timing_ms}ms):")
Enum.each(result.items, fn item ->
  IO.puts("  [#{Float.round(item.score, 3)}] #{item.metadata[:content]}")
end)

# Cleanup
:ok = Pgvector.delete_index("demo")
IO.puts("\nCleaned up demo index.")
```

---

## Quality Requirements

### All tests must pass:
```bash
mix test
```

### No compiler warnings:
```bash
mix compile --warnings-as-errors
```

### Credo strict must pass:
```bash
mix credo --strict
```

### Dialyzer must pass:
```bash
mix dialyzer
```

### Test coverage > 80%:
```bash
mix coveralls.html
```

---

## Deliverables Checklist

### Adapters
- [ ] VectorStore: Pgvector adapter with full CRUD
- [ ] VectorStore: Qdrant adapter with full CRUD
- [ ] GraphStore: Neo4j adapter with multi-graph support
- [ ] Embedder: OpenAI adapter with batching
- [ ] LLM: Anthropic Claude adapter
- [ ] Chunker: Recursive text splitter

### Pipelines
- [ ] Ingestion pipeline with Broadway
- [ ] Embedding pipeline with rate limiting
- [ ] Cost tracking telemetry

### RAG Strategies
- [ ] Hybrid (vector + keyword with RRF)
- [ ] Self-RAG with critique
- [ ] Strategy registry

### Quality
- [ ] All tests pass with mocks
- [ ] Bypass tests for HTTP adapters
- [ ] Examples run with real integrations
- [ ] No compiler warnings
- [ ] Credo --strict passes
- [ ] Dialyzer passes

### Documentation
- [ ] README.md with setup instructions
- [ ] examples/README.md
- [ ] CHANGELOG.md
