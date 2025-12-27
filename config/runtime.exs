import Config

# Runtime configuration - loaded at runtime, not compile time
# This is where we read environment variables

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :portfolio_index, PortfolioIndex.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # Neo4j configuration from environment
  neo4j_uri =
    System.get_env("NEO4J_URI") ||
      raise "environment variable NEO4J_URI is missing"

  neo4j_user = System.get_env("NEO4J_USER") || "neo4j"
  neo4j_password = System.get_env("NEO4J_PASSWORD") || raise "NEO4J_PASSWORD is missing"

  config :boltx, Boltx,
    name: Boltx,
    uri: neo4j_uri,
    auth: [username: neo4j_user, password: neo4j_password],
    pool_size: String.to_integer(System.get_env("NEO4J_POOL_SIZE") || "10")
end

# Gemini API configuration (all environments)
if gemini_api_key = System.get_env("GEMINI_API_KEY") do
  config :gemini_ex,
    api_key: gemini_api_key
end

# Optional: Vertex AI configuration
if vertex_project = System.get_env("VERTEX_PROJECT") do
  config :gemini_ex,
    vertex_project: vertex_project,
    vertex_location: System.get_env("VERTEX_LOCATION") || "us-central1"
end
