defmodule Mix.Tasks.Portfolio.Install do
  @moduledoc """
  Installs PortfolioIndex into a Phoenix application.

  ## Usage

      mix portfolio.install

  ## What it does

  1. Creates required database migrations
  2. Prints configuration instructions
  3. Provides next steps for setup

  ## Options

  - `--repo` - Ecto repo module (default: inferred from app)
  - `--dimension` - Embedding vector dimension (default: 384)
  - `--no-migrations` - Skip migration generation
  """

  use Mix.Task

  import Mix.Generator

  @shortdoc "Install PortfolioIndex in your application"

  @migration_template """
  defmodule <%= @repo %>.Migrations.CreatePortfolioTables do
    use Ecto.Migration

    def up do
      execute "CREATE EXTENSION IF NOT EXISTS vector"

      create table(:portfolio_collections, primary_key: false) do
        add :id, :binary_id, primary_key: true
        add :name, :string, null: false
        add :description, :text
        add :metadata, :map, default: %{}

        timestamps(type: :utc_datetime)
      end

      create unique_index(:portfolio_collections, [:name])

      create table(:portfolio_documents, primary_key: false) do
        add :id, :binary_id, primary_key: true
        add :source_id, :string
        add :content_hash, :string
        add :title, :string
        add :source_path, :string
        add :metadata, :map, default: %{}
        add :status, :string, default: "pending"
        add :error_message, :text
        add :chunk_count, :integer, default: 0
        add :collection_id, references(:portfolio_collections, type: :binary_id, on_delete: :nilify_all)

        timestamps(type: :utc_datetime)
      end

      create index(:portfolio_documents, [:source_id])
      create index(:portfolio_documents, [:content_hash])
      create index(:portfolio_documents, [:status])
      create index(:portfolio_documents, [:collection_id])

      create table(:portfolio_chunks, primary_key: false) do
        add :id, :binary_id, primary_key: true
        add :content, :text, null: false
        add :embedding, :vector, size: <%= @dimension %>, null: true
        add :chunk_index, :integer, default: 0
        add :token_count, :integer
        add :start_char, :integer
        add :end_char, :integer
        add :metadata, :map, default: %{}
        add :document_id, references(:portfolio_documents, type: :binary_id, on_delete: :delete_all)

        timestamps(type: :utc_datetime)
      end

      create index(:portfolio_chunks, [:document_id])

      execute \"\"\"
      CREATE INDEX portfolio_chunks_embedding_idx ON portfolio_chunks
      USING hnsw (embedding vector_cosine_ops)
      \"\"\"
    end

    def down do
      drop table(:portfolio_chunks)
      drop table(:portfolio_documents)
      drop table(:portfolio_collections)
      # Note: We don't drop the vector extension as it may be used by other tables
    end
  end
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          repo: :string,
          dimension: :integer,
          no_migrations: :boolean
        ]
      )

    repo = opts[:repo] || infer_repo()
    dimension = opts[:dimension] || 384
    skip_migrations = opts[:no_migrations] || false

    unless skip_migrations do
      generate_migration(repo, dimension)
    end

    print_instructions(repo, dimension)
  end

  defp generate_migration(repo, dimension) do
    repo_underscore =
      repo
      |> String.replace(".", "/")
      |> Macro.underscore()
      |> String.replace("/", "_")

    migrations_path = Path.join(["priv", repo_underscore, "migrations"])
    File.mkdir_p!(migrations_path)

    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    filename = "#{timestamp}_create_portfolio_tables.exs"
    path = Path.join(migrations_path, filename)

    content = EEx.eval_string(@migration_template, assigns: [repo: repo, dimension: dimension])

    create_file(path, content)
  end

  defp print_instructions(repo, dimension) do
    Mix.shell().info("""

    PortfolioIndex installation complete!

    Configuration for #{repo} with #{dimension} dimensions.

    == Next Steps ==

    1. Run the migration:

        mix ecto.migrate

    2. Configure pgvector types in your repo config:

        # config/config.exs
        config :my_app, #{repo},
          types: MyApp.PostgrexTypes

    3. Create the types module (if not already present):

        # lib/my_app/postgrex_types.ex
        Postgrex.Types.define(
          MyApp.PostgrexTypes,
          [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
          []
        )

    4. Configure the embedder in your config:

        # config/config.exs
        config :portfolio_index,
          embedder: PortfolioIndex.Adapters.Embedder.Gemini,
          embedding: [
            default_dimensions: #{dimension}
          ]

    5. Start using PortfolioIndex:

        # Ingest a document
        PortfolioIndex.Maintenance.diagnostics(#{repo})

    == Optional: Broadway Pipelines ==

    For async document processing, add the pipelines to your supervision tree:

        children = [
          #{repo},
          {PortfolioIndex.Pipelines.Ingestion, [repo: #{repo}]},
          {PortfolioIndex.Pipelines.Embedding, [repo: #{repo}]}
        ]

    """)
  end

  defp infer_repo do
    case Mix.Project.config()[:app] do
      nil ->
        "MyApp.Repo"

      app ->
        app
        |> to_string()
        |> Macro.camelize()
        |> Kernel.<>(".Repo")
    end
  end
end
