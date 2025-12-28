defmodule PortfolioIndex.Adapters.Reranker.LLM do
  @moduledoc """
  LLM-based document reranking.

  Implements the `PortfolioCore.Ports.Reranker` behaviour.

  Uses an LLM to score document relevance to a query, then reorders
  results by the new scores. This provides higher quality reranking
  than simple embedding similarity at the cost of latency.

  ## Strategy

  1. Build a prompt with the query and candidate documents
  2. Ask the LLM to score each document's relevance (1-10)
  3. Parse the JSON response to extract scores
  4. Reorder documents by LLM-assigned scores
  5. Return top_n results

  ## Example

      opts = [top_n: 5, context: %{adapters: %{llm: MyLLM}}]
      {:ok, reranked} = LLM.rerank("What is Elixir?", documents, opts)

  ## Customization

  Provide a custom prompt template via the `:prompt_template` option:

      opts = [prompt_template: "Rate documents...\\n{query}\\n{documents}"]
  """

  @behaviour PortfolioCore.Ports.Reranker

  require Logger

  alias PortfolioIndex.RAG.AdapterResolver

  @default_prompt_template """
  You are a relevance scoring assistant. Score how relevant each document is to the query.

  Query: {query}

  Documents to score:
  {documents}

  For each document, provide a relevance score from 1 to 10 where:
  - 1 = completely irrelevant
  - 5 = somewhat relevant
  - 10 = highly relevant and directly answers the query

  Return ONLY a valid JSON array with objects containing "index" (0-based) and "score" fields.
  Example: [{"index": 0, "score": 8}, {"index": 1, "score": 3}]

  JSON response:
  """

  @impl true
  @spec rerank(String.t(), [map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def rerank(query, documents, opts) do
    if Enum.empty?(documents) do
      {:ok, []}
    else
      start_time = System.monotonic_time(:millisecond)
      top_n = Keyword.get(opts, :top_n, length(documents))
      prompt_template = Keyword.get(opts, :prompt_template, @default_prompt_template)

      {llm, llm_opts} = resolve_llm(opts)

      prompt = build_prompt(query, documents, prompt_template)
      messages = [%{role: :user, content: prompt}]

      case llm.complete(messages, llm_opts) do
        {:ok, %{content: content}} ->
          case parse_scores(content, length(documents)) do
            {:ok, scores} ->
              reranked = apply_scores_and_sort(documents, scores, top_n)
              duration = System.monotonic_time(:millisecond) - start_time

              emit_telemetry(
                :rerank,
                %{
                  duration_ms: duration,
                  input_count: length(documents),
                  output_count: length(reranked)
                },
                %{}
              )

              {:ok, reranked}

            {:error, reason} ->
              Logger.warning(
                "Failed to parse LLM rerank scores: #{inspect(reason)}, using passthrough"
              )

              passthrough_rerank(documents, top_n)
          end

        {:ok, response} ->
          # Try to extract content from various response formats
          content = extract_content(response)

          case parse_scores(content, length(documents)) do
            {:ok, scores} ->
              reranked = apply_scores_and_sort(documents, scores, top_n)
              {:ok, reranked}

            {:error, _reason} ->
              passthrough_rerank(documents, top_n)
          end

        {:error, reason} ->
          Logger.warning("LLM reranking failed: #{inspect(reason)}, using passthrough")
          passthrough_rerank(documents, top_n)
      end
    end
  end

  @impl true
  @spec model_name() :: String.t()
  def model_name, do: "llm-reranker"

  @impl true
  @spec normalize_scores([map()]) :: [map()]
  def normalize_scores(items) do
    scores = Enum.map(items, & &1.rerank_score)
    max_score = Enum.max(scores, fn -> 1.0 end)
    min_score = Enum.min(scores, fn -> 0.0 end)
    range = max_score - min_score

    if range == 0 do
      Enum.map(items, &Map.put(&1, :rerank_score, 1.0))
    else
      Enum.map(items, fn item ->
        normalized = (item.rerank_score - min_score) / range
        Map.put(item, :rerank_score, normalized)
      end)
    end
  end

  # Private functions

  @spec resolve_llm(keyword()) :: {module(), keyword()}
  defp resolve_llm(opts) do
    context = Keyword.get(opts, :context, %{})
    default_llm = PortfolioIndex.Adapters.LLM.Gemini
    AdapterResolver.resolve(context, :llm, default_llm)
  end

  @spec build_prompt(String.t(), [map()], String.t()) :: String.t()
  defp build_prompt(query, documents, template) do
    documents_text =
      documents
      |> Enum.with_index()
      |> Enum.map_join("\n\n", fn {doc, idx} ->
        content = doc[:content] || doc.content || ""
        truncated = String.slice(content, 0, 500)
        "[Document #{idx}]: #{truncated}"
      end)

    template
    |> String.replace("{query}", query)
    |> String.replace("{documents}", documents_text)
  end

  @spec parse_scores(String.t(), non_neg_integer()) ::
          {:ok, %{non_neg_integer() => float()}} | {:error, term()}
  defp parse_scores(content, doc_count) do
    # Try to extract JSON array from the response
    case extract_json_array(content) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, scores} when is_list(scores) ->
            score_map =
              scores
              |> Enum.filter(fn s ->
                is_map(s) and Map.has_key?(s, "index") and Map.has_key?(s, "score")
              end)
              |> Enum.map(fn s ->
                index = s["index"]
                score = s["score"]
                # Normalize to 0-1
                {index, score / 10.0}
              end)
              |> Enum.filter(fn {idx, _} -> idx >= 0 and idx < doc_count end)
              |> Map.new()

            {:ok, score_map}

          {:ok, _} ->
            {:error, :invalid_json_structure}

          {:error, reason} ->
            {:error, {:json_decode, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec extract_json_array(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp extract_json_array(content) do
    case Regex.run(~r/\[[\s\S]*\]/, content) do
      [json] -> {:ok, json}
      nil -> {:error, :no_json_array_found}
    end
  end

  @spec apply_scores_and_sort([map()], %{non_neg_integer() => float()}, pos_integer()) :: [map()]
  defp apply_scores_and_sort(documents, scores, top_n) do
    documents
    |> Enum.with_index()
    |> Enum.map(fn {doc, idx} ->
      original_score = Map.get(doc, :score) || Map.get(doc, "score") || 0.0
      rerank_score = Map.get(scores, idx, original_score)
      content = Map.get(doc, :content) || Map.get(doc, "content") || ""

      %{
        id: Map.get(doc, :id) || Map.get(doc, "id") || "doc_#{idx}",
        content: content,
        original_score: original_score,
        rerank_score: rerank_score,
        metadata: Map.get(doc, :metadata) || Map.get(doc, "metadata") || %{}
      }
    end)
    |> Enum.sort_by(& &1.rerank_score, :desc)
    |> Enum.take(top_n)
  end

  @spec passthrough_rerank([map()], pos_integer()) :: {:ok, [map()]}
  defp passthrough_rerank(documents, top_n) do
    reranked =
      documents
      |> Enum.with_index()
      |> Enum.map(fn {doc, idx} ->
        original_score = Map.get(doc, :score) || Map.get(doc, "score") || 1.0 - idx * 0.01
        content = Map.get(doc, :content) || Map.get(doc, "content") || ""

        %{
          id: Map.get(doc, :id) || Map.get(doc, "id") || "doc_#{idx}",
          content: content,
          original_score: original_score,
          rerank_score: original_score,
          metadata: Map.get(doc, :metadata) || Map.get(doc, "metadata") || %{}
        }
      end)
      |> Enum.take(top_n)

    {:ok, reranked}
  end

  @spec extract_content(map()) :: String.t()
  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(_), do: ""

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:portfolio_index, :reranker, :llm, event],
      measurements,
      metadata
    )
  end
end
