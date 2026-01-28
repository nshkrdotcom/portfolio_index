# Agent Sessions

PortfolioIndex provides agent session adapters for managing conversational AI
sessions with Claude and Codex providers. These adapters implement the
`PortfolioCore.Ports.AgentSession` behaviour.

## Architecture

```
PortfolioIndex.Adapters.AgentSession.Claude   (port implementation)
    |
AgentSessionManager.SessionManager            (orchestration)
    |
AgentSessionManager.Adapters.ClaudeAdapter    (provider adapter)
```

The same pattern applies for the Codex adapter with the corresponding
`CodexAdapter` provider.

## Claude Adapter

`PortfolioIndex.Adapters.AgentSession.Claude` manages sessions with Claude:

```elixir
alias PortfolioIndex.Adapters.AgentSession.Claude

# Start a session
{:ok, session_id} = Claude.start_session("my-agent", context: %{project: "demo"})

# Execute a prompt
{:ok, result} = Claude.execute(session_id, "Explain GenServer in Elixir")
IO.puts(result.output)
IO.inspect(result.token_usage)

# Cancel a running execution
{:ok, _} = Claude.cancel(session_id, run_id)

# End the session
:ok = Claude.end_session(session_id)
```

### Capabilities

```elixir
{:ok, capabilities} = Claude.capabilities()
# [
#   %{name: "streaming", type: :sampling, enabled: true},
#   %{name: "tool_use", type: :tool, enabled: true},
#   %{name: "vision", type: :resource, enabled: true},
#   %{name: "system_prompts", type: :prompt, enabled: true},
#   %{name: "interrupt", type: :sampling, enabled: true}
# ]
```

## Codex Adapter

`PortfolioIndex.Adapters.AgentSession.Codex` provides the same interface for
Codex sessions:

```elixir
alias PortfolioIndex.Adapters.AgentSession.Codex

{:ok, session_id} = Codex.start_session("my-agent")
{:ok, result} = Codex.execute(session_id, "Write a sorting function")
:ok = Codex.end_session(session_id)
```

## Configuration

Configure the session store and provider adapters in your application config:

```elixir
# config/config.exs
config :portfolio_index, :agent_session,
  store: {AgentSessionManager.Adapters.InMemorySessionStore, []},
  claude: {AgentSessionManager.Adapters.ClaudeAdapter, [model: "claude-sonnet-4-20250514"]},
  codex: {AgentSessionManager.Adapters.CodexAdapter, []}
```

`PortfolioIndex.Adapters.AgentSession.Config` resolves the store and adapter
from application config with runtime override support:

```elixir
alias PortfolioIndex.Adapters.AgentSession.Config

store = Config.resolve_store([])
adapter = Config.resolve_adapter(:claude, [])
```

## Adapter Resolution

Use `PortfolioIndex.adapter/1` to resolve the configured agent session adapter:

```elixir
adapter = PortfolioIndex.adapter(:agent_session)
# => PortfolioIndex.Adapters.AgentSession.Claude (default)
```

Override via application config:

```elixir
config :portfolio_index, :agent_session_adapter,
  PortfolioIndex.Adapters.AgentSession.Codex
```

## Input Normalization

The `execute/3` function accepts multiple input formats:

```elixir
# String input
Claude.execute(session_id, "Hello")
# Normalized to: %{prompt: "Hello"}

# Map input
Claude.execute(session_id, %{prompt: "Hello", context: %{file: "app.ex"}})
# Passed through as-is

# Arbitrary data
Claude.execute(session_id, {:analyze, file_contents})
# Normalized to: %{data: {:analyze, file_contents}}
```

## Rate Limiting

All `execute/3` calls pass through `PortfolioIndex.Adapters.RateLimiter` before
delegating to the SessionManager. Success and failure outcomes are recorded to
enable rate limit backoff.

## Telemetry

Agent session adapters emit telemetry spans:

```elixir
[:portfolio_index, :agent_session, :start_session, :start | :stop | :exception]
[:portfolio_index, :agent_session, :execute, :start | :stop | :exception]
[:portfolio_index, :agent_session, :cancel, :start | :stop | :exception]
[:portfolio_index, :agent_session, :end_session, :start | :stop | :exception]
```

Execute spans include measurements for:
- `input_tokens` -- tokens consumed by the input
- `output_tokens` -- tokens generated in the response
- `turn_count` -- number of conversation turns

All events include `%{provider: "claude" | "codex"}` in metadata.
