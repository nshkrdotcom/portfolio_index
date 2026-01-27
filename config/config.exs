import Config

# Skip SnakeBridge compile-time introspection unless explicitly enabled.
if System.get_env("SNAKEBRIDGE_SKIP") in [nil, ""] do
  System.put_env("SNAKEBRIDGE_SKIP", "1")
end

# Base configuration for PortfolioIndex

config :portfolio_index,
  ecto_repos: [PortfolioIndex.Repo],
  env: config_env()

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :span_id, :trace_id]

# Default embedding dimensions
config :portfolio_index, :embedding, default_dimensions: 768

# LLM adapter configuration (override context/tooling defaults here if needed)

# Import environment specific config
import_config "#{config_env()}.exs"
