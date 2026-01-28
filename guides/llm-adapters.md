# LLM Adapters

PortfolioIndex provides adapters for multiple LLM providers. All adapters
implement the `PortfolioCore.Ports.LLM` behaviour, providing a consistent
interface for completion and streaming.

## Available Adapters

| Adapter | Provider | Default Model | Streaming |
|---------|----------|---------------|-----------|
| `Gemini` | Google | gemini-flash-lite-latest | Yes |
| `Anthropic` | Anthropic | Claude (SDK default) | Yes |
| `OpenAI` | OpenAI | gpt-4o-mini / gpt-5-nano | Yes |
| `Codex` | OpenAI (Codex SDK) | SDK default | Yes |
| `Ollama` | Ollama (local) | llama3.2 | Yes |
| `VLLM` | vLLM (local GPU) | Qwen/Qwen2-0.5B-Instruct | Yes |

## Common Interface

All adapters share the same API:

```elixir
# Completion
{:ok, result} = Adapter.complete(messages, opts)
# result.content   -- response text
# result.model     -- model used
# result.usage     -- %{input_tokens: N, output_tokens: N}

# Streaming
{:ok, stream} = Adapter.stream(messages, opts)
stream |> Enum.each(fn chunk ->
  IO.write(chunk.delta)
end)

# Model information
Adapter.supported_models()           # list of model names
Adapter.model_info("model-name")     # %{context_window: N, ...}
```

## OpenAI Adapter

`PortfolioIndex.Adapters.LLM.OpenAI` supports both the Chat Completions API
and the newer Responses API.

### Chat Completions (default for GPT-4 models)

```elixir
alias PortfolioIndex.Adapters.LLM.OpenAI

messages = [
  %{role: :system, content: "You are a helpful assistant."},
  %{role: :user, content: "Explain pattern matching."}
]

{:ok, result} = OpenAI.complete(messages, model: "gpt-4o-mini", max_tokens: 200)
IO.puts(result.content)
```

### Responses API (default for GPT-5 models)

GPT-5 models automatically use the Responses API. You can also opt in explicitly:

```elixir
{:ok, result} = OpenAI.complete(messages,
  api: :responses,
  model: "gpt-5-nano",
  max_output_tokens: 150,
  store: true
)

IO.puts(result.content)
IO.puts("Response ID: #{result.response_id}")
```

#### API Selection

| Option | Behavior |
|--------|----------|
| `api: :responses` | Force Responses API |
| `api: :chat_completions` | Force Chat Completions API |
| `api: :auto` (or omit) | GPT-5 models use Responses, others use Chat Completions |

#### Responses API Features

- **`response_id`** -- returned in results for conversation threading
- **`previous_response_id`** -- continue from a previous response
- **`store: true`** -- persist the response server-side
- **`max_output_tokens`** -- preferred over `max_tokens` for newer models

System messages are automatically extracted into the `instructions` field.

### Streaming

```elixir
{:ok, stream} = OpenAI.stream(messages, model: "gpt-5-nano", api: :responses)

stream |> Enum.each(fn chunk ->
  IO.write(chunk.delta)
end)
```

Streaming works with both API surfaces.

Requires `OPENAI_API_KEY` environment variable.

## Anthropic (Claude) Adapter

```elixir
alias PortfolioIndex.Adapters.LLM.Anthropic

{:ok, result} = Anthropic.complete(messages, [])
{:ok, stream} = Anthropic.stream(messages, [])
```

Uses `claude_agent_sdk` under the hood. Requires `ANTHROPIC_API_KEY`.

## Codex Adapter

```elixir
alias PortfolioIndex.Adapters.LLM.Codex

{:ok, result} = Codex.complete(messages, [])
```

Uses `codex_sdk`. Requires `OPENAI_API_KEY` or `CODEX_API_KEY`.

## Gemini Adapter

```elixir
alias PortfolioIndex.Adapters.LLM.Gemini

{:ok, result} = Gemini.complete(messages, model: "gemini-flash-lite-latest")
{:ok, stream} = Gemini.stream(messages, [])
```

Requires `GEMINI_API_KEY`.

## Ollama Adapter

```elixir
alias PortfolioIndex.Adapters.LLM.Ollama

{:ok, result} = Ollama.complete(messages, model: "llama3.2")
{:ok, stream} = Ollama.stream(messages, model: "llama3.2")
```

Setup:

```bash
ollama pull llama3.2
```

Configurable via `OLLAMA_HOST` or `OLLAMA_BASE_URL`.

## vLLM Adapter

`PortfolioIndex.Adapters.LLM.VLLM` runs models locally on NVIDIA GPUs via the
`vllm` Elixir library (SnakeBridge):

```elixir
alias PortfolioIndex.Adapters.LLM.VLLM

{:ok, result} = VLLM.complete(messages,
  model: "Qwen/Qwen2-0.5B-Instruct",
  max_tokens: 128,
  temperature: 0.2,
  llm: [max_model_len: 2048, gpu_memory_utilization: 0.8]
)
```

Setup:

```bash
mix deps.get
mix snakebridge.setup
```

Requires a CUDA-capable NVIDIA GPU. Set `HF_TOKEN` for gated HuggingFace models.

## Rate Limiting

All adapters use `PortfolioIndex.Adapters.RateLimiter` for rate limiting.
Success and failure are recorded to enable backoff on rate limit errors.

## Telemetry

All adapters emit telemetry via `PortfolioIndex.Telemetry.LLM`:

```elixir
[:portfolio_index, :llm, :complete, :start | :stop | :exception]
[:portfolio_index, :llm, :stream, :start | :stop | :exception]
```

Measurements include duration, input/output token counts, and model name.

Lineage context (`trace_id`, `work_id`, `plan_id`, `step_id`) is propagated
through the `opts` parameter via `PortfolioIndex.Telemetry.Context`.

## Backend Bridge

`PortfolioIndex.LLM.BackendBridge` converts CrucibleIR backend prompt structs
into messages and options suitable for any LLM adapter:

```elixir
alias PortfolioIndex.LLM.BackendBridge

{messages, opts} = BackendBridge.prompt_to_messages(backend_prompt)
{:ok, result} = OpenAI.complete(messages, opts)
completion = BackendBridge.completion_from_result(result, messages, opts)
```
