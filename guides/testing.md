# Testing

This guide covers testing strategies for applications that use PortfolioIndex.

## Running Tests

```bash
# Unit tests (mocked, fast)
mix test

# Include integration tests (requires running services)
mix test --include integration

# Specific adapter tests
mix test test/adapters/graph_store/neo4j_test.exs --include integration
mix test test/adapters/vector_store/pgvector_test.exs --include integration

# Quality checks
mix quality    # format --check-formatted, credo --strict, dialyzer

# Full suite
mix test.all   # quality + test
```

## Test Structure

| Test Type | Tag | Services Required |
|-----------|-----|-------------------|
| Unit | (default) | None |
| Integration | `@tag :integration` | Neo4j, PostgreSQL |

Integration tests are excluded by default:

```elixir
# test/test_helper.exs
ExUnit.start(exclude: [:integration, :skip])
```

## Mock Configuration

PortfolioIndex uses [Mox](https://hex.pm/packages/mox) for mock-based testing.
Configure mock SDK modules in `config/test.exs`:

```elixir
config :portfolio_index,
  anthropic_sdk: ClaudeAgentSdkMock,
  codex_sdk: CodexSdkMock,
  gemini_sdk: GeminiSdkMock,
  ollama_sdk: OllamaSdkMock,
  vllm_sdk: VLLMSdkMock
```

Define mocks in `test/support/`:

```elixir
# test/support/llm_sdk_behaviours.ex
Mox.defmock(ClaudeAgentSdkMock, for: ClaudeAgentSDK.Behaviour)
Mox.defmock(CodexSdkMock, for: CodexSdk.Behaviour)
# ...
```

## Test Fixtures

`test/support/fixtures.ex` provides test data generators:

```elixir
alias PortfolioIndex.Fixtures

# Vector fixtures
Fixtures.random_vector(768)              # Random 768-dim vector
Fixtures.random_normalized_vector(768)   # Normalized (unit length)

# Graph fixtures
Fixtures.sample_node("node_1")           # %{id, labels, properties}
Fixtures.sample_edge("from", "to")       # %{id, type, from_id, to_id, properties}
Fixtures.sample_graph(5)                 # %{nodes: [...], edges: [...]}

# Document fixtures
Fixtures.sample_document()               # Sample markdown content
Fixtures.sample_code()                   # Sample Elixir code
Fixtures.sample_chunks(content, 3)       # Split content into chunks
```

## Integration Test Patterns

### Pgvector Tests

Use Ecto sandbox for database isolation:

```elixir
defmodule MyVectorTest do
  use ExUnit.Case, async: false

  alias PortfolioIndex.Adapters.VectorStore.Pgvector

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(PortfolioIndex.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @tag :integration
  test "stores and searches vectors" do
    index_id = "test_#{System.unique_integer([:positive])}"
    :ok = Pgvector.create_index(index_id, %{dimensions: 768})

    vector = for _ <- 1..768, do: :rand.uniform()
    :ok = Pgvector.store(index_id, "doc_1", vector, %{})

    {:ok, results} = Pgvector.search(index_id, vector, 1, [])
    assert hd(results).id == "doc_1"

    Pgvector.delete_index(index_id)
  end
end
```

### Neo4j Tests

Create isolated graph namespaces per test:

```elixir
defmodule MyNeo4jTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.GraphStore.Neo4j

  @tag :integration
  test "creates nodes" do
    graph_id = "test_#{System.unique_integer([:positive])}"
    :ok = Neo4j.create_graph(graph_id, %{})

    {:ok, node} = Neo4j.create_node(graph_id, %{
      labels: ["Test"],
      properties: %{name: "example"}
    })

    assert is_binary(node.id)

    Neo4j.delete_graph(graph_id)
  end
end
```

### LLM Adapter Tests

Mock the SDK and verify behavior:

```elixir
defmodule MyLLMTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  test "completes with OpenAI" do
    expect(OpenAISdkMock, :create, fn _client, _request ->
      {:ok, %{"choices" => [%{"message" => %{"content" => "Hello"}}],
              "model" => "gpt-5-nano",
              "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5}}}
    end)

    messages = [%{role: :user, content: "Hi"}]
    {:ok, result} = PortfolioIndex.Adapters.LLM.OpenAI.complete(messages, [])
    assert result.content == "Hello"
  end
end
```

## Coverage

```bash
# Generate coverage report
mix coveralls

# HTML report
mix coveralls.html
```

PortfolioIndex uses [ExCoveralls](https://hex.pm/packages/excoveralls) for
coverage tracking.
