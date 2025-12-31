defmodule PortfolioIndex.RAG.SelfCorrectingSearch do
  @moduledoc """
  Search with self-correction loop that evaluates result sufficiency
  and rewrites queries when needed.

  ## Flow

  1. Execute initial search
  2. Evaluate if results are sufficient for answering the question
  3. If insufficient:
     a. Ask LLM to suggest a better query
     b. Execute new search
     c. Repeat until sufficient or max iterations
  4. Return results with correction history

  ## Usage

      ctx = Context.new("What is Elixir used for?")

      opts = [
        llm: &MyLLM.complete/2,
        search_fn: &MySearcher.search/2,
        max_iterations: 3
      ]

      result_ctx = SelfCorrectingSearch.search(ctx, opts)

      result_ctx.results        # Final search results
      result_ctx.correction_count  # Number of query rewrites performed

  ## Options

    - `:llm` - LLM function `fn messages, opts -> {:ok, %{content: ...}} end`
    - `:search_fn` - Search function `fn query, opts -> {:ok, [results]} end`
    - `:max_iterations` - Maximum search attempts (default: 3)
    - `:min_results` - Minimum results to consider sufficient (default: 1)
    - `:sufficiency_prompt` - Custom prompt for sufficiency evaluation
    - `:rewrite_prompt` - Custom prompt for query rewriting
  """

  alias PortfolioIndex.RAG.Pipeline.Context

  @type search_opts :: [
          max_iterations: pos_integer(),
          min_results: pos_integer(),
          sufficiency_prompt: String.t() | (String.t(), [map()] -> String.t()),
          rewrite_prompt: String.t() | (String.t(), [map()] -> String.t()),
          llm: (list(map()), keyword() -> {:ok, map()} | {:error, term()}),
          search_fn: (String.t(), keyword() -> {:ok, [map()]} | {:error, term()})
        ]

  @default_sufficiency_prompt """
  Evaluate if these search results are sufficient to answer the question.

  Question: {question}

  Search Results:
  {results}

  Respond with JSON only:
  - If results are sufficient: {"sufficient": true, "reasoning": "..."}
  - If results are insufficient: {"sufficient": false, "reasoning": "explanation of what's missing"}
  """

  @default_rewrite_prompt """
  The search query did not return sufficient results to answer the question.

  Original query: {query}
  Question: {question}

  Current results (insufficient):
  {results}

  Feedback: {feedback}

  Suggest an improved search query that will find better results.
  Return JSON only: {"query": "improved search query"}
  """

  @doc """
  Execute self-correcting search.

  Returns context with results and correction history.
  """
  # Internal state for search loop
  defmodule SearchState do
    @moduledoc false
    defstruct [
      :ctx,
      :query,
      :opts,
      :search_fn,
      :min_results,
      :max_iterations,
      :iteration,
      :history
    ]
  end

  @spec search(Context.t(), search_opts()) :: Context.t()
  def search(%Context{halted?: true} = ctx, _opts), do: ctx
  def search(%Context{error: error} = ctx, _opts) when not is_nil(error), do: ctx

  def search(%Context{} = ctx, opts) do
    state = %SearchState{
      ctx: ctx,
      query: effective_query(ctx),
      opts: opts,
      search_fn: Keyword.fetch!(opts, :search_fn),
      min_results: Keyword.get(opts, :min_results, 1),
      max_iterations: Keyword.get(opts, :max_iterations, 3),
      iteration: 0,
      history: []
    }

    do_search_loop(state)
  end

  defp do_search_loop(%SearchState{iteration: iteration, max_iterations: max} = state)
       when iteration >= max do
    # Max iterations reached, return best results
    case state.search_fn.(state.query, state.opts) do
      {:ok, results} ->
        finalize_search(state.ctx, results, iteration, state.history)

      {:error, reason} ->
        Context.halt(state.ctx, reason)
    end
  end

  defp do_search_loop(%SearchState{} = state) do
    case state.search_fn.(state.query, state.opts) do
      {:ok, results} ->
        handle_search_results(state, results)

      {:error, reason} ->
        Context.halt(state.ctx, reason)
    end
  end

  defp handle_search_results(state, results) do
    if length(results) < state.min_results do
      handle_insufficient_results(state, results, "Not enough results found")
    else
      evaluate_and_maybe_rewrite(state, results)
    end
  end

  defp evaluate_and_maybe_rewrite(state, results) do
    case evaluate_sufficiency(state.ctx.question, results, state.opts) do
      {:ok, true, _reasoning} ->
        finalize_search(state.ctx, results, state.iteration, state.history)

      {:ok, false, reasoning} ->
        handle_insufficient_results(state, results, reasoning)

      {:error, _reason} ->
        # LLM failed, assume sufficient to avoid infinite loops
        finalize_search(state.ctx, results, state.iteration, state.history)
    end
  end

  defp handle_insufficient_results(state, results, feedback) do
    case rewrite_query(state.query, results, feedback, state.opts) do
      {:ok, new_query} ->
        new_state = %{
          state
          | query: new_query,
            iteration: state.iteration + 1,
            history: [{state.query, feedback} | state.history]
        }

        do_search_loop(new_state)

      {:error, _reason} ->
        finalize_search(state.ctx, results, state.iteration, state.history)
    end
  end

  defp finalize_search(ctx, results, iteration, history) do
    %{ctx | results: results, correction_count: iteration, corrections: Enum.reverse(history)}
  end

  @doc """
  Evaluate if search results are sufficient.
  """
  @spec evaluate_sufficiency(String.t(), [map()], keyword()) ::
          {:ok, boolean(), String.t()} | {:error, term()}
  def evaluate_sufficiency(question, results, opts) do
    case Keyword.get(opts, :llm) do
      nil ->
        # No LLM provided, assume results are sufficient
        {:ok, true, "No LLM configured for sufficiency check"}

      llm ->
        custom_prompt = Keyword.get(opts, :sufficiency_prompt)

        prompt = build_sufficiency_prompt(question, results, custom_prompt)
        messages = [%{role: :user, content: prompt}]

        case llm.(messages, opts) do
          {:ok, %{content: response}} ->
            parse_sufficiency_response(response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Generate a rewritten query based on feedback.
  """
  @spec rewrite_query(String.t(), [map()], String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def rewrite_query(original_query, results, feedback, opts) do
    case Keyword.get(opts, :llm) do
      nil ->
        # No LLM provided, return original query
        {:ok, original_query}

      llm ->
        custom_prompt = Keyword.get(opts, :rewrite_prompt)
        question = Keyword.get(opts, :question, original_query)

        prompt = build_rewrite_prompt(original_query, question, results, feedback, custom_prompt)
        messages = [%{role: :user, content: prompt}]

        case llm.(messages, opts) do
          {:ok, %{content: response}} ->
            parse_rewrite_response(response, original_query)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Private functions

  defp effective_query(%Context{expanded_query: expanded}) when is_binary(expanded), do: expanded

  defp effective_query(%Context{rewritten_query: rewritten}) when is_binary(rewritten),
    do: rewritten

  defp effective_query(%Context{question: question}), do: question

  defp build_sufficiency_prompt(question, results, nil) do
    results_text = format_results(results)

    @default_sufficiency_prompt
    |> String.replace("{question}", question)
    |> String.replace("{results}", results_text)
  end

  defp build_sufficiency_prompt(question, results, custom_fn) when is_function(custom_fn, 2) do
    custom_fn.(question, results)
  end

  defp build_rewrite_prompt(query, question, results, feedback, nil) do
    results_text = format_results(results)

    @default_rewrite_prompt
    |> String.replace("{query}", query)
    |> String.replace("{question}", question)
    |> String.replace("{results}", results_text)
    |> String.replace("{feedback}", feedback || "")
  end

  defp build_rewrite_prompt(query, _question, results, feedback, custom_fn)
       when is_function(custom_fn, 3) do
    custom_fn.(query, results, feedback)
  end

  defp format_results([]), do: "No results found."

  defp format_results(results) do
    results
    |> Enum.take(5)
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {result, idx} ->
      content = result[:content] || result["content"] || ""
      truncated = String.slice(content, 0, 300)
      "[#{idx}] #{truncated}"
    end)
  end

  defp parse_sufficiency_response(response) do
    case extract_json(response) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, %{"sufficient" => true, "reasoning" => reason}} ->
            {:ok, true, reason}

          {:ok, %{"sufficient" => true}} ->
            {:ok, true, "Results are sufficient"}

          {:ok, %{"sufficient" => false, "reasoning" => reason}} ->
            {:ok, false, reason}

          {:ok, %{"sufficient" => false}} ->
            {:ok, false, nil}

          _ ->
            # Default to sufficient on parse failure
            {:ok, true, "Parse fallback"}
        end

      :error ->
        # Default to sufficient on extraction failure
        {:ok, true, "Parse fallback"}
    end
  end

  defp parse_rewrite_response(response, fallback_query) do
    case extract_json(response) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, %{"query" => query}} when is_binary(query) ->
            {:ok, query}

          _ ->
            {:ok, fallback_query}
        end

      :error ->
        {:ok, fallback_query}
    end
  end

  defp extract_json(content) do
    trimmed = String.trim(content)

    if String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") do
      {:ok, trimmed}
    else
      case Regex.run(~r/\{[^{}]*\}/, content) do
        [json] -> {:ok, json}
        nil -> :error
      end
    end
  end
end
