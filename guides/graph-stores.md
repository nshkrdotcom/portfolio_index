# Graph Stores

PortfolioIndex provides a Neo4j graph store adapter for knowledge graph operations,
entity relationships, and GraphRAG retrieval.

## Neo4j Adapter

`PortfolioIndex.Adapters.GraphStore.Neo4j` connects to Neo4j via the
[boltx](https://hex.pm/packages/boltx) Bolt driver.

### Configuration

```elixir
# config/dev.exs
config :boltx, Boltx,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  pool_size: 10,
  name: Boltx
```

Environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `NEO4J_URI` | Bolt connection URI | `bolt://localhost:7687` |
| `NEO4J_USER` | Username | `neo4j` |
| `NEO4J_PASSWORD` | Password | -- |

### Graph Namespaces

All operations are scoped to a graph namespace via `_graph_id`, providing
multi-tenant isolation:

```elixir
alias PortfolioIndex.Adapters.GraphStore.Neo4j

:ok = Neo4j.create_graph("project_a", %{})
:ok = Neo4j.create_graph("project_b", %{})

# Nodes in different graphs don't interfere
Neo4j.create_node("project_a", %{labels: ["File"], properties: %{path: "/app.ex"}})
Neo4j.create_node("project_b", %{labels: ["File"], properties: %{path: "/app.ex"}})
```

### Creating Nodes and Edges

```elixir
{:ok, node1} = Neo4j.create_node("knowledge", %{
  labels: ["Concept"],
  properties: %{name: "Elixir", type: "language"}
})

{:ok, node2} = Neo4j.create_node("knowledge", %{
  labels: ["Concept"],
  properties: %{name: "GenServer", type: "behaviour"}
})

{:ok, _edge} = Neo4j.create_edge("knowledge", %{
  from_id: node1.id,
  to_id: node2.id,
  type: "HAS_FEATURE",
  properties: %{since: "1.0"}
})
```

### Querying

```elixir
# Get neighbors
{:ok, neighbors} = Neo4j.get_neighbors("knowledge", node1.id, direction: :outgoing)

# Custom Cypher queries
cypher = """
MATCH (p:Person {_graph_id: $graph_id})
WHERE p.age > $min_age
RETURN p.name AS name, p.age AS age
ORDER BY p.age DESC
"""
{:ok, result} = Neo4j.query("my_graph", cypher, %{min_age: 25})
```

Both `$graph_id` and `$_graph_id` are available in custom Cypher queries.

### Schema Management

`PortfolioIndex.Adapters.GraphStore.Neo4j.Schema` manages constraints and indexes:

```elixir
alias PortfolioIndex.Adapters.GraphStore.Neo4j.Schema

Schema.setup!()                    # Create all constraints and indexes
Schema.version()                   # Check current schema version
Schema.migrate!(2)                 # Run migrations up to version 2
Schema.reset!()                    # Reset database (testing only)
Schema.clean_graph!("my_graph")    # Clean a specific graph namespace
```

Schema versions are tracked in a `:SchemaVersion` node:

```cypher
(:SchemaVersion {id: 'current', version: 1, updated_at: datetime()})
```

Created constraints and indexes:

| Type | Name | Description |
|------|------|-------------|
| Constraint | `node_id_unique` | Unique node IDs within a graph |
| Constraint | `edge_id_unique` | Unique edge IDs within a graph |
| Index | `idx_node_graph_id` | Fast graph isolation queries |
| Index | `idx_node_labels` | Label-based queries |
| Index | `idx_fulltext_content` | Full-text search on content/name/title |

## Submodules

### Entity Search

`PortfolioIndex.Adapters.GraphStore.Neo4j.EntitySearch` provides vector-based
entity search within the graph:

```elixir
alias PortfolioIndex.Adapters.GraphStore.Neo4j.EntitySearch

{:ok, entities} = EntitySearch.search("knowledge", query_vector, k: 5)
```

### Community Detection

`PortfolioIndex.Adapters.GraphStore.Neo4j.Community` manages community
structures for GraphRAG:

```elixir
alias PortfolioIndex.Adapters.GraphStore.Neo4j.Community

{:ok, communities} = Community.list("knowledge")
{:ok, community} = Community.get("knowledge", community_id)
```

### Graph Traversal

`PortfolioIndex.Adapters.GraphStore.Neo4j.Traversal` provides BFS, subgraph
extraction, and path finding:

```elixir
alias PortfolioIndex.Adapters.GraphStore.Neo4j.Traversal

{:ok, subgraph} = Traversal.bfs("knowledge", start_node_id, max_depth: 3)
{:ok, path} = Traversal.shortest_path("knowledge", from_id, to_id)
```

## Telemetry Events

```elixir
[:portfolio_index, :graph_store, :create_node]  # %{duration_ms: 5}
[:portfolio_index, :graph_store, :create_edge]   # %{duration_ms: 5}
[:portfolio_index, :graph_store, :query]          # %{duration_ms: 5}
```

All events include `%{graph_id: "my_graph"}` in metadata.
