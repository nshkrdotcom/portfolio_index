# Configure ExUnit
ExUnit.start(exclude: [:integration, :skip])

# Define Mox mocks for all ports
Mox.defmock(PortfolioIndex.Mocks.VectorStore, for: PortfolioCore.Ports.VectorStore)
Mox.defmock(PortfolioIndex.Mocks.GraphStore, for: PortfolioCore.Ports.GraphStore)
Mox.defmock(PortfolioIndex.Mocks.DocumentStore, for: PortfolioCore.Ports.DocumentStore)
Mox.defmock(PortfolioIndex.Mocks.Embedder, for: PortfolioCore.Ports.Embedder)
Mox.defmock(PortfolioIndex.Mocks.LLM, for: PortfolioCore.Ports.LLM)
Mox.defmock(PortfolioIndex.Mocks.Chunker, for: PortfolioCore.Ports.Chunker)

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
