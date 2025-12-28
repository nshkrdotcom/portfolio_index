defmodule PortfolioIndex.RAG.Strategies.Agentic do
  @moduledoc """
  Agentic RAG strategy with tool-based retrieval.

  Uses an iterative approach:
  1. Analyze query to determine retrieval needs
  2. Use tools to gather information iteratively
  3. Self-assess gathered context
  4. Synthesize final results
  """

  @behaviour PortfolioIndex.RAG.Strategy

  @dialyzer [{:nowarn_function, retrieve: 3}]

  alias PortfolioIndex.Adapters.Embedder.Gemini, as: DefaultEmbedder
  alias PortfolioIndex.Adapters.LLM.Gemini, as: DefaultLLM
  alias PortfolioIndex.Adapters.VectorStore.Pgvector, as: DefaultVectorStore
  alias PortfolioIndex.RAG.AdapterResolver

  require Logger

  @max_iterations 5
  @default_k 5

  @impl true
  def name, do: :agentic

  @impl true
  def required_adapters, do: [:vector_store, :embedder, :llm]

  @impl true
  def retrieve(query, context, opts) do
    start_time = System.monotonic_time(:millisecond)
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)
    k = Keyword.get(opts, :k, @default_k)
    index_id = context[:index_id] || "default"
    filter = context[:filters]

    {embedder, embedder_opts} = AdapterResolver.resolve(context, :embedder, DefaultEmbedder)

    {vector_store, vector_opts} =
      AdapterResolver.resolve(context, :vector_store, DefaultVectorStore)

    vector_opts = maybe_add_filter(vector_opts, filter)
    {llm, llm_opts} = AdapterResolver.resolve(context, :llm, DefaultLLM)
    {document_store, document_opts} = AdapterResolver.resolve(context, :document_store, nil)
    store_id = context[:store_id] || Keyword.get(document_opts, :store_id, "default")

    tools =
      build_tools(
        %{embedder: embedder, embedder_opts: embedder_opts},
        %{vector_store: vector_store, vector_opts: vector_opts, index_id: index_id},
        %{document_store: document_store, document_opts: document_opts, store_id: store_id},
        k
      )

    case run_agent_loop(query, tools, llm, llm_opts, max_iter) do
      {:ok, %{items: items, iterations: iterations, tokens_used: tokens_used}} ->
        duration = System.monotonic_time(:millisecond) - start_time

        emit_telemetry(
          :retrieve,
          %{duration_ms: duration, iterations: iterations, results: length(items)},
          %{index_id: index_id}
        )

        {:ok,
         %{
           items: items,
           query: query,
           answer: nil,
           strategy: :agentic,
           timing_ms: duration,
           tokens_used: tokens_used
         }}

      {:error, reason} ->
        Logger.error("Agentic retrieval failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_tools(embedder_ctx, vector_ctx, document_ctx, k) do
    %{
      semantic_search: %{
        description: "Search for code/documents by semantic similarity",
        parameters: ["query: string (required)", "limit: integer (optional, default #{k})"],
        execute: fn args -> semantic_search_tool(args, embedder_ctx, vector_ctx, k) end
      },
      keyword_search: %{
        description: "Search for exact keyword matches in code/documents",
        parameters: ["keywords: string (required)", "limit: integer (optional)"],
        execute: fn args -> keyword_search_tool(args, vector_ctx, k) end
      },
      get_context: %{
        description: "Get surrounding context for a specific chunk ID",
        parameters: ["chunk_id: string (required)"],
        execute: fn args -> get_context_tool(args, document_ctx) end
      }
    }
  end

  defp semantic_search_tool(args, embedder_ctx, vector_ctx, default_k) do
    query = args["query"] || args[:query]
    limit = args["limit"] || args[:limit] || default_k

    with {:ok, embed_result} <- embedder_ctx.embedder.embed(query, embedder_ctx.embedder_opts),
         embedding when is_list(embedding) <- embed_result.vector || embed_result[:vector],
         {:ok, results} <-
           vector_ctx.vector_store.search(
             vector_ctx.index_id,
             embedding,
             limit,
             vector_ctx.vector_opts
           ) do
      format_search_results(results)
    else
      error ->
        Logger.warning("Semantic search failed: #{inspect(error)}")
        "Search failed: #{inspect(error)}"
    end
  end

  defp keyword_search_tool(args, vector_ctx, default_k) do
    keywords = args["keywords"] || args[:keywords]
    limit = args["limit"] || args[:limit] || default_k

    case vector_ctx.vector_store.search(
           vector_ctx.index_id,
           keywords,
           limit,
           Keyword.put(vector_ctx.vector_opts, :mode, :keyword)
         ) do
      {:ok, results} -> format_search_results(results)
      _ -> "Keyword search not available"
    end
  end

  defp get_context_tool(args, document_ctx) do
    chunk_id = args["chunk_id"] || args[:chunk_id]

    case document_ctx.document_store do
      nil ->
        "Document store not available"

      store ->
        store_id = document_ctx.store_id || "default"

        case store.get(store_id, chunk_id) do
          {:ok, doc} -> doc.content
          _ -> "Chunk not found: #{chunk_id}"
        end
    end
  end

  defp format_search_results(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {result, index} ->
      content = extract_content(result)
      id = result.id || result[:id]
      id_label = if id, do: "id=#{id} ", else: ""
      score = format_score(result.score || result[:score])

      "[#{index}] #{id_label}(score: #{score}) #{String.slice(content, 0, 200)}..."
    end)
  end

  defp format_score(score) do
    score
    |> normalize_score()
    |> Float.round(3)
  end

  defp normalize_score(%Decimal{} = score), do: Decimal.to_float(score)
  defp normalize_score(score) when is_integer(score), do: score / 1
  defp normalize_score(score) when is_float(score), do: score

  defp normalize_score(score) when is_binary(score) do
    case Float.parse(score) do
      {value, _} -> value
      :error -> 0.0
    end
  end

  defp normalize_score(_), do: 0.0

  defp extract_content(result) do
    metadata = result.metadata || result[:metadata] || %{}

    result[:content] ||
      metadata[:content] ||
      metadata["content"] ||
      metadata[:text] ||
      metadata["text"] ||
      ""
  end

  defp run_agent_loop(query, tools, llm, llm_opts, max_iter) do
    initial_state = %{
      query: query,
      gathered: [],
      iteration: 0,
      tokens_used: 0
    }

    do_loop(initial_state, tools, llm, llm_opts, max_iter)
  end

  defp do_loop(state, _tools, _llm, _llm_opts, max_iter) when state.iteration >= max_iter do
    {:ok, synthesize_results(state)}
  end

  defp do_loop(state, tools, llm, llm_opts, max_iter) do
    prompt = build_agent_prompt(state, tools)

    case llm.complete([%{role: :user, content: prompt}], llm_opts) do
      {:ok, %{content: response} = llm_response} ->
        tokens = state.tokens_used + usage_tokens(llm_response[:usage] || %{})

        case parse_agent_response(response) do
          {:tool_call, tool_name, args} ->
            result = execute_tool(tools, tool_name, args)

            new_state = %{
              state
              | gathered: state.gathered ++ [{tool_name, args, result}],
                iteration: state.iteration + 1,
                tokens_used: tokens
            }

            do_loop(new_state, tools, llm, llm_opts, max_iter)

          :done ->
            {:ok, synthesize_results(%{state | tokens_used: tokens})}

          :continue ->
            do_loop(
              %{state | iteration: state.iteration + 1, tokens_used: tokens},
              tools,
              llm,
              llm_opts,
              max_iter
            )
        end

      {:error, reason} ->
        Logger.error("Agent LLM call failed: #{inspect(reason)}")
        {:ok, synthesize_results(state)}
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
    - Search results include id=...; use that with get_context when you need full context
    - When you have enough context, respond with: {"done": true}
    - To call a tool, respond with: {"tool": "tool_name", "args": {"param": "value"}}

    What is your next action?
    """
  end

  defp format_tool_descriptions(tools) do
    tools
    |> Enum.map_join("\n", fn {name, spec} ->
      params = Enum.join(spec.parameters, ", ")
      "- #{name}: #{spec.description}\n  Parameters: #{params}"
    end)
  end

  defp format_gathered_info([]), do: "None yet - start gathering information."

  defp format_gathered_info(gathered) do
    gathered
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {{tool, args, result}, index} ->
      "[#{index}] #{tool}(#{inspect(args)})\nResult: #{String.slice(to_string(result), 0, 500)}"
    end)
  end

  defp parse_agent_response(content) do
    case extract_json(content) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"tool" => name, "args" => args}} ->
            {:tool_call, String.to_atom(name), args}

          {:ok, %{"done" => true}} ->
            :done

          _ ->
            :continue
        end

      :error ->
        if String.contains?(String.downcase(content), ["done", "sufficient", "enough"]) do
          :done
        else
          :continue
        end
    end
  end

  defp extract_json(content) do
    trimmed = String.trim(content)

    if json_wrapped?(trimmed) do
      {:ok, trimmed}
    else
      case json_bounds(content) do
        {start_idx, end_idx} ->
          {:ok, String.slice(content, start_idx..end_idx)}

        :error ->
          :error
      end
    end
  end

  defp json_wrapped?(content) do
    String.starts_with?(content, "{") and String.ends_with?(content, "}")
  end

  defp json_bounds(content) do
    case {brace_start(content), brace_end(content)} do
      {start_idx, end_idx}
      when is_integer(start_idx) and is_integer(end_idx) and end_idx >= start_idx ->
        {start_idx, end_idx}

      _ ->
        :error
    end
  end

  defp brace_start(content) do
    case :binary.match(content, "{") do
      {idx, _len} -> idx
      :nomatch -> nil
    end
  end

  defp brace_end(content) do
    case :binary.matches(content, "}") do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  defp execute_tool(tools, name, args) do
    case Map.get(tools, name) do
      nil ->
        "Unknown tool: #{name}"

      spec ->
        emit_telemetry(:tool_call, %{tool: name}, %{})
        spec.execute.(args)
    end
  end

  defp synthesize_results(state) do
    items =
      state.gathered
      |> Enum.flat_map(fn {_tool, _args, result} ->
        if is_binary(result) do
          [
            %{
              content: result,
              score: 1.0,
              source: :agentic,
              metadata: %{iteration: state.iteration}
            }
          ]
        else
          []
        end
      end)

    %{items: items, iterations: state.iteration, tokens_used: state.tokens_used}
  end

  defp usage_tokens(usage) do
    (usage[:input_tokens] || usage["input_tokens"] || 0) +
      (usage[:output_tokens] || usage["output_tokens"] || 0)
  end

  defp maybe_add_filter(vector_opts, nil), do: vector_opts
  defp maybe_add_filter(vector_opts, filter), do: Keyword.put(vector_opts, :filter, filter)

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :rag, :agentic, event],
      measurements,
      metadata
    )
  end
end
