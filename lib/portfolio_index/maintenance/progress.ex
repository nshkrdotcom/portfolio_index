defmodule PortfolioIndex.Maintenance.Progress do
  @moduledoc """
  Progress reporting utilities for maintenance operations.
  Provides callbacks for CLI and programmatic progress tracking.

  ## Usage

  Progress reporters are functions that receive progress events and can be
  used to display progress in different ways:

  - `cli_reporter/1` - Prints progress to stdout
  - `silent_reporter/0` - No-op reporter for silent operations
  - `telemetry_reporter/1` - Emits telemetry events for monitoring

  ## Example

      # Using CLI reporter
      Maintenance.reembed(repo, on_progress: Progress.cli_reporter())

      # Using telemetry reporter
      Maintenance.reembed(repo, on_progress: Progress.telemetry_reporter([:my_app, :maintenance]))

      # Custom reporter
      Maintenance.reembed(repo, on_progress: fn event ->
        Logger.info("Progress: \#{event.current}/\#{event.total}")
        :ok
      end)
  """

  @type progress_callback :: (map() -> :ok) | nil

  @type progress_event :: %{
          operation: atom(),
          current: non_neg_integer(),
          total: non_neg_integer(),
          percentage: float(),
          message: String.t() | nil
        }

  @doc """
  Create a CLI progress reporter that prints to stdout.

  ## Options

  - `:quiet` - If true, suppresses all output (default: false)
  - `:prefix` - String prefix for progress messages (default: "Progress")

  ## Example

      reporter = Progress.cli_reporter()
      reporter.(%{operation: :reembed, current: 5, total: 10, percentage: 50.0, message: nil})
      # Prints: Progress: 5/10 (50.0%)
  """
  @spec cli_reporter(keyword()) :: progress_callback()
  def cli_reporter(opts \\ []) do
    quiet = Keyword.get(opts, :quiet, false)
    prefix = Keyword.get(opts, :prefix, "Progress")

    fn event ->
      unless quiet do
        message_part = if event.message, do: " - #{event.message}", else: ""
        percentage_str = :erlang.float_to_binary(event.percentage, decimals: 1)

        IO.puts("#{prefix}: #{event.current}/#{event.total} (#{percentage_str}%)#{message_part}")
      end

      :ok
    end
  end

  @doc """
  Create a silent reporter (no-op).

  Useful for programmatic usage where progress output is not desired.

  ## Example

      reporter = Progress.silent_reporter()
      reporter.(%{current: 5, total: 10})
      # Does nothing, returns :ok
  """
  @spec silent_reporter() :: progress_callback()
  def silent_reporter do
    fn _event -> :ok end
  end

  @doc """
  Create a telemetry-emitting reporter.

  Emits telemetry events that can be consumed by monitoring systems.

  ## Parameters

  - `event_prefix` - List of atoms forming the event prefix

  ## Events

  Emits `event_prefix ++ [:progress]` with:
  - Measurements: `current`, `total`, `percentage`
  - Metadata: `operation`, `message`

  ## Example

      reporter = Progress.telemetry_reporter([:my_app, :maintenance])
      # Emits [:my_app, :maintenance, :progress] events
  """
  @spec telemetry_reporter(list(atom())) :: progress_callback()
  def telemetry_reporter(event_prefix) when is_list(event_prefix) do
    fn event ->
      :telemetry.execute(
        event_prefix ++ [:progress],
        %{
          current: event.current,
          total: event.total,
          percentage: event.percentage
        },
        %{
          operation: event.operation,
          message: event.message
        }
      )

      :ok
    end
  end

  @doc """
  Report a progress event using the given callback.

  ## Parameters

  - `callback` - Progress callback function (can be nil)
  - `event` - Progress event map

  ## Example

      Progress.report(my_callback, %{
        operation: :reembed,
        current: 5,
        total: 10,
        percentage: 50.0,
        message: "Processing batch 1"
      })
  """
  @spec report(progress_callback(), progress_event()) :: :ok
  def report(nil, _event), do: :ok

  def report(callback, event) when is_function(callback, 1) do
    callback.(event)
  end

  @doc """
  Report progress by building an event from operation, current, and total.

  ## Parameters

  - `callback` - Progress callback function (can be nil)
  - `operation` - Atom identifying the operation
  - `current` - Current progress count
  - `total` - Total count

  ## Example

      Progress.report(my_callback, :reembed, 5, 10)
      # Builds event with 50.0% and reports it
  """
  @spec report(progress_callback(), atom(), non_neg_integer(), non_neg_integer()) :: :ok
  def report(callback, operation, current, total) do
    event = build_event(operation, current, total)
    report(callback, event)
  end

  @doc """
  Build a progress event from components.

  ## Parameters

  - `operation` - Atom identifying the operation
  - `current` - Current progress count
  - `total` - Total count
  - `message` - Optional message (default: nil)

  ## Example

      event = Progress.build_event(:reembed, 5, 10, "Processing batch")
      # => %{operation: :reembed, current: 5, total: 10, percentage: 50.0, message: "Processing batch"}
  """
  @spec build_event(atom(), non_neg_integer(), non_neg_integer(), String.t() | nil) ::
          progress_event()
  def build_event(operation, current, total, message \\ nil) do
    percentage =
      if total > 0 do
        current / total * 100.0
      else
        0.0
      end

    %{
      operation: operation,
      current: current,
      total: total,
      percentage: percentage,
      message: message
    }
  end
end
