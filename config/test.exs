import Config

# Configure your database for tests
config :portfolio_index, PortfolioIndex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "portfolio_index_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  types: PortfolioIndex.PostgrexTypes

# Neo4j test configuration
config :boltx, Boltx,
  name: Boltx,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  pool_size: 5

# Print only warnings and errors during test
config :logger, level: :warning

# Prevent live OpenAI calls in test unless explicitly overridden.
config :portfolio_index, :openai, allow_live_api: false

# Use mocks in tests
config :portfolio_index,
  vector_store: PortfolioIndex.Mocks.VectorStore,
  graph_store: PortfolioIndex.Mocks.GraphStore,
  embedder: PortfolioIndex.Mocks.Embedder,
  llm: PortfolioIndex.Mocks.LLM,
  anthropic_sdk: ClaudeAgentSdkMock,
  codex_sdk: CodexSdkMock,
  gemini_sdk: GeminiSdkMock,
  ollama_sdk: OllamaSdkMock
