defmodule PortfolioIndex.Adapters.LLM.Anthropic do
  @moduledoc """
  Anthropic LLM adapter placeholder.

  This adapter satisfies the `PortfolioCore.Ports.LLM` behaviour but
  does not implement actual API calls yet.
  """

  @behaviour PortfolioCore.Ports.LLM

  require Logger

  @impl true
  def complete(_messages, _opts) do
    Logger.error("Anthropic LLM adapter not implemented")
    {:error, :not_implemented}
  end

  @impl true
  def stream(_messages, _opts) do
    Logger.error("Anthropic LLM adapter not implemented")
    {:error, :not_implemented}
  end

  @impl true
  def supported_models do
    ["claude-3-sonnet-20240229"]
  end

  @impl true
  def model_info(_model) do
    %{context_window: 200_000, max_output: 4096, supports_tools: false}
  end
end
