defmodule PortfolioIndex.Telemetry.RAG do
  @moduledoc """
  RAG pipeline telemetry for tracking each step.

  Provides utilities for wrapping RAG pipeline operations with telemetry instrumentation.

  ## Usage

      alias PortfolioIndex.Telemetry.RAG
      alias PortfolioIndex.RAG.Pipeline.Context

      # Wrap a pipeline step
      RAG.step_span(:rewrite, ctx, fn ctx ->
        QueryProcessor.rewrite(ctx)
      end)

      # Wrap search specifically
      RAG.search_span(ctx, [mode: :hybrid, collections: ["docs"]], fn ->
        do_search()
      end)

  ## Pipeline Steps

  The following steps are tracked:
  - `:rewrite` - Query rewriting
  - `:expand` - Query expansion
  - `:decompose` - Query decomposition
  - `:select` - Index/collection selection
  - `:search` - Vector search
  - `:rerank` - Result reranking
  - `:answer` - Answer generation
  - `:self_correct` - Self-correction loop
  """

  alias PortfolioIndex.RAG.Pipeline.Context

  @pipeline_steps [
    :rewrite,
    :expand,
    :decompose,
    :select,
    :search,
    :rerank,
    :answer,
    :self_correct
  ]

  @doc """
  Wrap a pipeline step with telemetry.

  Emits `[:portfolio, :rag, <step>, :start]`, `[:portfolio, :rag, <step>, :stop]`,
  and `[:portfolio, :rag, <step>, :exception]` events.

  ## Parameters

    - `step` - Pipeline step name (atom)
    - `ctx` - Current pipeline context
    - `fun` - Function that takes context and returns updated context

  ## Example

      RAG.step_span(:rewrite, ctx, fn ctx ->
        QueryProcessor.rewrite(ctx, opts)
      end)
  """
  @spec step_span(atom(), Context.t(), (Context.t() -> Context.t())) :: Context.t()
  def step_span(step, %Context{} = ctx, fun)
      when step in @pipeline_steps and is_function(fun, 1) do
    metadata = build_step_metadata(step, ctx)

    :telemetry.span(
      [:portfolio, :rag, step],
      metadata,
      fn ->
        result_ctx = fun.(ctx)
        stop_meta = build_step_stop_metadata(step, result_ctx)
        {result_ctx, stop_meta}
      end
    )
  end

  @doc """
  Emit search-specific telemetry.

  Wraps a search operation with detailed search metadata.

  ## Parameters

    - `ctx` - Current pipeline context
    - `opts` - Search options:
      - `:mode` - Search mode (:semantic, :fulltext, :hybrid)
      - `:collections` - Collections searched
      - `:limit` - Result limit
    - `fun` - Function that performs the search

  ## Example

      RAG.search_span(ctx, [mode: :hybrid, collections: ["docs"]], fn ->
        do_vector_search()
      end)
  """
  @spec search_span(Context.t(), keyword(), (-> result)) :: result when result: any()
  def search_span(%Context{} = ctx, opts, fun) when is_function(fun, 0) do
    metadata = %{
      question: ctx.question,
      mode: Keyword.get(opts, :mode, :semantic),
      collections: Keyword.get(opts, :collections, []),
      limit: Keyword.get(opts, :limit)
    }

    :telemetry.span(
      [:portfolio, :rag, :search],
      metadata,
      fn ->
        result = fun.()
        stop_meta = build_search_stop_metadata(result)
        {result, stop_meta}
      end
    )
  end

  @doc """
  Emit rerank-specific telemetry.

  Wraps a reranking operation with detailed rerank metadata.

  ## Parameters

    - `ctx` - Current pipeline context
    - `opts` - Rerank options:
      - `:input_count` - Number of chunks before reranking
      - `:threshold` - Score threshold used
    - `fun` - Function that performs the reranking

  ## Example

      RAG.rerank_span(ctx, [input_count: 25, threshold: 0.5], fn ->
        do_reranking()
      end)
  """
  @spec rerank_span(Context.t(), keyword(), (-> result)) :: result when result: any()
  def rerank_span(%Context{} = ctx, opts, fun) when is_function(fun, 0) do
    input_count = Keyword.get(opts, :input_count) || length(ctx.results)

    metadata = %{
      question: ctx.question,
      input_count: input_count,
      threshold: Keyword.get(opts, :threshold)
    }

    :telemetry.span(
      [:portfolio, :rag, :rerank],
      metadata,
      fn ->
        result = fun.()
        stop_meta = build_rerank_stop_metadata(result, input_count)
        {result, stop_meta}
      end
    )
  end

  @doc """
  Emit self-correction telemetry.

  Used to track when the RAG pipeline performs self-correction.

  ## Parameters

    - `ctx` - Current pipeline context
    - `reason` - Reason for correction

  ## Example

      RAG.correction_event(ctx, "Answer not grounded in context")
  """
  @spec correction_event(Context.t(), String.t()) :: :ok
  def correction_event(%Context{} = ctx, reason) when is_binary(reason) do
    :telemetry.execute(
      [:portfolio, :rag, :self_correct],
      %{count: 1},
      %{
        question: ctx.question,
        correction_count: ctx.correction_count + 1,
        reason: reason
      }
    )
  end

  # Private functions

  defp build_step_metadata(step, ctx) do
    base = %{
      step: step,
      question: ctx.question
    }

    # Add context state summary
    context_state =
      %{}
      |> maybe_put(:has_rewritten, ctx.rewritten_query != nil)
      |> maybe_put(:has_expanded, ctx.expanded_query != nil)
      |> maybe_put(:sub_question_count, length(ctx.sub_questions))
      |> maybe_put(:result_count, length(ctx.results))
      |> maybe_put(:has_answer, ctx.answer != nil)

    Map.put(base, :context_state, context_state)
  end

  defp build_step_stop_metadata(:rewrite, ctx) do
    %{
      query: ctx.rewritten_query,
      success: ctx.rewritten_query != nil
    }
  end

  defp build_step_stop_metadata(:expand, ctx) do
    %{
      expanded_query: ctx.expanded_query,
      success: ctx.expanded_query != nil
    }
  end

  defp build_step_stop_metadata(:decompose, ctx) do
    %{
      sub_question_count: length(ctx.sub_questions),
      success: ctx.sub_questions != []
    }
  end

  defp build_step_stop_metadata(:select, ctx) do
    %{
      selected: ctx.selected_indexes,
      selection_count: length(ctx.selected_indexes),
      reasoning: ctx.selection_reasoning
    }
  end

  defp build_step_stop_metadata(:search, ctx) do
    %{
      result_count: length(ctx.results),
      total_chunks: length(ctx.results)
    }
  end

  defp build_step_stop_metadata(:rerank, ctx) do
    %{
      output_count: length(ctx.results),
      kept: length(ctx.results)
    }
  end

  defp build_step_stop_metadata(:answer, ctx) do
    %{
      has_answer: ctx.answer != nil,
      answer_length: if(ctx.answer, do: String.length(ctx.answer), else: 0),
      context_used_count: length(ctx.context_used)
    }
  end

  defp build_step_stop_metadata(:self_correct, ctx) do
    %{
      correction_count: ctx.correction_count,
      corrections: ctx.corrections
    }
  end

  defp build_search_stop_metadata({:ok, results}) when is_list(results) do
    %{result_count: length(results)}
  end

  defp build_search_stop_metadata(results) when is_list(results) do
    %{result_count: length(results)}
  end

  defp build_search_stop_metadata(_) do
    %{}
  end

  defp build_rerank_stop_metadata({:ok, results}, input_count) when is_list(results) do
    %{
      output_count: length(results),
      kept: length(results),
      original: input_count
    }
  end

  defp build_rerank_stop_metadata(results, input_count) when is_list(results) do
    %{
      output_count: length(results),
      kept: length(results),
      original: input_count
    }
  end

  defp build_rerank_stop_metadata(_results, input_count) do
    %{original: input_count}
  end

  defp maybe_put(map, _key, value) when value in [nil, false], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
