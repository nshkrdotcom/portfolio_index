defmodule PortfolioIndex.RAG.Strategies.Agentic do
  @moduledoc """
  Agentic retrieval strategy placeholder.

  Currently delegates to Hybrid retrieval and tags the result as :agentic.
  """

  @behaviour PortfolioIndex.RAG.Strategy

  alias PortfolioIndex.RAG.Strategies.Hybrid

  @impl true
  def name, do: :agentic

  @impl true
  def required_adapters, do: [:vector_store, :embedder, :llm]

  @impl true
  def retrieve(query, context, opts) do
    with {:ok, result} <- Hybrid.retrieve(query, context, opts) do
      {:ok, Map.put(result, :strategy, :agentic)}
    end
  end
end
