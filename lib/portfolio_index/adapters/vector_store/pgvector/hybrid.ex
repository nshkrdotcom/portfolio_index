defmodule PortfolioIndex.Adapters.VectorStore.Pgvector.Hybrid do
  @moduledoc """
  Hybrid capability wrapper for the Pgvector adapter.

  Exposes `fulltext_search/4` for stores that support tsvector-based retrieval.
  """

  @behaviour PortfolioCore.Ports.VectorStore.Hybrid

  alias PortfolioIndex.Adapters.VectorStore.Pgvector

  @impl true
  def fulltext_search(index_id, query, k, opts) do
    Pgvector.fulltext_search(index_id, query, k, opts)
  end
end
