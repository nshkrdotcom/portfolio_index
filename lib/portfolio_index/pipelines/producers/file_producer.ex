defmodule PortfolioIndex.Pipelines.Producers.FileProducer do
  @moduledoc """
  Broadway producer that discovers and emits files for processing.

  ## Configuration

      producer: [
        module: {FileProducer, [
          paths: ["/path/to/docs"],
          patterns: ["**/*.md", "**/*.ex"],
          poll_interval: 60_000
        ]}
      ]
  """

  use GenStage
  require Logger

  alias Broadway.{Message, NoopAcknowledger}

  @default_poll_interval 60_000
  @default_patterns ["**/*"]

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    paths = Keyword.get(opts, :paths, [])
    patterns = Keyword.get(opts, :patterns, @default_patterns)
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)

    state = %{
      paths: paths,
      patterns: patterns,
      poll_interval: poll_interval,
      pending: :queue.new(),
      demand: 0,
      processed_hashes: MapSet.new()
    }

    # Schedule initial file discovery
    send(self(), :discover_files)

    {:producer, state}
  end

  @impl true
  def handle_demand(demand, state) do
    {events, new_state} = take_events(state.demand + demand, state)
    {:noreply, to_messages(events), %{new_state | demand: new_state.demand}}
  end

  @impl true
  def handle_info(:discover_files, state) do
    files = discover_files(state.paths, state.patterns, state.processed_hashes)

    # Add new files to pending queue
    new_pending =
      Enum.reduce(files, state.pending, fn file, queue ->
        :queue.in(file, queue)
      end)

    # Update processed hashes
    new_hashes =
      Enum.reduce(files, state.processed_hashes, fn file, set ->
        MapSet.put(set, file.hash)
      end)

    # Schedule next poll
    Process.send_after(self(), :discover_files, state.poll_interval)

    # Try to fulfill pending demand
    {events, new_state} =
      take_events(state.demand, %{state | pending: new_pending, processed_hashes: new_hashes})

    {:noreply, to_messages(events), new_state}
  end

  # Private functions

  defp discover_files(paths, patterns, processed_hashes) do
    paths
    |> Enum.flat_map(fn path ->
      patterns
      |> Enum.flat_map(fn pattern ->
        full_pattern = Path.join(path, pattern)
        Path.wildcard(full_pattern)
      end)
    end)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&build_file_info/1)
    |> Enum.reject(fn file -> MapSet.member?(processed_hashes, file.hash) end)
  end

  defp build_file_info(path) do
    stat = File.stat!(path)
    content_hash = hash_file(path)

    %{
      path: path,
      type: detect_type(path),
      size: stat.size,
      mtime: stat.mtime,
      hash: content_hash
    }
  end

  defp hash_file(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
  end

  @extension_types %{
    ".ex" => :elixir,
    ".exs" => :elixir,
    ".md" => :markdown,
    ".html" => :html,
    ".txt" => :plain,
    ".json" => :json,
    ".yaml" => :yaml,
    ".yml" => :yaml
  }

  defp detect_type(path) do
    Map.get(@extension_types, Path.extname(path), :plain)
  end

  defp take_events(demand, state) when demand > 0 do
    case :queue.out(state.pending) do
      {{:value, event}, new_queue} ->
        {more_events, final_state} = take_events(demand - 1, %{state | pending: new_queue})
        {[event | more_events], final_state}

      {:empty, _queue} ->
        {[], %{state | demand: demand}}
    end
  end

  defp take_events(_demand, state), do: {[], state}

  defp to_messages(events) do
    acknowledger = NoopAcknowledger.init()

    Enum.map(events, fn event ->
      %Message{data: event, acknowledger: acknowledger}
    end)
  end
end
