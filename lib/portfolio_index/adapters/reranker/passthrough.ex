defmodule PortfolioIndex.Adapters.Reranker.Passthrough do
  @moduledoc """
  No-op reranker for testing and baseline comparisons.

  Implements the `PortfolioCore.Ports.Reranker` behaviour.

  Returns documents in their original order without modification.
  Useful for:
  - Testing pipelines without reranking overhead
  - Establishing baseline metrics
  - Debugging retrieval issues

  ## Example

      {:ok, items} = Passthrough.rerank("query", documents, [])
      # Returns documents unchanged
  """

  @behaviour PortfolioCore.Ports.Reranker

  @impl true
  @spec rerank(String.t(), [map()], keyword()) :: {:ok, [map()]}
  def rerank(_query, documents, _opts) do
    # Add rerank_score equal to original score (or index-based if no score)
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

    {:ok, reranked}
  end

  @impl true
  @spec model_name() :: String.t()
  def model_name, do: "passthrough"
end
