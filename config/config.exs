import Config

# Base configuration for PortfolioIndex

config :portfolio_index,
  ecto_repos: [PortfolioIndex.Repo]

# Hammer rate limiting backend configuration
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       expiry_ms: 60_000 * 60 * 2,
       cleanup_interval_ms: 60_000 * 10
     ]}

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :span_id, :trace_id]

# Default embedding dimensions
config :portfolio_index, :embedding, default_dimensions: 768

# LLM adapter configuration (override context/tooling defaults here if needed)

# Import environment specific config
import_config "#{config_env()}.exs"
