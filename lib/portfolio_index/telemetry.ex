defmodule PortfolioIndex.Telemetry do
  @moduledoc """
  Telemetry setup and event handling for PortfolioIndex.

  Emits events for:
  - Vector store operations
  - Graph store operations
  - Embedding generation
  - LLM completions
  - Pipeline processing
  - RAG retrieval
  """

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns a list of telemetry metrics for the application.
  """
  def metrics do
    [
      # Vector store metrics
      counter("portfolio_index.vector_store.store.count"),
      counter("portfolio_index.vector_store.search.count"),
      summary("portfolio_index.vector_store.search.duration",
        unit: {:native, :millisecond}
      ),
      summary("portfolio_index.vector_store.store_batch.count",
        description: "Number of vectors stored in batch"
      ),

      # Graph store metrics
      counter("portfolio_index.graph_store.create_node.count"),
      counter("portfolio_index.graph_store.create_edge.count"),
      counter("portfolio_index.graph_store.query.count"),
      summary("portfolio_index.graph_store.query.duration",
        unit: {:native, :millisecond}
      ),

      # Embedder metrics
      counter("portfolio_index.embedder.embed.count"),
      counter("portfolio_index.embedder.embed_batch.count"),
      summary("portfolio_index.embedder.embed.tokens",
        description: "Tokens used per embedding"
      ),
      summary("portfolio_index.embedder.embed.duration",
        unit: {:native, :millisecond}
      ),

      # LLM metrics
      counter("portfolio_index.llm.complete.count"),
      summary("portfolio_index.llm.complete.input_tokens"),
      summary("portfolio_index.llm.complete.output_tokens"),
      summary("portfolio_index.llm.complete.duration",
        unit: {:native, :millisecond}
      ),

      # Pipeline metrics
      counter("portfolio_index.pipeline.ingestion.file_processed.count"),
      counter("portfolio_index.pipeline.embedding.generated.count"),
      summary("portfolio_index.pipeline.ingestion.chunks_per_file"),

      # RAG metrics
      counter("portfolio_index.rag.retrieve.count"),
      summary("portfolio_index.rag.retrieve.duration",
        unit: {:native, :millisecond}
      ),
      summary("portfolio_index.rag.retrieve.items_returned"),

      # Agent session metrics
      counter("portfolio_index.agent_session.start_session.count"),
      counter("portfolio_index.agent_session.execute.count"),
      counter("portfolio_index.agent_session.cancel.count"),
      counter("portfolio_index.agent_session.end_session.count"),
      summary("portfolio_index.agent_session.execute.duration",
        unit: {:native, :millisecond}
      ),
      summary("portfolio_index.agent_session.execute.input_tokens"),
      summary("portfolio_index.agent_session.execute.output_tokens")
    ]
  end

  defp periodic_measurements do
    []
  end

  @doc """
  Attaches telemetry handlers for logging.
  """
  def attach_default_handlers do
    events = [
      [:portfolio_index, :vector_store, :search, :stop],
      [:portfolio_index, :embedder, :embed, :stop],
      [:portfolio_index, :llm, :complete, :stop],
      [:portfolio_index, :rag, :retrieve, :stop],
      [:portfolio_index, :agent_session, :execute, :stop],
      [:portfolio_index, :agent_session, :start_session, :stop]
    ]

    :telemetry.attach_many(
      "portfolio-index-logger",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event(event, measurements, metadata, _config) do
    require Logger

    Logger.debug(
      "[Telemetry] #{inspect(event)} " <>
        "measurements=#{inspect(measurements)} " <>
        "metadata=#{inspect(Map.take(metadata, [:model, :index_id, :graph_id, :strategy]))}"
    )
  end
end
