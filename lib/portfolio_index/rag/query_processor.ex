defmodule PortfolioIndex.RAG.QueryProcessor do
  @moduledoc """
  Unified query processing module that combines rewriting, expansion, and decomposition.

  This module provides pipeline-friendly functions that transform a `Context` struct
  through various query processing stages. Each function is designed to work with
  the pipe operator for composition.

  ## Pipeline Usage

      ctx =
        Context.new("Hey, what is Elixir?")
        |> QueryProcessor.rewrite()
        |> QueryProcessor.expand()
        |> QueryProcessor.decompose()

      # Access processed query
      QueryProcessor.effective_query(ctx)
      # => "elixir programming language functional concurrent"

  ## Configuration

  All functions accept options to customize behavior:

      opts = [
        context: %{adapters: %{llm: MyLLM}},  # LLM adapter
        prompt: fn q -> "Custom: \#{q}" end    # Custom prompt
      ]

  ## Processing Steps

  1. **Rewrite** - Removes conversational noise, extracts core question
  2. **Expand** - Adds synonyms and related terms for better recall
  3. **Decompose** - Breaks complex questions into simpler sub-questions

  ## Error Handling

  Processing steps are designed to be graceful:
  - Failures don't halt the pipeline (unless context is explicitly halted)
  - Each step checks for halted context and short-circuits
  - The `effective_query/1` function always returns a usable query
  """

  alias PortfolioIndex.Adapters.QueryDecomposer
  alias PortfolioIndex.Adapters.QueryExpander
  alias PortfolioIndex.Adapters.QueryRewriter
  alias PortfolioIndex.RAG.Pipeline.Context

  require Logger

  @doc """
  Apply query rewriting to context.

  Transforms conversational input into a clean search query by removing
  greetings, filler phrases, and other noise.

  ## Options

    - `:context` - Adapter context (required for LLM resolution)
    - `:prompt` - Custom prompt function `fn query -> prompt_string end`
    - `:rewriter` - Custom rewriter module (default: `QueryRewriter.LLM`)

  ## Examples

      ctx
      |> QueryProcessor.rewrite(context: %{adapters: %{llm: MyLLM}})

  Returns the context with `rewritten_query` populated.
  """
  @spec rewrite(Context.t(), keyword()) :: Context.t()
  def rewrite(ctx, opts \\ [])

  def rewrite(%Context{halted?: true} = ctx, _opts), do: ctx

  def rewrite(%Context{} = ctx, opts) do
    rewriter = Keyword.get(opts, :rewriter, QueryRewriter.LLM)

    :telemetry.span(
      [:portfolio_index, :query_processor, :rewrite],
      %{question: ctx.question},
      fn ->
        case rewriter.rewrite(ctx.question, opts) do
          {:ok, %{rewritten: rewritten}} ->
            updated_ctx = %{ctx | rewritten_query: rewritten}
            {updated_ctx, %{success: true}}

          {:error, reason} ->
            Logger.warning("Query rewriting failed: #{inspect(reason)}")
            {ctx, %{success: false, reason: reason}}
        end
      end
    )
  end

  @doc """
  Apply query expansion to context.

  Adds synonyms and related terms to improve retrieval recall.
  Uses `rewritten_query` if available, otherwise uses original `question`.

  ## Options

    - `:context` - Adapter context (required for LLM resolution)
    - `:prompt` - Custom prompt function `fn query -> prompt_string end`
    - `:expander` - Custom expander module (default: `QueryExpander.LLM`)

  ## Examples

      ctx
      |> QueryProcessor.expand(context: %{adapters: %{llm: MyLLM}})

  Returns the context with `expanded_query` populated.
  """
  @spec expand(Context.t(), keyword()) :: Context.t()
  def expand(ctx, opts \\ [])

  def expand(%Context{halted?: true} = ctx, _opts), do: ctx

  def expand(%Context{} = ctx, opts) do
    expander = Keyword.get(opts, :expander, QueryExpander.LLM)
    query = ctx.rewritten_query || ctx.question

    :telemetry.span([:portfolio_index, :query_processor, :expand], %{query: query}, fn ->
      case expander.expand(query, opts) do
        {:ok, %{expanded: expanded}} ->
          updated_ctx = %{ctx | expanded_query: expanded}
          {updated_ctx, %{success: true}}

        {:error, reason} ->
          Logger.warning("Query expansion failed: #{inspect(reason)}")
          {ctx, %{success: false, reason: reason}}
      end
    end)
  end

  @doc """
  Apply query decomposition to context.

  Breaks complex questions into simpler sub-questions that can be searched
  independently. Uses the effective query (expanded > rewritten > original).

  ## Options

    - `:context` - Adapter context (required for LLM resolution)
    - `:prompt` - Custom prompt function `fn query -> prompt_string end`
    - `:decomposer` - Custom decomposer module (default: `QueryDecomposer.LLM`)

  ## Examples

      ctx
      |> QueryProcessor.decompose(context: %{adapters: %{llm: MyLLM}})

  Returns the context with `sub_questions` populated.
  """
  @spec decompose(Context.t(), keyword()) :: Context.t()
  def decompose(ctx, opts \\ [])

  def decompose(%Context{halted?: true} = ctx, _opts), do: ctx

  def decompose(%Context{} = ctx, opts) do
    decomposer = Keyword.get(opts, :decomposer, QueryDecomposer.LLM)
    query = effective_query(ctx)

    :telemetry.span([:portfolio_index, :query_processor, :decompose], %{query: query}, fn ->
      case decomposer.decompose(query, opts) do
        {:ok, %{sub_questions: sub_questions}} ->
          updated_ctx = %{ctx | sub_questions: sub_questions}
          {updated_ctx, %{success: true, sub_question_count: length(sub_questions)}}

        {:error, reason} ->
          Logger.warning("Query decomposition failed: #{inspect(reason)}")
          {ctx, %{success: false, reason: reason}}
      end
    end)
  end

  @doc """
  Apply all query processing steps in sequence.

  Runs rewrite -> expand -> decompose by default. Individual steps can be
  skipped using the `:skip` option.

  ## Options

    - `:context` - Adapter context (required for LLM resolution)
    - `:skip` - List of steps to skip (e.g., `[:expand, :decompose]`)
    - Plus all options accepted by individual steps

  ## Examples

      # Full processing
      ctx |> QueryProcessor.process(context: %{adapters: %{llm: MyLLM}})

      # Skip expansion
      ctx |> QueryProcessor.process(skip: [:expand], context: ctx)

  Returns the fully processed context.
  """
  @spec process(Context.t(), keyword()) :: Context.t()
  def process(ctx, opts \\ [])

  def process(%Context{halted?: true} = ctx, _opts), do: ctx

  def process(%Context{} = ctx, opts) do
    skip = Keyword.get(opts, :skip, [])

    ctx
    |> maybe_apply(:rewrite, skip, opts)
    |> maybe_apply(:expand, skip, opts)
    |> maybe_apply(:decompose, skip, opts)
  end

  @spec maybe_apply(Context.t(), atom(), [atom()], keyword()) :: Context.t()
  defp maybe_apply(ctx, step, skip, opts) do
    if step in skip do
      ctx
    else
      apply(__MODULE__, step, [ctx, opts])
    end
  end

  @doc """
  Returns the effective query to use for retrieval.

  Priority: expanded_query > rewritten_query > question

  This is the query that should be used for embedding generation
  and vector search.

  ## Examples

      ctx = Context.new("Hey what is Elixir?")
        |> QueryProcessor.rewrite()
        |> QueryProcessor.expand()

      QueryProcessor.effective_query(ctx)
      # => "elixir programming language functional concurrent"
  """
  @spec effective_query(Context.t()) :: String.t()
  def effective_query(%Context{expanded_query: expanded}) when is_binary(expanded), do: expanded

  def effective_query(%Context{rewritten_query: rewritten}) when is_binary(rewritten),
    do: rewritten

  def effective_query(%Context{question: question}), do: question
end
