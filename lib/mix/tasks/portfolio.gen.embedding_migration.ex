defmodule Mix.Tasks.Portfolio.Gen.EmbeddingMigration do
  @moduledoc """
  Generates a migration for changing embedding dimensions.

  ## Usage

      mix portfolio.gen.embedding_migration --dimension 1536

  This is useful when switching embedding models with different dimensions.

  ## Options

  - `--dimension` - New embedding dimension (required)
  - `--table` - Table name (default: portfolio_chunks)
  - `--column` - Column name (default: embedding)
  - `--migrations-path` - Path for migrations (default: priv/repo/migrations)
  """

  use Mix.Task

  import Mix.Generator

  @shortdoc "Generate migration to change embedding dimensions"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          dimension: :integer,
          table: :string,
          column: :string,
          migrations_path: :string
        ]
      )

    dimension = opts[:dimension]
    table = opts[:table] || "portfolio_chunks"
    column = opts[:column] || "embedding"
    migrations_path = opts[:migrations_path]

    unless dimension do
      Mix.raise(
        "--dimension option is required. Example: mix portfolio.gen.embedding_migration --dimension 1536"
      )
    end

    generate_migration(dimension, table, column, migrations_path)
  end

  defp generate_migration(dimension, table, column, migrations_path) do
    migrations_dir = migrations_path || default_migrations_path()

    # Ensure the directory exists
    File.mkdir_p!(migrations_dir)

    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    filename = "#{timestamp}_update_embedding_dimensions.exs"
    path = Path.join(migrations_dir, filename)

    content = migration_content(dimension, table, column)

    create_file(path, content)

    Mix.shell().info("""

    Generated migration: #{path}

    This migration will:
    1. Drop the HNSW index on the #{column} column
    2. Alter the #{column} column to #{dimension} dimensions
    3. Recreate the HNSW index

    Run the migration with:

        mix ecto.migrate

    After migrating, re-embed all documents with:

        mix portfolio.reembed

    """)
  end

  defp default_migrations_path do
    Path.join(["priv", "repo", "migrations"])
  end

  defp migration_content(dimension, table, column) do
    """
    defmodule PortfolioIndex.Repo.Migrations.UpdateEmbeddingDimensions do
      use Ecto.Migration

      @table :#{table}
      @column :#{column}
      @new_dimension #{dimension}
      @old_dimension 384

      def up do
        # Drop the existing HNSW index
        execute "DROP INDEX IF EXISTS #{table}_#{column}_idx"

        # Alter the embedding column to new dimensions
        # This requires dropping and recreating the column due to pgvector constraints
        execute \"\"\"
        ALTER TABLE #{table}
        ALTER COLUMN #{column} TYPE vector(@new_dimension)
        \"\"\"

        # Recreate the HNSW index with the new dimensions
        execute \"\"\"
        CREATE INDEX #{table}_#{column}_idx ON #{table}
        USING hnsw (#{column} vector_cosine_ops)
        \"\"\"
      end

      def down do
        # Drop the new index
        execute "DROP INDEX IF EXISTS #{table}_#{column}_idx"

        # Revert to previous dimensions
        execute \"\"\"
        ALTER TABLE #{table}
        ALTER COLUMN #{column} TYPE vector(@old_dimension)
        \"\"\"

        # Recreate the original index
        execute \"\"\"
        CREATE INDEX #{table}_#{column}_idx ON #{table}
        USING hnsw (#{column} vector_cosine_ops)
        \"\"\"
      end
    end
    """
  end
end
