defmodule PortfolioIndex.Pipelines.Ingestion do
  @moduledoc """
  Broadway pipeline for document ingestion.

  Handles file reading, parsing, and chunking. Outputs chunks to the
  embedding queue for further processing.

  ## Flow

  1. FileProducer discovers files
  2. Processor reads and parses content
  3. Processor chunks content
  4. Batcher queues chunks for embedding

  ## Usage

      # Start the pipeline
      {:ok, _pid} = Ingestion.start_link(
        paths: ["/path/to/docs"],
        patterns: ["**/*.md"],
        index_id: "my_index"
      )
  """

  use Broadway
  require Logger

  alias PortfolioIndex.Adapters.Chunker.Recursive, as: Chunker
  alias PortfolioIndex.Pipelines.Embedding

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    paths = Keyword.get(opts, :paths, [])
    patterns = Keyword.get(opts, :patterns, ["**/*"])
    concurrency = Keyword.get(opts, :concurrency, 10)
    batch_size = Keyword.get(opts, :batch_size, 50)

    Broadway.start_link(__MODULE__,
      name: name,
      producer: [
        module:
          {PortfolioIndex.Pipelines.Producers.FileProducer,
           [
             paths: paths,
             patterns: patterns
           ]},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: concurrency,
          min_demand: 1,
          max_demand: 10
        ]
      ],
      batchers: [
        embedding: [
          concurrency: 2,
          batch_size: batch_size,
          batch_timeout: 5000
        ]
      ],
      context: %{
        index_id: Keyword.get(opts, :index_id, "default"),
        chunk_size: Keyword.get(opts, :chunk_size, 1000),
        chunk_overlap: Keyword.get(opts, :chunk_overlap, 200)
      }
    )
  end

  @doc """
  Start the ingestion pipeline under the PipelineSupervisor.
  """
  def start(opts) do
    DynamicSupervisor.start_child(
      PortfolioIndex.PipelineSupervisor,
      {__MODULE__, opts}
    )
  end

  @doc """
  Enqueue a single file for ingestion without starting a producer.

  This is useful for ad-hoc indexing flows where files are already
  discovered by the caller.
  """
  def enqueue(file, opts \\ []) do
    context = %{
      index_id: Keyword.get(opts, :index_id, "default"),
      chunk_size: Keyword.get(opts, :chunk_size, 1000),
      chunk_overlap: Keyword.get(opts, :chunk_overlap, 200)
    }

    case process_file(file, context) do
      {:ok, chunks} ->
        Enum.each(chunks, fn chunk ->
          Embedding.enqueue(
            Map.merge(chunk, %{
              source: file.path,
              source_type: file.type,
              index_id: context.index_id
            })
          )
        end)

        {:ok, length(chunks)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_message(_processor, message, context) do
    start_time = System.monotonic_time(:millisecond)
    file_info = message.data

    case process_file(file_info, context) do
      {:ok, chunks} ->
        duration = System.monotonic_time(:millisecond) - start_time

        :telemetry.execute(
          [:portfolio_index, :pipeline, :ingestion, :file_processed],
          %{duration_ms: duration, chunk_count: length(chunks)},
          %{path: file_info.path, type: file_info.type}
        )

        message
        |> Broadway.Message.update_data(fn _ -> %{chunks: chunks, file_info: file_info} end)
        |> Broadway.Message.put_batcher(:embedding)

      {:error, reason} ->
        Logger.warning("Failed to process #{file_info.path}: #{inspect(reason)}")
        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:embedding, messages, _batch_info, context) do
    chunks =
      Enum.flat_map(messages, fn msg ->
        Enum.map(msg.data.chunks, fn chunk ->
          Map.merge(chunk, %{
            source: msg.data.file_info.path,
            source_type: msg.data.file_info.type,
            index_id: context.index_id
          })
        end)
      end)

    Logger.info("Queuing #{length(chunks)} chunks for embedding")

    # Queue chunks for embedding pipeline
    Enum.each(chunks, fn chunk ->
      Embedding.enqueue(chunk)
    end)

    messages
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn msg ->
      Logger.error("Ingestion failed: #{inspect(msg.data)}, status: #{inspect(msg.status)}")
    end)

    messages
  end

  # Private functions

  defp process_file(%{path: path, type: type}, context) do
    with {:ok, content} <- File.read(path),
         {:ok, parsed} <- parse_content(content, type) do
      chunk_content(parsed, context)
    end
  end

  defp parse_content(content, :elixir) do
    {:ok, %{text: content, format: :code, language: :elixir}}
  end

  defp parse_content(content, :markdown) do
    {:ok, %{text: content, format: :markdown}}
  end

  defp parse_content(content, :html) do
    {:ok, %{text: content, format: :html}}
  end

  defp parse_content(content, _type) do
    {:ok, %{text: content, format: :plain}}
  end

  defp chunk_content(parsed, context) do
    config = %{
      chunk_size: context.chunk_size,
      chunk_overlap: context.chunk_overlap
    }

    {:ok, chunks} = Chunker.chunk(parsed.text, parsed.format, config)

    enriched =
      Enum.map(chunks, fn chunk ->
        Map.merge(chunk, %{
          format: parsed.format,
          language: parsed[:language]
        })
      end)

    {:ok, enriched}
  end
end
