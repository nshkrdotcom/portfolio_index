# Portfolio Index - Implementation Details

**Note:** The `portfolio_core` dependency is already updated to v0.2.0 in mix.exs.

## Adapter Implementations

### 1. Anthropic LLM (via claude_agent_sdk)

```elixir
# lib/portfolio_index/adapters/llm/anthropic.ex
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
    # Delegate to SDK if available, otherwise return known models
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

### 2. OpenAI LLM (via codex_sdk)

```elixir
# lib/portfolio_index/adapters/llm/open_ai.ex
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

### 3. GraphRAG Strategy

```elixir
# lib/portfolio_index/rag/strategies/graph_rag.ex
defmodule PortfolioIndex.RAG.Strategies.GraphRAG do
  @behaviour PortfolioCore.Ports.Retriever

  @moduledoc """
  Graph-aware RAG strategy.

  Combines vector search with knowledge graph traversal:
  1. Extract entities from query
  2. Find matching nodes in graph
  3. Traverse to related entities
  4. Aggregate community context
  5. Combine with vector results
  6. Generate answer
  """

  alias PortfolioIndex.RAG.AdapterResolver

  @default_depth 2
  @default_k 5

  @impl true
  def retrieve(query, context, opts \\ []) do
    depth = Keyword.get(opts, :depth, @default_depth)
    k = Keyword.get(opts, :k, @default_k)
    graph_id = Keyword.get(opts, :graph_id, "default")

    with {:ok, adapters} <- AdapterResolver.resolve(context),
         {:ok, entities} <- extract_entities(query, adapters.llm),
         {:ok, graph_results} <- traverse_graph(entities, graph_id, depth, adapters.graph_store),
         {:ok, vector_results} <- vector_search(query, k, adapters),
         {:ok, combined} <- combine_results(graph_results, vector_results) do
      {:ok, combined}
    end
  end

  @impl true
  def strategy_name, do: :graph_rag

  @impl true
  def required_adapters, do: [:vector_store, :embedder, :graph_store, :llm]

  # Entity Extraction

  defp extract_entities(query, llm) do
    prompt = """
    Extract key entities from this query. Return as JSON array.

    Query: #{query}

    Return format: {"entities": ["entity1", "entity2"]}
    """

    with {:ok, response} <- llm.complete([%{role: :user, content: prompt}]) do
      parse_entities(response.content)
    end
  end

  defp parse_entities(content) do
    case Jason.decode(content) do
      {:ok, %{"entities" => entities}} -> {:ok, entities}
      _ -> {:ok, []}  # Graceful fallback
    end
  end

  # Graph Traversal

  defp traverse_graph(entities, graph_id, depth, graph_store) do
    results =
      entities
      |> Enum.flat_map(fn entity ->
        case find_node(entity, graph_id, graph_store) do
          {:ok, node} -> traverse_from_node(node, depth, graph_id, graph_store)
          _ -> []
        end
      end)
      |> Enum.uniq_by(& &1.id)

    {:ok, results}
  end

  defp find_node(entity, graph_id, graph_store) do
    query = """
    MATCH (n)
    WHERE n._graph_id = $graph_id
      AND (n.name CONTAINS $entity OR n.label CONTAINS $entity)
    RETURN n
    LIMIT 1
    """

    case graph_store.query(graph_id, query, %{entity: entity, graph_id: graph_id}) do
      {:ok, [node | _]} -> {:ok, node}
      _ -> {:error, :not_found}
    end
  end

  defp traverse_from_node(node, depth, graph_id, graph_store) do
    case graph_store.get_neighbors(graph_id, node.id, depth: depth) do
      {:ok, neighbors} -> [node | neighbors]
      _ -> [node]
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

  defp combine_results(graph_results, vector_results) do
    # Convert graph nodes to searchable format
    graph_docs =
      Enum.map(graph_results, fn node ->
        %{
          id: node.id,
          content: format_node_content(node),
          score: 0.8,  # Base score for graph results
          source: :graph
        }
      end)

    # Add source to vector results
    vector_docs =
      Enum.map(vector_results, fn result ->
        Map.put(result, :source, :vector)
      end)

    # Combine and deduplicate
    combined =
      (graph_docs ++ vector_docs)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.score, :desc)

    {:ok, combined}
  end

  defp format_node_content(node) do
    """
    Entity: #{node.properties[:name] || node.id}
    Type: #{Enum.join(node.labels, ", ")}
    Properties: #{inspect(node.properties)}
    """
  end
end
```

### 4. Agentic Strategy

```elixir
# lib/portfolio_index/rag/strategies/agentic.ex
defmodule PortfolioIndex.RAG.Strategies.Agentic do
  @behaviour PortfolioCore.Ports.Retriever

  @moduledoc """
  Agentic RAG strategy with tool-based retrieval.

  Uses an iterative approach:
  1. Analyze query complexity
  2. Decompose if needed
  3. Use tools to gather information
  4. Synthesize results
  5. Self-critique and refine
  """

  alias PortfolioIndex.RAG.AdapterResolver

  @max_iterations 5

  @impl true
  def retrieve(query, context, opts \\ []) do
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)

    with {:ok, adapters} <- AdapterResolver.resolve(context) do
      tools = build_tools(adapters)
      run_agent_loop(query, tools, adapters.llm, max_iter)
    end
  end

  @impl true
  def strategy_name, do: :agentic

  @impl true
  def required_adapters, do: [:vector_store, :embedder, :llm]

  # Tools

  defp build_tools(adapters) do
    %{
      search: &search_tool(&1, adapters),
      read_context: &read_context_tool(&1, adapters),
      graph_query: &graph_query_tool(&1, adapters)
    }
  end

  defp search_tool(%{"query" => query, "limit" => limit}, adapters) do
    with {:ok, embedding} <- adapters.embedder.embed(query),
         {:ok, results} <- adapters.vector_store.search("default", embedding, limit: limit) do
      format_search_results(results)
    end
  end

  defp read_context_tool(%{"chunk_ids" => ids}, adapters) do
    results =
      Enum.map(ids, fn id ->
        case adapters.document_store.get("default", id) do
          {:ok, doc} -> doc.content
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, Enum.join(results, "\n\n")}
  end

  defp graph_query_tool(%{"entity" => entity}, adapters) do
    case adapters[:graph_store] do
      nil -> {:error, :no_graph_store}
      store ->
        query = "MATCH (n)-[r]-(m) WHERE n.name CONTAINS $entity RETURN n, r, m LIMIT 10"
        store.query("default", query, %{entity: entity})
    end
  end

  # Agent Loop

  defp run_agent_loop(query, tools, llm, max_iter) do
    initial_state = %{
      query: query,
      gathered_info: [],
      iteration: 0
    }

    do_loop(initial_state, tools, llm, max_iter)
  end

  defp do_loop(state, _tools, llm, max_iter) when state.iteration >= max_iter do
    synthesize_results(state, llm)
  end

  defp do_loop(state, tools, llm, max_iter) do
    # Ask LLM what to do next
    prompt = build_agent_prompt(state, tools)

    with {:ok, response} <- llm.complete([%{role: :user, content: prompt}]) do
      case parse_agent_response(response.content) do
        {:tool_call, tool_name, args} ->
          # Execute tool
          result = execute_tool(tools, tool_name, args)

          # Update state
          new_state = %{state |
            gathered_info: state.gathered_info ++ [{tool_name, result}],
            iteration: state.iteration + 1
          }

          do_loop(new_state, tools, llm, max_iter)

        {:final_answer, _} ->
          # Ready to synthesize
          synthesize_results(state, llm)

        :continue ->
          # No tool call, continue gathering
          do_loop(%{state | iteration: state.iteration + 1}, tools, llm, max_iter)
      end
    end
  end

  defp build_agent_prompt(state, tools) do
    tool_descriptions = format_tool_descriptions(tools)
    gathered = format_gathered_info(state.gathered_info)

    """
    You are a research agent. Your task is to gather information to answer this query:

    Query: #{state.query}

    Available tools:
    #{tool_descriptions}

    Information gathered so far:
    #{gathered}

    Respond with either:
    1. A tool call: {"tool": "tool_name", "args": {...}}
    2. Final answer ready: {"final": true}

    What's your next action?
    """
  end

  defp format_tool_descriptions(tools) do
    Enum.map_join(tools, "\n", fn {name, _func} ->
      "- #{name}: Execute #{name} operation"
    end)
  end

  defp format_gathered_info([]), do: "None yet"
  defp format_gathered_info(info) do
    Enum.map_join(info, "\n", fn {tool, result} ->
      "#{tool}: #{inspect(result, limit: 200)}"
    end)
  end

  defp parse_agent_response(content) do
    case Jason.decode(content) do
      {:ok, %{"tool" => name, "args" => args}} ->
        {:tool_call, String.to_atom(name), args}

      {:ok, %{"final" => true}} ->
        {:final_answer, nil}

      _ ->
        :continue
    end
  end

  defp execute_tool(tools, name, args) do
    case Map.get(tools, name) do
      nil -> {:error, :unknown_tool}
      func -> func.(args)
    end
  end

  defp synthesize_results(state, llm) do
    prompt = """
    Based on the gathered information, provide relevant context for this query:

    Query: #{state.query}

    Information:
    #{format_gathered_info(state.gathered_info)}

    Synthesize the most relevant pieces of information.
    """

    with {:ok, response} <- llm.complete([%{role: :user, content: prompt}]) do
      {:ok, [%{content: response.content, score: 1.0, source: :agentic}]}
    end
  end

  defp format_search_results(results) do
    results
    |> Enum.map(fn r -> "- #{r.content}" end)
    |> Enum.join("\n")
  end
end
```

## Module Structure

```
lib/portfolio_index/
├── adapters/
│   ├── embedder/
│   │   ├── gemini.ex         # Existing
│   │   └── ollama.ex         # NEW (Tier 2)
│   ├── llm/
│   │   ├── gemini.ex         # Existing
│   │   ├── anthropic.ex      # NEW - claude_agent_sdk wrapper
│   │   ├── open_ai.ex        # NEW - codex_sdk wrapper
│   │   └── ollama.ex         # NEW (Tier 2)
│   ├── vector_store/
│   │   ├── pgvector.ex       # Existing
│   │   └── qdrant.ex         # NEW (Tier 2)
│   ├── graph_store/
│   │   └── neo4j.ex          # Existing
│   ├── document_store/
│   │   └── postgres.ex       # Existing
│   ├── chunker/
│   │   ├── recursive.ex      # Existing
│   │   ├── sentence.ex       # NEW (Tier 4)
│   │   ├── paragraph.ex      # NEW (Tier 4)
│   │   └── semantic.ex       # NEW (Tier 4)
│   └── reranker/
│       └── cohere.ex         # NEW (Tier 2)
│
├── rag/
│   ├── adapter_resolver.ex   # Existing
│   ├── strategy.ex           # Existing
│   └── strategies/
│       ├── hybrid.ex         # Existing
│       ├── self_rag.ex       # Existing
│       ├── graph_rag.ex      # COMPLETE (from stub)
│       └── agentic.ex        # COMPLETE (from stub)
│
├── pipelines/
│   ├── ingestion.ex          # Existing
│   ├── embedding.ex          # Existing
│   └── producers/
│       ├── file_producer.ex  # Existing
│       └── ets_producer.ex   # Existing
│
├── infrastructure/
│   ├── cost_tracker.ex       # NEW (Tier 3)
│   ├── circuit_breaker.ex    # NEW (Tier 3)
│   └── tenant_context.ex     # NEW (Tier 3)
│
└── telemetry.ex              # Enhanced
```

## Dependencies

Add to `mix.exs`:

```elixir
defp deps do
  [
    # Existing deps...

    # LLM SDKs
    {:claude_agent_sdk, "~> 0.1"},
    {:codex_sdk, "~> 0.1"}
  ]
end
```
