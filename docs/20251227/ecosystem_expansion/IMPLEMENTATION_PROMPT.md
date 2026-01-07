# Portfolio Index v0.2.0 Implementation Prompt

## Mission

Implement LLM adapters using SDK wrappers (claude_agent_sdk, codex_sdk), complete GraphRAG and Agentic strategies. Use TDD. All tests passing, no warnings, no dialyzer errors, credo --strict clean.

**Note:** The `portfolio_core` dependency is already updated to v0.2.0 in mix.exs.

---

## Required Reading

### Documentation (Read First)
```
docs/20251227/ecosystem_expansion/01_current_state.md
docs/20251227/ecosystem_expansion/02_expansion_roadmap.md
docs/20251227/ecosystem_expansion/03_implementation_details.md
```

### Source Files - Adapters (Understand Patterns)
```
lib/portfolio_index.ex
lib/portfolio_index/application.ex
lib/portfolio_index/repo.ex
lib/portfolio_index/telemetry.ex

lib/portfolio_index/adapters/vector_store/pgvector.ex
lib/portfolio_index/adapters/graph_store/neo4j.ex
lib/portfolio_index/adapters/document_store/postgres.ex
lib/portfolio_index/adapters/embedder/gemini.ex
lib/portfolio_index/adapters/llm/gemini.ex
lib/portfolio_index/adapters/chunker/recursive.ex
```

### Source Files - RAG Strategies
```
lib/portfolio_index/rag/strategy.ex
lib/portfolio_index/rag/adapter_resolver.ex
lib/portfolio_index/rag/strategies/hybrid.ex
lib/portfolio_index/rag/strategies/self_rag.ex
lib/portfolio_index/rag/strategies/graph_rag.ex   # Stub to complete
lib/portfolio_index/rag/strategies/agentic.ex     # Stub to complete
```

### Source Files - Pipelines
```
lib/portfolio_index/pipelines/ingestion.ex
lib/portfolio_index/pipelines/embedding.ex
lib/portfolio_index/pipelines/producers/file_producer.ex
lib/portfolio_index/pipelines/producers/ets_producer.ex
```

### Test Files (Match Patterns)
```
test/test_helper.exs
test/adapters/pgvector_test.exs
test/adapters/neo4j_test.exs
test/adapters/gemini_embedder_test.exs
test/adapters/gemini_llm_test.exs
test/rag/hybrid_test.exs
test/rag/self_rag_test.exs
```

### Configuration
```
mix.exs
config/config.exs
config/dev.exs
config/test.exs
README.md
CHANGELOG.md
```

---

## Implementation Tasks

### Task 1: Add SDK Dependencies

Update `mix.exs` to add LLM SDK dependencies:

```elixir
defp deps do
  [
    # Existing deps...

    # LLM SDKs - use latest versions from Hex
    {:claude_agent_sdk, "~> 0.1"},
    {:codex_sdk, "~> 0.1"}
  ]
end
```

Run: `mix deps.get`

### Task 2: Implement Anthropic LLM (claude_agent_sdk wrapper)

Create `lib/portfolio_index/adapters/llm/anthropic.ex`:

```elixir
defmodule PortfolioIndex.Adapters.LLM.Anthropic do
  @behaviour PortfolioCore.Ports.LLM

  @moduledoc """
  Anthropic Claude LLM adapter using claude_agent_sdk.

  This is a thin wrapper around the claude_agent_sdk Hex library.
  Uses the SDK's default model unless overridden via opts.

  ## Configuration

      config :portfolio_index, :anthropic,
        model: nil  # Uses SDK default, or specify override

  ## Manifest

      adapters:
        llm:
          module: PortfolioIndex.Adapters.LLM.Anthropic
          config:
            model: null  # Uses SDK default
  """

  require Logger

  @impl true
  def complete(messages, opts \\ []) do
    model = Keyword.get(opts, :model, configured_model())
    max_tokens = Keyword.get(opts, :max_tokens)
    system = Keyword.get(opts, :system)

    sdk_opts =
      []
      |> maybe_add(:model, model)
      |> maybe_add(:max_tokens, max_tokens)
      |> maybe_add(:system, system)

    converted_messages = convert_messages(messages)

    with {:ok, response} <- ClaudeAgentSdk.complete(converted_messages, sdk_opts) do
      emit_telemetry(:complete, %{model: response.model})
      {:ok, normalize_response(response)}
    end
  end

  @impl true
  def stream(messages, callback, opts \\ []) when is_function(callback, 1) do
    model = Keyword.get(opts, :model, configured_model())
    max_tokens = Keyword.get(opts, :max_tokens)
    system = Keyword.get(opts, :system)

    sdk_opts =
      []
      |> maybe_add(:model, model)
      |> maybe_add(:max_tokens, max_tokens)
      |> maybe_add(:system, system)

    converted_messages = convert_messages(messages)

    ClaudeAgentSdk.stream(converted_messages, callback, sdk_opts)
  end

  @impl true
  def supported_models do
    case function_exported?(ClaudeAgentSdk, :supported_models, 0) do
      true -> ClaudeAgentSdk.supported_models()
      false -> ["claude-sonnet-4-20250514", "claude-opus-4-20250514", "claude-3-haiku-20240307"]
    end
  end

  @impl true
  def model_info(model) do
    case function_exported?(ClaudeAgentSdk, :model_info, 1) do
      true -> ClaudeAgentSdk.model_info(model)
      false -> {:error, :not_available}
    end
  end

  # Private

  defp convert_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} ->
        %{role: to_string(role), content: content}

      %{"role" => role, "content" => content} ->
        %{role: role, content: content}

      msg when is_map(msg) ->
        msg
    end)
  end

  defp normalize_response(response) do
    %{
      content: response.content,
      model: response.model,
      stop_reason: Map.get(response, :stop_reason),
      usage: Map.get(response, :usage, %{})
    }
  end

  defp configured_model do
    Application.get_env(:portfolio_index, :anthropic)[:model]
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:portfolio_index, :llm, :anthropic, event],
      %{count: 1},
      metadata
    )
  end
end
```

### Task 3: Implement OpenAI LLM (codex_sdk wrapper)

Create `lib/portfolio_index/adapters/llm/open_ai.ex`:

```elixir
defmodule PortfolioIndex.Adapters.LLM.OpenAI do
  @behaviour PortfolioCore.Ports.LLM

  @moduledoc """
  OpenAI GPT LLM adapter using codex_sdk.

  This is a thin wrapper around the codex_sdk Hex library.
  Uses the SDK's default model unless overridden via opts.

  ## Configuration

      config :portfolio_index, :openai,
        model: nil  # Uses SDK default, or specify override

  ## Manifest

      adapters:
        llm:
          module: PortfolioIndex.Adapters.LLM.OpenAI
          config:
            model: null  # Uses SDK default
  """

  require Logger

  @impl true
  def complete(messages, opts \\ []) do
    model = Keyword.get(opts, :model, configured_model())
    max_tokens = Keyword.get(opts, :max_tokens)

    sdk_opts =
      []
      |> maybe_add(:model, model)
      |> maybe_add(:max_tokens, max_tokens)

    converted_messages = convert_messages(messages)

    with {:ok, response} <- CodexSdk.complete(converted_messages, sdk_opts) do
      emit_telemetry(:complete, %{model: response.model})
      {:ok, normalize_response(response)}
    end
  end

  @impl true
  def stream(messages, callback, opts \\ []) when is_function(callback, 1) do
    model = Keyword.get(opts, :model, configured_model())
    max_tokens = Keyword.get(opts, :max_tokens)

    sdk_opts =
      []
      |> maybe_add(:model, model)
      |> maybe_add(:max_tokens, max_tokens)

    converted_messages = convert_messages(messages)

    CodexSdk.stream(converted_messages, callback, sdk_opts)
  end

  @impl true
  def supported_models do
    case function_exported?(CodexSdk, :supported_models, 0) do
      true -> CodexSdk.supported_models()
      false -> ["gpt-4o", "gpt-4-turbo", "o1", "o3-mini"]
    end
  end

  @impl true
  def model_info(model) do
    case function_exported?(CodexSdk, :model_info, 1) do
      true -> CodexSdk.model_info(model)
      false -> {:error, :not_available}
    end
  end

  # Private

  defp convert_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} ->
        %{role: to_string(role), content: content}

      %{"role" => role, "content" => content} ->
        %{role: role, content: content}

      msg when is_map(msg) ->
        msg
    end)
  end

  defp normalize_response(response) do
    %{
      content: response.content,
      model: response.model,
      stop_reason: Map.get(response, :stop_reason),
      usage: Map.get(response, :usage, %{})
    }
  end

  defp configured_model do
    Application.get_env(:portfolio_index, :openai)[:model]
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:portfolio_index, :llm, :openai, event],
      %{count: 1},
      metadata
    )
  end
end
```

### Task 4: Complete GraphRAG Strategy

Replace stub in `lib/portfolio_index/rag/strategies/graph_rag.ex`:

```elixir
defmodule PortfolioIndex.RAG.Strategies.GraphRAG do
  @behaviour PortfolioCore.Ports.Retriever

  @moduledoc """
  Graph-aware RAG strategy.

  Combines vector similarity search with knowledge graph traversal:
  1. Extract entities from query
  2. Find matching nodes in graph
  3. Traverse to related entities
  4. Aggregate context from graph
  5. Combine with vector search results
  6. Return unified results
  """

  alias PortfolioIndex.RAG.AdapterResolver

  require Logger

  @default_depth 2
  @default_k 5
  @default_graph_id "default"

  @impl true
  def retrieve(query, context, opts \\ []) do
    depth = Keyword.get(opts, :depth, @default_depth)
    k = Keyword.get(opts, :k, @default_k)
    graph_id = Keyword.get(opts, :graph_id, @default_graph_id)

    with {:ok, adapters} <- AdapterResolver.resolve(context),
         {:ok, entities} <- extract_entities(query, adapters),
         {:ok, graph_results} <- traverse_graph(entities, graph_id, depth, adapters),
         {:ok, vector_results} <- vector_search(query, k, adapters) do
      combined = combine_results(graph_results, vector_results, opts)
      emit_telemetry(:retrieve, %{graph_count: length(graph_results), vector_count: length(vector_results)})
      {:ok, combined}
    end
  end

  @impl true
  def strategy_name, do: :graph_rag

  @impl true
  def required_adapters, do: [:vector_store, :embedder, :graph_store, :llm]

  # Entity Extraction

  defp extract_entities(query, adapters) do
    prompt = """
    Extract key entities (functions, modules, classes, concepts) from this query.
    Return as JSON: {"entities": ["entity1", "entity2"]}

    Query: #{query}
    """

    case adapters.llm.complete([%{role: :user, content: prompt}]) do
      {:ok, %{content: content}} ->
        parse_entities(content)

      {:error, reason} ->
        Logger.warning("Entity extraction failed: #{inspect(reason)}")
        {:ok, []}  # Graceful fallback
    end
  end

  defp parse_entities(content) do
    # Try to extract JSON from response
    case Regex.run(~r/\{[^}]+\}/, content) do
      [json] ->
        case Jason.decode(json) do
          {:ok, %{"entities" => entities}} when is_list(entities) ->
            {:ok, entities}
          _ ->
            {:ok, []}
        end
      _ ->
        {:ok, []}
    end
  end

  # Graph Traversal

  defp traverse_graph([], _graph_id, _depth, _adapters), do: {:ok, []}

  defp traverse_graph(entities, graph_id, depth, adapters) do
    graph_store = adapters.graph_store

    results =
      entities
      |> Task.async_stream(fn entity ->
        case find_node(entity, graph_id, graph_store) do
          {:ok, node} ->
            neighbors = get_neighbors(node, graph_id, depth, graph_store)
            [node | neighbors]
          _ ->
            []
        end
      end, max_concurrency: 4, timeout: 10_000)
      |> Enum.flat_map(fn
        {:ok, nodes} -> nodes
        _ -> []
      end)
      |> Enum.uniq_by(& &1.id)

    {:ok, results}
  end

  defp find_node(entity, graph_id, graph_store) do
    # Search by name or label containing entity
    query = """
    MATCH (n)
    WHERE n._graph_id = $graph_id
      AND (toLower(n.name) CONTAINS toLower($entity)
           OR toLower(n.label) CONTAINS toLower($entity))
    RETURN n
    LIMIT 1
    """

    case graph_store.query(graph_id, query, %{entity: entity, graph_id: graph_id}) do
      {:ok, [node | _]} -> {:ok, node}
      {:ok, []} -> {:error, :not_found}
      error -> error
    end
  end

  defp get_neighbors(node, graph_id, depth, graph_store) do
    case graph_store.get_neighbors(graph_id, node.id, depth: depth) do
      {:ok, neighbors} -> neighbors
      _ -> []
    end
  end

  # Vector Search

  defp vector_search(query, k, adapters) do
    with {:ok, embedding} <- adapters.embedder.embed(query),
         {:ok, results} <- adapters.vector_store.search("default", embedding, limit: k) do
      {:ok, results}
    end
  end

  # Result Combination

  defp combine_results(graph_results, vector_results, opts) do
    graph_weight = Keyword.get(opts, :graph_weight, 0.4)
    vector_weight = Keyword.get(opts, :vector_weight, 0.6)

    # Convert graph nodes to result format
    graph_docs =
      Enum.map(graph_results, fn node ->
        %{
          id: "graph:#{node.id}",
          content: format_node_content(node),
          score: graph_weight,
          source: :graph,
          metadata: %{
            labels: node.labels,
            properties: node.properties
          }
        }
      end)

    # Add source to vector results and adjust score
    vector_docs =
      Enum.map(vector_results, fn result ->
        result
        |> Map.put(:source, :vector)
        |> Map.update(:score, 0, &(&1 * vector_weight))
      end)

    # Combine, deduplicate by content similarity, and sort
    (graph_docs ++ vector_docs)
    |> deduplicate_results()
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp format_node_content(node) do
    name = node.properties[:name] || node.properties["name"] || node.id
    labels = Enum.join(node.labels || [], ", ")

    props =
      node.properties
      |> Map.drop([:name, "name", :_graph_id, "_graph_id"])
      |> Enum.map(fn {k, v} -> "  #{k}: #{inspect(v)}" end)
      |> Enum.join("\n")

    """
    [#{labels}] #{name}
    #{props}
    """
  end

  defp deduplicate_results(results) do
    # Simple dedup by ID prefix
    results
    |> Enum.reduce(%{}, fn result, acc ->
      key = result.id
      case Map.get(acc, key) do
        nil -> Map.put(acc, key, result)
        existing when existing.score < result.score -> Map.put(acc, key, result)
        _ -> acc
      end
    end)
    |> Map.values()
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:portfolio_index, :rag, :graph_rag, event],
      %{count: 1},
      metadata
    )
  end
end
```

### Task 5: Complete Agentic Strategy

Replace stub in `lib/portfolio_index/rag/strategies/agentic.ex`:

```elixir
defmodule PortfolioIndex.RAG.Strategies.Agentic do
  @behaviour PortfolioCore.Ports.Retriever

  @moduledoc """
  Agentic RAG strategy with tool-based retrieval.

  Uses an iterative approach:
  1. Analyze query to determine retrieval needs
  2. Use tools to gather information iteratively
  3. Self-assess gathered context
  4. Synthesize final results
  """

  alias PortfolioIndex.RAG.AdapterResolver

  require Logger

  @max_iterations 5
  @default_k 5

  @impl true
  def retrieve(query, context, opts \\ []) do
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)
    k = Keyword.get(opts, :k, @default_k)

    with {:ok, adapters} <- AdapterResolver.resolve(context) do
      tools = build_tools(adapters, k)
      run_agent_loop(query, tools, adapters.llm, max_iter)
    end
  end

  @impl true
  def strategy_name, do: :agentic

  @impl true
  def required_adapters, do: [:vector_store, :embedder, :llm]

  # Tool Definitions

  defp build_tools(adapters, k) do
    %{
      semantic_search: %{
        description: "Search for code/documents by semantic similarity",
        parameters: ["query: string (required)", "limit: integer (optional, default #{k})"],
        execute: fn args -> semantic_search_tool(args, adapters, k) end
      },
      keyword_search: %{
        description: "Search for exact keyword matches in code/documents",
        parameters: ["keywords: string (required)", "limit: integer (optional)"],
        execute: fn args -> keyword_search_tool(args, adapters, k) end
      },
      get_context: %{
        description: "Get surrounding context for a specific chunk ID",
        parameters: ["chunk_id: string (required)"],
        execute: fn args -> get_context_tool(args, adapters) end
      }
    }
  end

  defp semantic_search_tool(args, adapters, default_k) do
    query = args["query"] || args[:query]
    limit = args["limit"] || args[:limit] || default_k

    with {:ok, embedding} <- adapters.embedder.embed(query),
         {:ok, results} <- adapters.vector_store.search("default", embedding, limit: limit) do
      format_search_results(results)
    else
      error ->
        Logger.warning("Semantic search failed: #{inspect(error)}")
        "Search failed: #{inspect(error)}"
    end
  end

  defp keyword_search_tool(args, adapters, default_k) do
    keywords = args["keywords"] || args[:keywords]
    limit = args["limit"] || args[:limit] || default_k

    # Use vector store's keyword search if available
    case adapters.vector_store.search("default", keywords, limit: limit, mode: :keyword) do
      {:ok, results} -> format_search_results(results)
      _ -> "Keyword search not available"
    end
  end

  defp get_context_tool(args, adapters) do
    chunk_id = args["chunk_id"] || args[:chunk_id]

    case adapters[:document_store] do
      nil -> "Document store not available"
      store ->
        case store.get("default", chunk_id) do
          {:ok, doc} -> doc.content
          _ -> "Chunk not found: #{chunk_id}"
        end
    end
  end

  defp format_search_results(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map(fn {r, i} ->
      "[#{i}] (score: #{Float.round(r.score, 3)}) #{String.slice(r.content, 0, 200)}..."
    end)
    |> Enum.join("\n\n")
  end

  # Agent Loop

  defp run_agent_loop(query, tools, llm, max_iter) do
    initial_state = %{
      query: query,
      gathered: [],
      iteration: 0
    }

    case do_loop(initial_state, tools, llm, max_iter) do
      {:ok, results} -> {:ok, results}
      {:error, _} = error -> error
    end
  end

  defp do_loop(state, _tools, _llm, max_iter) when state.iteration >= max_iter do
    synthesize_results(state)
  end

  defp do_loop(state, tools, llm, max_iter) do
    prompt = build_agent_prompt(state, tools)

    case llm.complete([%{role: :user, content: prompt}]) do
      {:ok, %{content: response}} ->
        case parse_agent_response(response) do
          {:tool_call, tool_name, args} ->
            result = execute_tool(tools, tool_name, args)
            new_state = %{state |
              gathered: state.gathered ++ [{tool_name, args, result}],
              iteration: state.iteration + 1
            }
            do_loop(new_state, tools, llm, max_iter)

          :done ->
            synthesize_results(state)

          :continue ->
            do_loop(%{state | iteration: state.iteration + 1}, tools, llm, max_iter)
        end

      {:error, reason} ->
        Logger.error("Agent LLM call failed: #{inspect(reason)}")
        synthesize_results(state)
    end
  end

  defp build_agent_prompt(state, tools) do
    tool_desc = format_tool_descriptions(tools)
    gathered = format_gathered_info(state.gathered)

    """
    You are a retrieval agent. Your task is to gather relevant information for this query:

    QUERY: #{state.query}

    AVAILABLE TOOLS:
    #{tool_desc}

    INFORMATION GATHERED SO FAR:
    #{gathered}

    INSTRUCTIONS:
    - Use tools to find relevant information
    - Call one tool at a time
    - When you have enough context, respond with: {"done": true}
    - To call a tool, respond with: {"tool": "tool_name", "args": {"param": "value"}}

    What is your next action?
    """
  end

  defp format_tool_descriptions(tools) do
    tools
    |> Enum.map(fn {name, spec} ->
      params = Enum.join(spec.parameters, ", ")
      "- #{name}: #{spec.description}\n  Parameters: #{params}"
    end)
    |> Enum.join("\n")
  end

  defp format_gathered_info([]), do: "None yet - start gathering information."

  defp format_gathered_info(gathered) do
    gathered
    |> Enum.with_index(1)
    |> Enum.map(fn {{tool, args, result}, i} ->
      "[#{i}] #{tool}(#{inspect(args)})\nResult: #{String.slice(to_string(result), 0, 500)}"
    end)
    |> Enum.join("\n\n")
  end

  defp parse_agent_response(content) do
    # Try to find JSON in response
    case Regex.run(~r/\{[^{}]+\}/, content) do
      [json] ->
        case Jason.decode(json) do
          {:ok, %{"tool" => name, "args" => args}} ->
            {:tool_call, String.to_atom(name), args}

          {:ok, %{"done" => true}} ->
            :done

          _ ->
            :continue
        end
      _ ->
        if String.contains?(String.downcase(content), ["done", "sufficient", "enough"]) do
          :done
        else
          :continue
        end
    end
  end

  defp execute_tool(tools, name, args) do
    case Map.get(tools, name) do
      nil ->
        "Unknown tool: #{name}"
      spec ->
        emit_telemetry(:tool_call, %{tool: name})
        spec.execute.(args)
    end
  end

  defp synthesize_results(state) do
    # Convert gathered information to result format
    results =
      state.gathered
      |> Enum.flat_map(fn {_tool, _args, result} when is_binary(result) ->
        # Parse results back into structured format
        [%{
          id: "agentic:#{:erlang.phash2(result)}",
          content: result,
          score: 1.0,
          source: :agentic,
          metadata: %{iteration: state.iteration}
        }]

        {_tool, _args, _other} ->
          []
      end)

    emit_telemetry(:retrieve, %{iterations: state.iteration, results: length(results)})
    {:ok, results}
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:portfolio_index, :rag, :agentic, event],
      %{count: 1},
      metadata
    )
  end
end
```

---

## TDD Process

### Step 1: Write Tests First

Create test files for each new/updated adapter:

```
test/adapters/anthropic_llm_test.exs
test/adapters/openai_llm_test.exs
test/rag/graph_rag_test.exs
test/rag/agentic_test.exs
```

#### test/adapters/anthropic_llm_test.exs

```elixir
defmodule PortfolioIndex.Adapters.LLM.AnthropicTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.LLM.Anthropic

  import Mox

  setup :verify_on_exit!

  describe "complete/2" do
    test "delegates to claude_agent_sdk" do
      # Mock the SDK call
      expect(ClaudeAgentSdkMock, :complete, fn messages, _opts ->
        assert length(messages) == 1
        {:ok, %{content: "Hello!", model: "claude-sonnet-4-20250514", usage: %{}}}
      end)

      {:ok, response} = Anthropic.complete([%{role: :user, content: "Hi"}])

      assert response.content == "Hello!"
      assert response.model == "claude-sonnet-4-20250514"
    end

    test "passes model override via opts" do
      expect(ClaudeAgentSdkMock, :complete, fn _messages, opts ->
        assert Keyword.get(opts, :model) == "claude-opus-4-20250514"
        {:ok, %{content: "Hi", model: "claude-opus-4-20250514", usage: %{}}}
      end)

      Anthropic.complete([%{role: :user, content: "Hi"}], model: "claude-opus-4-20250514")
    end
  end

  describe "supported_models/0" do
    test "returns list of models" do
      models = Anthropic.supported_models()
      assert is_list(models)
      assert length(models) > 0
    end
  end
end
```

#### test/adapters/openai_llm_test.exs

```elixir
defmodule PortfolioIndex.Adapters.LLM.OpenAITest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.LLM.OpenAI

  import Mox

  setup :verify_on_exit!

  describe "complete/2" do
    test "delegates to codex_sdk" do
      expect(CodexSdkMock, :complete, fn messages, _opts ->
        assert length(messages) == 1
        {:ok, %{content: "Hello!", model: "gpt-4o", usage: %{}}}
      end)

      {:ok, response} = OpenAI.complete([%{role: :user, content: "Hi"}])

      assert response.content == "Hello!"
      assert response.model == "gpt-4o"
    end

    test "passes model override via opts" do
      expect(CodexSdkMock, :complete, fn _messages, opts ->
        assert Keyword.get(opts, :model) == "o1"
        {:ok, %{content: "Hi", model: "o1", usage: %{}}}
      end)

      OpenAI.complete([%{role: :user, content: "Hi"}], model: "o1")
    end
  end

  describe "supported_models/0" do
    test "returns list of models" do
      models = OpenAI.supported_models()
      assert is_list(models)
      assert length(models) > 0
    end
  end
end
```

#### test/rag/graph_rag_test.exs

```elixir
defmodule PortfolioIndex.RAG.Strategies.GraphRAGTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.RAG.Strategies.GraphRAG

  import Mox

  setup :verify_on_exit!

  describe "retrieve/3" do
    test "combines graph and vector results" do
      # Setup mocks
      expect(MockEmbedder, :embed, fn _query -> {:ok, List.duplicate(0.1, 768)} end)
      expect(MockVectorStore, :search, fn _idx, _vec, _opts ->
        {:ok, [%{id: "v1", content: "Vector result", score: 0.9}]}
      end)
      expect(MockGraphStore, :query, fn _gid, _q, _p -> {:ok, []} end)
      expect(MockLLM, :complete, fn _msgs -> {:ok, %{content: ~s({"entities": []})}} end)

      context = %{
        embedder: MockEmbedder,
        vector_store: MockVectorStore,
        graph_store: MockGraphStore,
        llm: MockLLM
      }

      {:ok, results} = GraphRAG.retrieve("test query", context)

      assert length(results) >= 1
      assert Enum.any?(results, &(&1.source == :vector))
    end
  end

  describe "strategy_name/0" do
    test "returns :graph_rag" do
      assert GraphRAG.strategy_name() == :graph_rag
    end
  end

  describe "required_adapters/0" do
    test "requires all necessary adapters" do
      adapters = GraphRAG.required_adapters()

      assert :vector_store in adapters
      assert :embedder in adapters
      assert :graph_store in adapters
      assert :llm in adapters
    end
  end
end
```

### Step 2: Run Tests

```bash
# Unit tests (mocked)
mix test

# Integration tests (requires API keys)
mix test --include integration
```

---

## Documentation Updates

### README.md

Add new sections:

```markdown
## Adapters

### Embedders
- **Gemini** - Google Gemini text-embedding-004

### LLMs
- **Gemini** - gemini-flash-lite-latest with streaming
- **Anthropic** - Claude via claude_agent_sdk (NEW v0.2.0)
- **OpenAI** - GPT/o1 via codex_sdk (NEW v0.2.0)

### RAG Strategies
- **Hybrid** - Vector + keyword with RRF fusion
- **SelfRAG** - Self-critique and refinement
- **GraphRAG** - Graph-aware retrieval (NEW v0.2.0)
- **Agentic** - Tool-based iterative retrieval (NEW v0.2.0)
```

### CHANGELOG.md

```markdown
# Changelog

## [0.2.0] - 2025-12-27

### Added
- Anthropic LLM adapter via claude_agent_sdk with streaming
- OpenAI LLM adapter via codex_sdk with streaming
- GraphRAG strategy - combines vector search with graph traversal
- Agentic strategy - tool-based iterative retrieval
- Telemetry events for new adapters and strategies

### Changed
- AdapterResolver now supports dynamic context-based resolution
- Improved error handling in all strategies

### Dependencies
- Added claude_agent_sdk ~> 0.1
- Added codex_sdk ~> 0.1
- Updated portfolio_core to 0.2.0
```

### Examples

Create examples:

```
examples/anthropic_llm.exs
examples/openai_llm.exs
examples/graph_rag.exs
examples/agentic_rag.exs
```

#### examples/run_all.sh

```bash
#!/bin/bash
set -e

echo "=== Portfolio Index Examples ==="
echo ""

echo "1. Pgvector Vector Store"
mix run examples/pgvector_usage.exs
echo ""

echo "2. Neo4j Graph Store"
mix run examples/neo4j_usage.exs
echo ""

echo "3. Gemini Embedder"
mix run examples/gemini_embedder.exs
echo ""

echo "4. Anthropic LLM (v0.2.0)"
mix run examples/anthropic_llm.exs
echo ""

echo "5. OpenAI LLM (v0.2.0)"
mix run examples/openai_llm.exs
echo ""

echo "6. Hybrid RAG"
mix run examples/hybrid_rag.exs
echo ""

echo "7. GraphRAG (v0.2.0)"
mix run examples/graph_rag.exs
echo ""

echo "8. Agentic RAG (v0.2.0)"
mix run examples/agentic_rag.exs
echo ""

echo "=== All examples completed successfully ==="
```

---

## Version Bump

### mix.exs
```elixir
def project do
  [
    app: :portfolio_index,
    version: "0.2.0",
    # ...
  ]
end
```

---

## Quality Gates

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
mix test --cover
mix docs
```

### Acceptance Criteria

- [ ] SDK dependencies added (claude_agent_sdk, codex_sdk)
- [ ] Anthropic LLM wrapper implemented (delegates to claude_agent_sdk)
- [ ] OpenAI LLM wrapper implemented (delegates to codex_sdk)
- [ ] GraphRAG strategy complete with entity extraction
- [ ] Agentic strategy complete with tool execution
- [ ] All tests passing (unit + integration)
- [ ] No compiler warnings
- [ ] No dialyzer errors
- [ ] Credo --strict passes
- [ ] README updated
- [ ] CHANGELOG updated for v0.2.0
- [ ] All examples work
- [ ] examples/run_all.sh succeeds
- [ ] Version bumped to 0.2.0

---

## File Checklist

### Modified Files
- [ ] `mix.exs` - Version bump + SDK deps (claude_agent_sdk, codex_sdk)
- [ ] `lib/portfolio_index/rag/strategies/graph_rag.ex` - Complete implementation
- [ ] `lib/portfolio_index/rag/strategies/agentic.ex` - Complete implementation
- [ ] `README.md`
- [ ] `CHANGELOG.md`

### New Files
- [ ] `lib/portfolio_index/adapters/llm/anthropic.ex` - claude_agent_sdk wrapper
- [ ] `lib/portfolio_index/adapters/llm/open_ai.ex` - codex_sdk wrapper
- [ ] `test/adapters/anthropic_llm_test.exs`
- [ ] `test/adapters/openai_llm_test.exs`
- [ ] `test/rag/graph_rag_test.exs`
- [ ] `test/rag/agentic_test.exs`
- [ ] `examples/anthropic_llm.exs`
- [ ] `examples/openai_llm.exs`
- [ ] `examples/graph_rag.exs`
- [ ] `examples/agentic_rag.exs`
- [ ] `examples/README.md`
- [ ] `examples/run_all.sh`
