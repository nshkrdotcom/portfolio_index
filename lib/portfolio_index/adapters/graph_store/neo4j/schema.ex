defmodule PortfolioIndex.Adapters.GraphStore.Neo4j.Schema do
  @moduledoc """
  Neo4j schema management - constraints, indexes, and migrations.

  Unlike SQL databases, Neo4j doesn't have a formal migration system.
  This module provides schema setup and versioning for Neo4j.

  ## Usage

      # Setup all constraints and indexes
      Neo4j.Schema.setup!()

      # Check current schema version
      Neo4j.Schema.version()

      # Run specific migration
      Neo4j.Schema.migrate!(3)

  ## Schema Versioning

  Schema versions are tracked in a `:SchemaVersion` node in Neo4j.
  Each migration is idempotent and can be re-run safely.
  """

  require Logger

  @schema_version 1

  @doc """
  Setup the Neo4j schema with all constraints and indexes.
  """
  def setup! do
    Logger.info("[Neo4j.Schema] Setting up schema version #{@schema_version}...")

    with :ok <- create_schema_version_node(),
         :ok <- create_constraints(),
         :ok <- create_indexes(),
         :ok <- update_schema_version(@schema_version) do
      Logger.info("[Neo4j.Schema] Schema setup complete")
      :ok
    end
  end

  @doc """
  Get the current schema version from Neo4j.
  """
  def version do
    query = "MATCH (s:SchemaVersion) RETURN s.version AS version ORDER BY s.version DESC LIMIT 1"

    case Boltx.query(Boltx, query) do
      {:ok, %{results: [%{"version" => version}]}} -> version
      {:ok, %{results: []}} -> 0
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Run migrations up to the specified version.
  """
  def migrate!(target_version \\ @schema_version) do
    case version() do
      {:error, reason} ->
        Logger.error("[Neo4j.Schema] Could not determine current version: #{inspect(reason)}")
        {:error, :version_check_failed}

      current when current >= target_version ->
        Logger.info("[Neo4j.Schema] Already at version #{current}, nothing to migrate")
        :ok

      current ->
        Logger.info("[Neo4j.Schema] Migrating from version #{current} to #{target_version}")
        run_migrations(current + 1, target_version)
    end
  end

  @doc """
  Reset the Neo4j database (DANGEROUS - for testing only).
  Deletes all nodes and relationships.
  """
  def reset! do
    Logger.warning("[Neo4j.Schema] Resetting database - deleting all data!")

    queries = [
      "MATCH (n) DETACH DELETE n",
      "CALL apoc.schema.assert({}, {}) YIELD label RETURN label"
    ]

    Enum.each(queries, fn query ->
      case Boltx.query(Boltx, query) do
        {:ok, _} ->
          :ok

        {:error, %{code: "Neo.ClientError.Procedure.ProcedureNotFound"}} ->
          # APOC not installed, skip
          :ok

        {:error, reason} ->
          Logger.warning("[Neo4j.Schema] Reset query failed: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Clean test data for a specific graph namespace.
  """
  def clean_graph!(graph_id) do
    query = "MATCH (n {_graph_id: $graph_id}) DETACH DELETE n"

    case Boltx.query(Boltx, query, %{graph_id: graph_id}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp create_schema_version_node do
    query = """
    MERGE (s:SchemaVersion {id: 'current'})
    ON CREATE SET s.version = 0, s.created_at = datetime()
    RETURN s
    """

    case Boltx.query(Boltx, query) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_constraints do
    constraints = [
      # Unique constraint on node external IDs within a graph
      {"node_id_unique",
       """
         CREATE CONSTRAINT node_id_unique IF NOT EXISTS
         FOR (n:Node) REQUIRE (n._graph_id, n._external_id) IS UNIQUE
       """},

      # Unique constraint on edge external IDs within a graph
      {"edge_id_unique",
       """
         CREATE CONSTRAINT edge_id_unique IF NOT EXISTS
         FOR ()-[r:RELATES_TO]-() REQUIRE (r._graph_id, r._external_id) IS UNIQUE
       """}
    ]

    Enum.reduce_while(constraints, :ok, fn {name, query}, :ok ->
      case Boltx.query(Boltx, query) do
        {:ok, _} ->
          Logger.debug("[Neo4j.Schema] Created constraint: #{name}")
          {:cont, :ok}

        {:error, %{code: "Neo.ClientError.Schema.EquivalentSchemaRuleAlreadyExists"}} ->
          Logger.debug("[Neo4j.Schema] Constraint already exists: #{name}")
          {:cont, :ok}

        {:error, %{code: "Neo.DatabaseError.Schema.ConstraintCreationFailed"}} ->
          # Some constraints may not be supported in Community Edition
          Logger.debug("[Neo4j.Schema] Constraint not supported: #{name}")
          {:cont, :ok}

        {:error, reason} ->
          Logger.error("[Neo4j.Schema] Failed to create constraint #{name}: #{inspect(reason)}")
          {:halt, {:error, reason}}
      end
    end)
  end

  defp create_indexes do
    indexes = [
      # Index on graph_id for fast graph isolation queries
      {"idx_node_graph_id",
       """
         CREATE INDEX idx_node_graph_id IF NOT EXISTS
         FOR (n:Node) ON (n._graph_id)
       """},

      # Index on node labels for label-based queries
      {"idx_node_labels",
       """
         CREATE INDEX idx_node_labels IF NOT EXISTS
         FOR (n:Node) ON (n._labels)
       """},

      # Fulltext index for content search (if APOC available)
      {"idx_fulltext_content",
       """
         CREATE FULLTEXT INDEX idx_fulltext_content IF NOT EXISTS
         FOR (n:Node) ON EACH [n.content, n.name, n.title]
       """}
    ]

    Enum.reduce_while(indexes, :ok, fn {name, query}, :ok ->
      case Boltx.query(Boltx, query) do
        {:ok, _} ->
          Logger.debug("[Neo4j.Schema] Created index: #{name}")
          {:cont, :ok}

        {:error, %{code: "Neo.ClientError.Schema.EquivalentSchemaRuleAlreadyExists"}} ->
          Logger.debug("[Neo4j.Schema] Index already exists: #{name}")
          {:cont, :ok}

        {:error, %{code: code}}
        when code in [
               "Neo.ClientError.Statement.SyntaxError",
               "Neo.DatabaseError.Schema.IndexCreationFailed"
             ] ->
          # Some indexes may not be supported
          Logger.debug("[Neo4j.Schema] Index not supported: #{name}")
          {:cont, :ok}

        {:error, reason} ->
          Logger.error("[Neo4j.Schema] Failed to create index #{name}: #{inspect(reason)}")
          {:halt, {:error, reason}}
      end
    end)
  end

  defp update_schema_version(version) do
    query = """
    MATCH (s:SchemaVersion {id: 'current'})
    SET s.version = $version, s.updated_at = datetime()
    RETURN s
    """

    case Boltx.query(Boltx, query, %{version: version}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_migrations(from, to) do
    Enum.each(from..to//1, fn version ->
      run_migration(version)
      update_schema_version(version)
    end)

    :ok
  end

  defp run_migration(1) do
    # Version 1: Base schema (already created in setup)
    Logger.info("[Neo4j.Schema] Migration 1: Base schema")
  end

  defp run_migration(version) do
    Logger.warning("[Neo4j.Schema] Unknown migration version: #{version}")
  end
end
