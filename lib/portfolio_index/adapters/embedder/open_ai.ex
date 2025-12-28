defmodule PortfolioIndex.Adapters.Embedder.OpenAI do
  @moduledoc """
  OpenAI embeddings adapter placeholder.

  This adapter satisfies the `PortfolioCore.Ports.Embedder` behaviour but
  does not implement actual API calls yet.
  """

  @behaviour PortfolioCore.Ports.Embedder

  require Logger

  @impl true
  def embed(_text, _opts) do
    Logger.error("OpenAI embedder adapter not implemented")
    {:error, :not_implemented}
  end

  @impl true
  def embed_batch(_texts, _opts) do
    Logger.error("OpenAI embedder adapter not implemented")
    {:error, :not_implemented}
  end

  @impl true
  def dimensions(_model), do: 1536

  @impl true
  def supported_models do
    ["text-embedding-3-small", "text-embedding-3-large"]
  end
end
