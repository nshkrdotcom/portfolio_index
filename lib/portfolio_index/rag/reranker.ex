defmodule PortfolioIndex.RAG.Reranker do
  @moduledoc """
  Reranking utilities for RAG pipeline integration.
  Wraps the existing Reranker.LLM adapter with pipeline-aware functionality.

  ## Usage with Pipeline Context

      ctx = %Context{
        question: "What is Elixir?",
        results: [%{content: "...", score: 0.9}, ...]
      }

      opts = [
        reranker: PortfolioIndex.Adapters.Reranker.LLM,
        threshold: 0.7,
        limit: 5
      ]

      result_ctx = Reranker.rerank(ctx, opts)

      result_ctx.results        # Reranked and filtered results
      result_ctx.rerank_scores  # Map of id -> score (if track_scores: true)

  ## Direct Chunk Reranking

      {:ok, reranked} = Reranker.rerank_chunks(
        "What is Elixir?",
        chunks,
        reranker: MyReranker,
        limit: 5
      )

  ## Options

    - `:reranker` - Reranker module implementing PortfolioCore.Ports.Reranker
    - `:threshold` - Minimum score to keep (0.0-1.0)
    - `:limit` - Maximum number of results to return
    - `:track_scores` - Whether to store scores in context (default: true)
  """

  alias PortfolioIndex.RAG.Pipeline.Context

  require Logger

  @type rerank_opts :: [
          threshold: float(),
          limit: pos_integer(),
          reranker:
            module()
            | (String.t(), [map()], keyword() -> {:ok, [map()]} | {:error, term()}),
          track_scores: boolean()
        ]

  @doc """
  Rerank search results in pipeline context.

  Updates context with:
  - Reranked and filtered results
  - Rerank scores (if track_scores: true)
  """
  @spec rerank(Context.t(), rerank_opts()) :: Context.t()
  def rerank(%Context{halted?: true} = ctx, _opts), do: ctx
  def rerank(%Context{error: error} = ctx, _opts) when not is_nil(error), do: ctx

  def rerank(%Context{results: nil} = ctx, _opts) do
    %{ctx | results: [], rerank_scores: %{}}
  end

  def rerank(%Context{results: []} = ctx, _opts) do
    %{ctx | rerank_scores: %{}}
  end

  def rerank(%Context{} = ctx, opts) do
    reranker = Keyword.get(opts, :reranker, PortfolioIndex.Adapters.Reranker.LLM)
    threshold = Keyword.get(opts, :threshold, 0.0)
    limit = Keyword.get(opts, :limit, length(ctx.results))
    track_scores = Keyword.get(opts, :track_scores, true)

    case do_rerank(reranker, ctx.question, ctx.results, opts) do
      {:ok, reranked} ->
        filtered =
          reranked
          |> filter_by_threshold(threshold)
          |> Enum.take(limit)

        scores =
          if track_scores do
            build_scores_map(reranked)
          else
            %{}
          end

        %{ctx | results: filtered, rerank_scores: scores}

      {:error, reason} ->
        Logger.warning("Reranking failed: #{inspect(reason)}, using original results")
        %{ctx | rerank_scores: %{}}
    end
  end

  @doc """
  Rerank a list of chunks directly.
  """
  @spec rerank_chunks(String.t(), [map()], rerank_opts()) :: {:ok, [map()]} | {:error, term()}
  def rerank_chunks(question, chunks, opts \\ []) do
    reranker = Keyword.get(opts, :reranker, PortfolioIndex.Adapters.Reranker.LLM)
    threshold = Keyword.get(opts, :threshold, 0.0)
    limit = Keyword.get(opts, :limit, length(chunks))

    case do_rerank(reranker, question, chunks, opts) do
      {:ok, reranked} ->
        filtered =
          reranked
          |> filter_by_threshold(threshold)
          |> Enum.take(limit)

        {:ok, filtered}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deduplicate chunks by content or ID.
  """
  @spec deduplicate([map()], atom()) :: [map()]
  def deduplicate(chunks, key \\ :id)

  def deduplicate([], _key), do: []

  def deduplicate(chunks, key) do
    chunks
    |> Enum.reduce({[], MapSet.new()}, fn chunk, {acc, seen} ->
      value = Map.get(chunk, key)

      if value && MapSet.member?(seen, value) do
        {acc, seen}
      else
        {[chunk | acc], MapSet.put(seen, value)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # Private functions

  defp do_rerank(reranker, question, chunks, opts) when is_atom(reranker) do
    reranker_opts = Keyword.take(opts, [:top_n, :context, :prompt_template])
    top_n = Keyword.get(opts, :limit, length(chunks))
    reranker_opts = Keyword.put(reranker_opts, :top_n, top_n)

    reranker.rerank(question, chunks, reranker_opts)
  end

  defp do_rerank(reranker, question, chunks, opts) when is_function(reranker, 3) do
    reranker.(question, chunks, opts)
  end

  defp filter_by_threshold(chunks, threshold) when threshold <= 0.0, do: chunks

  defp filter_by_threshold(chunks, threshold) do
    Enum.filter(chunks, fn chunk ->
      score = chunk[:rerank_score] || chunk[:score] || 0.0
      score >= threshold
    end)
  end

  defp build_scores_map(chunks) do
    chunks
    |> Enum.reduce(%{}, fn chunk, acc ->
      case chunk[:id] do
        nil -> acc
        id -> Map.put(acc, id, chunk[:rerank_score] || chunk[:score] || 0.0)
      end
    end)
  end
end
