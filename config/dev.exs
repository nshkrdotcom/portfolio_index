import Config

# Configure your database
config :portfolio_index, PortfolioIndex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "portfolio_index_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  types: PortfolioIndex.PostgrexTypes

# Neo4j configuration
config :boltx, Boltx,
  name: Boltx,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  pool_size: 10

# Enable dev logging
config :logger, level: :debug
