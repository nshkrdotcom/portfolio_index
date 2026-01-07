defmodule PortfolioIndex.Pipelines.Embedding do
  @moduledoc """
  Broadway pipeline for generating embeddings with rate limiting.

  Consumes chunks from the ingestion pipeline, generates embeddings,
  and stores them in the vector store.

  ## Flow

  1. ETSProducer reads from embedding queue
  2. Processor generates embeddings via Gemini
  3. Batcher stores embeddings in vector store

  ## Rate Limiting

  Uses Hammer for rate limiting to respect API quotas.
  Default: 100 requests per minute.

  ## Usage

      # Start the pipeline
      {:ok, _pid} = Embedding.start_link(
        index_id: "my_index",
        rate_limit: 100,
        batch_size: 50
      )

      # Enqueue a chunk
      Embedding.enqueue(%{content: "...", source: "...", index: 0})
  """

  use Broadway
  require Logger

  # Suppress dialyzer warnings for adapter calls
  @dialyzer {:nowarn_function, generate_embedding: 4}

  alias PortfolioIndex.Adapters.Embedder.Gemini, as: Embedder
  alias PortfolioIndex.Adapters.VectorStore.Pgvector, as: VectorStore

  @queue_name :embedding_queue

  @queue_override_key {__MODULE__, :queue_name}

  @doc false
  def queue_name do
    Process.get(@queue_override_key) ||
      Application.get_env(:portfolio_index, :embedding_queue_table, @queue_name)
  end

  @doc false
  def __supertester_set_table__(:queue_name, table) do
    Process.put(@queue_override_key, table)
  end

  def __supertester_set_table__(_key, _table), do: :ok

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    concurrency = Keyword.get(opts, :concurrency, 5)
    batch_size = Keyword.get(opts, :batch_size, 100)
    rate_limit = Keyword.get(opts, :rate_limit, 100)
    rate_limit_interval = Keyword.get(opts, :rate_limit_interval, 60_000)

    # Initialize the ETS queue if it doesn't exist
    _ = ensure_queue_exists()

    Broadway.start_link(__MODULE__,
      name: name,
      producer: [
        module: {PortfolioIndex.Pipelines.Producers.ETSProducer, [table: queue_name()]},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: concurrency,
          min_demand: 1,
          max_demand: 5
        ]
      ],
      batchers: [
        store: [
          concurrency: 2,
          batch_size: batch_size,
          batch_timeout: 2000
        ]
      ],
      context: %{
        index_id: Keyword.get(opts, :index_id, "default"),
        dimensions: Keyword.get(opts, :dimensions, 768),
        rate_limit: rate_limit,
        rate_limit_interval: rate_limit_interval
      }
    )
  end

  @doc """
  Start the embedding pipeline under the PipelineSupervisor.
  """
  def start(opts) do
    DynamicSupervisor.start_child(
      PortfolioIndex.PipelineSupervisor,
      {__MODULE__, opts}
    )
  end

  @doc """
  Enqueue a chunk for embedding.
  """
  def enqueue(chunk) do
    _ = ensure_queue_exists()
    key = System.unique_integer([:monotonic, :positive])
    :ets.insert(queue_name(), {key, chunk})
    :ok
  end

  @doc """
  Get the current queue size.
  """
  def queue_size do
    _ = ensure_queue_exists()
    :ets.info(queue_name(), :size)
  end

  @impl true
  def handle_message(_processor, message, context) do
    chunk = message.data
    start_time = System.monotonic_time(:millisecond)

    # Check rate limit
    case check_rate_limit(context.rate_limit, context.rate_limit_interval) do
      :ok ->
        generate_embedding(message, chunk, context, start_time)

      {:error, :rate_limited} ->
        # Re-queue for later
        enqueue(chunk)
        Broadway.Message.failed(message, :rate_limited)
    end
  end

  @impl true
  def handle_batch(:store, messages, _batch_info, context) do
    start_time = System.monotonic_time(:millisecond)

    items =
      Enum.map(messages, fn msg ->
        chunk = msg.data
        id = generate_chunk_id(chunk)

        metadata = %{
          content: chunk.content,
          source: chunk.source,
          index: chunk.index,
          format: chunk.format,
          source_type: chunk[:source_type]
        }

        {id, chunk.embedding, metadata}
      end)

    case VectorStore.store_batch(context.index_id, items) do
      {:ok, count} ->
        duration = System.monotonic_time(:millisecond) - start_time

        :telemetry.execute(
          [:portfolio_index, :pipeline, :embedding, :batch_stored],
          %{duration_ms: duration, count: count},
          %{index_id: context.index_id}
        )

        Logger.info("Stored #{count} embeddings in #{duration}ms")

      {:error, reason} ->
        Logger.error("Failed to store batch: #{inspect(reason)}")
    end

    messages
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn msg ->
      case msg.status do
        {:failed, :rate_limited} ->
          Logger.debug("Re-queued rate-limited chunk")

        {:failed, reason} ->
          Logger.error("Embedding failed: #{inspect(reason)}")

        {:error, reason} ->
          Logger.error("Embedding failed: #{inspect(reason)}")
      end
    end)

    messages
  end

  # Private functions

  defp ensure_queue_exists do
    table = queue_name()

    cond do
      is_atom(table) ->
        case :ets.whereis(table) do
          :undefined ->
            :ets.new(table, [:named_table, :public, :ordered_set])

          _tid ->
            :ok
        end

      is_reference(table) ->
        case :ets.info(table) do
          :undefined ->
            new_table = :ets.new(:embedding_queue, [:public, :ordered_set])
            set_queue_override(new_table)
            :ok

          _info ->
            :ok
        end

      true ->
        :ok
    end
  end

  defp set_queue_override(table) do
    if Process.get(@queue_override_key) do
      Process.put(@queue_override_key, table)
    else
      Application.put_env(:portfolio_index, :embedding_queue_table, table)
    end
  end

  defp check_rate_limit(_rate_limit, _interval) do
    # Rate limiting is now handled by the centralized RateLimiter adapter
    # in the embedder layer. This check provides fail-fast behavior.
    alias PortfolioIndex.Adapters.RateLimiter

    case RateLimiter.check(:gemini, :embedding) do
      :ok -> :ok
      {:backoff, _ms} -> {:error, :rate_limited}
    end
  end

  defp generate_embedding(message, chunk, context, start_time) do
    case Embedder.embed(chunk.content, dimensions: context.dimensions) do
      {:ok, result} ->
        duration = System.monotonic_time(:millisecond) - start_time

        :telemetry.execute(
          [:portfolio_index, :pipeline, :embedding, :generated],
          %{duration_ms: duration, tokens: result.token_count, dimensions: result.dimensions},
          %{model: result.model}
        )

        enriched =
          Map.merge(chunk, %{
            embedding: result.vector,
            token_count: result.token_count,
            model: result.model
          })

        message
        |> Broadway.Message.update_data(fn _ -> enriched end)
        |> Broadway.Message.put_batcher(:store)

      {:error, reason} ->
        Logger.error("Embedding generation failed: #{inspect(reason)}")
        Broadway.Message.failed(message, reason)
    end
  end

  defp generate_chunk_id(chunk) do
    content_hash =
      :crypto.hash(:md5, chunk.content)
      |> Base.encode16(case: :lower)
      |> String.slice(0..7)

    source_hash =
      :crypto.hash(:md5, chunk.source)
      |> Base.encode16(case: :lower)
      |> String.slice(0..7)

    "#{source_hash}:#{chunk.index}:#{content_hash}"
  end
end
