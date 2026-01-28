# Configuration

This guide covers all configuration options for PortfolioIndex.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection URL | -- |
| `NEO4J_URI` | Neo4j Bolt URI | `bolt://localhost:7687` |
| `NEO4J_USER` | Neo4j username | `neo4j` |
| `NEO4J_PASSWORD` | Neo4j password | -- |
| `GEMINI_API_KEY` | Google Gemini API key | -- |
| `OPENAI_API_KEY` | OpenAI API key (embeddings, LLM, Codex) | -- |
| `OPENAI_ORGANIZATION` | OpenAI organization ID | -- |
| `ANTHROPIC_API_KEY` | Anthropic API key | -- |
| `CODEX_API_KEY` | Codex SDK API key (falls back to `OPENAI_API_KEY`) | -- |
| `OLLAMA_HOST` | Ollama host URL | `http://localhost:11434` |
| `OLLAMA_BASE_URL` | Ollama base URL (override) | `http://localhost:11434/api` |
| `OLLAMA_API_KEY` | Ollama API key (optional) | -- |
| `HF_TOKEN` | HuggingFace token (gated models, vLLM) | -- |
| `SNAKEBRIDGE_SKIP` | Skip SnakeBridge compile-time setup | `1` (skipped by default) |

## Application Config

### Database

```elixir
# config/dev.exs
config :portfolio_index, PortfolioIndex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "portfolio_index_dev",
  pool_size: 10

# config/test.exs
config :portfolio_index, PortfolioIndex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "portfolio_index_test",
  pool: Ecto.Adapters.SQL.Sandbox
```

### Neo4j

```elixir
config :boltx, Boltx,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  pool_size: 10,
  name: Boltx
```

### Embedder

```elixir
# Shorthand
config :portfolio_index, :embedder, :gemini

# With module and options
config :portfolio_index, :embedder,
  {PortfolioIndex.Adapters.Embedder.OpenAI, model: "text-embedding-3-large"}
```

Available shorthands: `:openai`, `:gemini`, `:ollama`, `:bumblebee`.

### LLM

```elixir
config :portfolio_index, :llm_adapter, PortfolioIndex.Adapters.LLM.OpenAI
config :portfolio_index, :llm_model, "gpt-5-nano"
```

### Agent Sessions

```elixir
config :portfolio_index, :agent_session,
  store: {AgentSessionManager.Adapters.InMemorySessionStore, []},
  claude: {AgentSessionManager.Adapters.ClaudeAdapter, [model: "claude-sonnet-4-20250514"]},
  codex: {AgentSessionManager.Adapters.CodexAdapter, []}

config :portfolio_index, :agent_session_adapter,
  PortfolioIndex.Adapters.AgentSession.Claude
```

### SDK Injection (Testing)

For testing, inject mock SDK modules:

```elixir
# config/test.exs
config :portfolio_index,
  anthropic_sdk: ClaudeAgentSdkMock,
  codex_sdk: CodexSdkMock,
  gemini_sdk: GeminiSdkMock,
  ollama_sdk: OllamaSdkMock,
  vllm_sdk: VLLMSdkMock
```

### Application Flags

```elixir
config :portfolio_index,
  start_repo: true,          # Start Ecto repo on application boot
  start_telemetry: true,     # Start telemetry poller
  start_neo4j: false         # Start Neo4j connection (disabled by default)
```

## Runtime Config

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :portfolio_index, PortfolioIndex.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))
end
```

## Adapter Resolution

`PortfolioIndex.adapter/1` resolves adapters from config with defaults:

```elixir
PortfolioIndex.adapter(:vector_store)     # => Pgvector (default)
PortfolioIndex.adapter(:graph_store)      # => Neo4j (default)
PortfolioIndex.adapter(:embedder)         # => Gemini (default)
PortfolioIndex.adapter(:llm)              # => configured LLM adapter
PortfolioIndex.adapter(:agent_session)    # => Claude (default)
```

Override any adapter via application config:

```elixir
config :portfolio_index, :vector_store_adapter, MyApp.CustomVectorStore
```

## Local Model Setup

### Ollama

```bash
# Install models
ollama pull llama3.2           # LLM
ollama pull nomic-embed-text   # Embeddings

# Or use the setup script
mix run examples/ollama_setup.exs
```

### vLLM

Requires CUDA-capable NVIDIA GPU:

```bash
mix deps.get
mix snakebridge.setup
```

Set `HF_TOKEN` for gated HuggingFace models.
