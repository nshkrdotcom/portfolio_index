defmodule PortfolioIndex.RAG.Strategies.GraphRAG do
  @moduledoc """
  Graph-aware retrieval strategy.

  For now, this delegates to the Hybrid strategy and tags the result
  as :graph_rag. Graph expansion can be layered in when graph adapters
  are available and configured.
  """

  @behaviour PortfolioIndex.RAG.Strategy

  alias PortfolioIndex.RAG.Strategies.Hybrid

  @impl true
  def name, do: :graph_rag

  @impl true
  def required_adapters, do: [:vector_store, :embedder, :graph_store]

  @impl true
  def retrieve(query, context, opts) do
    with {:ok, result} <- Hybrid.retrieve(query, context, opts) do
      {:ok, Map.put(result, :strategy, :graph_rag)}
    end
  end
end
