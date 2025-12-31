defmodule PortfolioIndex.Telemetry.Logger do
  @moduledoc """
  Human-readable telemetry logger for Portfolio events.
  Provides one-line setup for development and debugging.

  ## Usage

      # In application.ex or iex
      PortfolioIndex.Telemetry.Logger.attach()

      # With options
      PortfolioIndex.Telemetry.Logger.attach(
        level: :info,
        events: [:embedder, :vector_store],
        format: :json
      )

      # Detach when done
      PortfolioIndex.Telemetry.Logger.detach()

  ## Example Output

      [info] [Portfolio] embedder.embed completed in 42ms (1536 dims) model=text-embedding-3-small
      [info] [Portfolio] llm.complete completed in 1.23s [claude-sonnet-4] ok (156 chars) prompt=892chars
      [info] [Portfolio] rag.rewrite completed in 235ms ("What is Elixir?")
      [info] [Portfolio] rag.search completed in 156ms (25 chunks)
      [info] [Portfolio] rag.rerank completed in 312ms (10/25 kept)
      [info] [Portfolio] vector_store.search completed in 42ms (15 results)
  """

  require Logger

  @type log_level :: :debug | :info | :warning | :error
  @type format :: :text | :json

  @type opts :: [
          level: log_level(),
          events: [atom()] | :all,
          format: format(),
          handler_id: atom()
        ]

  @default_handler_id :portfolio_telemetry_logger

  # All stop events we handle
  @stop_events [
    # Embedder events
    [:portfolio, :embedder, :embed, :stop],
    [:portfolio, :embedder, :embed_batch, :stop],
    # Vector store events
    [:portfolio, :vector_store, :search, :stop],
    [:portfolio, :vector_store, :insert, :stop],
    [:portfolio, :vector_store, :insert_batch, :stop],
    # LLM events
    [:portfolio, :llm, :complete, :stop],
    # RAG pipeline events
    [:portfolio, :rag, :rewrite, :stop],
    [:portfolio, :rag, :expand, :stop],
    [:portfolio, :rag, :decompose, :stop],
    [:portfolio, :rag, :select, :stop],
    [:portfolio, :rag, :search, :stop],
    [:portfolio, :rag, :rerank, :stop],
    [:portfolio, :rag, :answer, :stop],
    [:portfolio, :rag, :self_correct, :stop],
    # Evaluation events
    [:portfolio, :evaluation, :run, :stop],
    [:portfolio, :evaluation, :test_case, :stop]
  ]

  @doc """
  Attach the telemetry logger to all Portfolio events.

  ## Options

    * `:level` - The log level to use (default: `:info`)
    * `:events` - List of components to log (`:embedder`, `:vector_store`, `:llm`, `:rag`, `:evaluation`)
      or `:all` for all events (default: `:all`)
    * `:format` - Output format: `:text` or `:json` (default: `:text`)
    * `:handler_id` - Custom handler ID (default: `:portfolio_telemetry_logger`)
  """
  @spec attach(opts()) :: :ok | {:error, term()}
  def attach(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, @default_handler_id)
    level = Keyword.get(opts, :level, :info)
    format = Keyword.get(opts, :format, :text)
    event_filter = Keyword.get(opts, :events, :all)

    events = filter_events(event_filter)

    config = %{
      level: level,
      format: format,
      handler_id: handler_id
    }

    :telemetry.attach_many(
      handler_id,
      events,
      &__MODULE__.handle_event/4,
      config
    )
  end

  @doc """
  Detach the telemetry logger.
  """
  @spec detach(atom()) :: :ok | {:error, term()}
  def detach(handler_id \\ @default_handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Check if logger is attached.
  """
  @spec attached?(atom()) :: boolean()
  def attached?(handler_id \\ @default_handler_id) do
    handlers = :telemetry.list_handlers(@stop_events |> List.first())

    Enum.any?(handlers, fn %{id: id} ->
      id == handler_id
    end)
  end

  @doc """
  Format an event for logging.
  """
  @spec format_event([atom()], map(), map(), format()) :: String.t()
  def format_event(event, measurements, metadata, format) do
    case format do
      :json -> format_json(event, measurements, metadata)
      _ -> format_text(event, measurements, metadata)
    end
  end

  @doc false
  def handle_event(event, measurements, metadata, config) do
    message = format_event(event, measurements, metadata, config.format)
    Logger.log(config.level, message)
  end

  # Private functions

  defp filter_events(:all), do: @stop_events

  defp filter_events(components) when is_list(components) do
    Enum.flat_map(components, fn component ->
      Enum.filter(@stop_events, fn [_, comp | _] ->
        comp == component
      end)
    end)
  end

  defp format_text(event, measurements, metadata) do
    duration = format_duration(measurements[:duration])
    event_name = format_event_name(event)
    details = extract_details(event_name, metadata)

    if details != "" do
      "[Portfolio] #{event_name} completed in #{duration} #{details}"
    else
      "[Portfolio] #{event_name} completed in #{duration}"
    end
  end

  defp format_json(event, measurements, metadata) do
    duration_ms =
      case measurements[:duration] do
        nil -> nil
        dur -> System.convert_time_unit(dur, :native, :millisecond)
      end

    data = %{
      event: Enum.join(event, "."),
      duration_ms: duration_ms,
      metadata: metadata
    }

    Jason.encode!(data)
  end

  defp format_duration(nil), do: "?"

  defp format_duration(duration_ns) do
    duration_ms = System.convert_time_unit(duration_ns, :native, :millisecond)

    cond do
      duration_ms >= 1000 -> "#{Float.round(duration_ms / 1000, 2)}s"
      duration_ms >= 1 -> "#{duration_ms}ms"
      true -> "<1ms"
    end
  end

  defp format_event_name([:portfolio | rest]) do
    rest
    |> Enum.reject(&(&1 == :stop))
    |> Enum.map_join(".", &Atom.to_string/1)
  end

  defp format_event_name(event) do
    event
    |> Enum.reject(&(&1 == :stop))
    |> Enum.map_join(".", &Atom.to_string/1)
  end

  defp extract_details("embedder.embed", meta) do
    dims = meta[:dimensions] || "?"
    model = meta[:model]

    if model do
      "(#{dims} dims) model=#{model}"
    else
      "(#{dims} dims)"
    end
  end

  defp extract_details("embedder.embed_batch", meta) do
    count = meta[:count] || meta[:batch_size] || "?"
    "(#{count} texts)"
  end

  defp extract_details("vector_store.search", meta) do
    count = meta[:result_count] || meta[:results] || "?"
    mode = meta[:mode]

    if mode do
      "(#{count} results, mode=#{mode})"
    else
      "(#{count} results)"
    end
  end

  defp extract_details("vector_store.insert", _meta), do: ""

  defp extract_details("vector_store.insert_batch", meta) do
    count = meta[:count] || "?"
    "(#{count} items)"
  end

  defp extract_details("llm.complete", meta) do
    model = meta[:model] || "?"
    prompt_len = meta[:prompt_length] || "?"
    status = if meta[:success] != false, do: "ok", else: "error"

    response_info =
      if meta[:success] != false do
        "(#{meta[:response_length] || "?"} chars)"
      else
        error_str = to_string(meta[:error] || "unknown error")

        truncated =
          if String.length(error_str) > 100,
            do: String.slice(error_str, 0, 100) <> "...",
            else: error_str

        "(#{truncated})"
      end

    "[#{model}] #{status} #{response_info} prompt=#{prompt_len}chars"
  end

  defp extract_details("rag.rewrite", meta) do
    case meta[:query] || meta[:rewritten_query] do
      query when is_binary(query) and byte_size(query) > 0 ->
        preview = String.slice(query, 0, 40)
        if String.length(query) > 40, do: "(\"#{preview}...\")", else: "(\"#{preview}\")"

      _ ->
        ""
    end
  end

  defp extract_details("rag.select", meta) do
    count = length(meta[:selected] || meta[:selected_indexes] || [])
    "(#{count} collection#{if count == 1, do: "", else: "s"})"
  end

  defp extract_details("rag.expand", meta) do
    case meta[:expanded_query] do
      nil ->
        "(no expansion)"

      query when is_binary(query) ->
        preview = String.slice(query, 0, 50)
        if String.length(query) > 50, do: "(\"#{preview}...\")", else: "(\"#{preview}\")"

      _ ->
        ""
    end
  end

  defp extract_details("rag.decompose", meta) do
    count = meta[:sub_question_count] || length(meta[:sub_questions] || [])
    "(#{count} subquestion#{if count == 1, do: "", else: "s"})"
  end

  defp extract_details("rag.search", meta) do
    count = meta[:result_count] || meta[:total_chunks] || length(meta[:results] || [])
    "(#{count} chunks)"
  end

  defp extract_details("rag.rerank", meta) do
    kept = meta[:kept] || meta[:output_count] || "?"
    original = meta[:original] || meta[:input_count] || "?"
    "(#{kept}/#{original} kept)"
  end

  defp extract_details("rag.answer", _meta), do: ""

  defp extract_details("rag.self_correct", meta) do
    attempt = meta[:attempt] || meta[:correction_count] || "?"
    "(attempt #{attempt})"
  end

  defp extract_details("evaluation.run", meta) do
    count = meta[:test_case_count] || "?"
    "(#{count} test cases)"
  end

  defp extract_details("evaluation.test_case", meta) do
    id = meta[:test_case_id] || meta[:id] || "?"
    "(id=#{id})"
  end

  defp extract_details(_event, _meta), do: ""
end
