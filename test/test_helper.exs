# Configure ExUnit
ExUnit.start(exclude: [:integration, :skip, :live])

# Ensure the test database exists and is migrated before running tests.
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)

case PortfolioIndex.Repo.__adapter__().storage_up(PortfolioIndex.Repo.config()) do
  :ok -> :ok
  {:error, :already_up} -> :ok
  {:error, reason} -> raise "Failed to create test database: #{inspect(reason)}"
end

{:ok, _, _} =
  Ecto.Migrator.with_repo(PortfolioIndex.Repo, fn repo ->
    Ecto.Migrator.run(repo, :up, all: true)
  end)

# Define Mox mocks for all ports
Mox.defmock(PortfolioIndex.Mocks.VectorStore, for: PortfolioCore.Ports.VectorStore)
Mox.defmock(PortfolioIndex.Mocks.GraphStore, for: PortfolioCore.Ports.GraphStore)

Mox.defmock(PortfolioIndex.Mocks.GraphStoreCommunity,
  for: PortfolioCore.Ports.GraphStore.Community
)

Mox.defmock(PortfolioIndex.Mocks.DocumentStore, for: PortfolioCore.Ports.DocumentStore)
Mox.defmock(PortfolioIndex.Mocks.Embedder, for: PortfolioCore.Ports.Embedder)
Mox.defmock(PortfolioIndex.Mocks.LLM, for: PortfolioCore.Ports.LLM)
Mox.defmock(PortfolioIndex.Mocks.Chunker, for: PortfolioCore.Ports.Chunker)
Mox.defmock(ClaudeAgentSdkMock, for: PortfolioIndex.Test.ClaudeAgentSdkBehaviour)
Mox.defmock(CodexSdkMock, for: PortfolioIndex.Test.CodexSdkBehaviour)
Mox.defmock(GeminiSdkMock, for: PortfolioIndex.Test.GeminiSdkBehaviour)
Mox.defmock(OllamaSdkMock, for: PortfolioIndex.Test.OllixirSdkBehaviour)
Mox.defmock(VLLMSdkMock, for: PortfolioIndex.Test.VLLMSdkBehaviour)

# Ensure sandbox mode for Ecto
Ecto.Adapters.SQL.Sandbox.mode(PortfolioIndex.Repo, :manual)

# Check if we should run integration tests
if System.get_env("INTEGRATION_TESTS") == "true" do
  IO.puts("\n🔌 Integration tests ENABLED\n")

  # Verify database connections for integration tests
  case PortfolioIndex.Repo.query("SELECT 1") do
    {:ok, _} -> IO.puts("  ✓ PostgreSQL connected")
    {:error, e} -> IO.puts("  ✗ PostgreSQL error: #{inspect(e)}")
  end

  case Boltx.query(Boltx, "RETURN 1") do
    {:ok, _} -> IO.puts("  ✓ Neo4j connected")
    {:error, e} -> IO.puts("  ✗ Neo4j error: #{inspect(e)}")
  end

  IO.puts("")
end
