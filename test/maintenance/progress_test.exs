defmodule PortfolioIndex.Maintenance.ProgressTest do
  use PortfolioIndex.SupertesterCase, async: true

  alias PortfolioIndex.Maintenance.Progress

  describe "silent_reporter/0" do
    test "returns a function that does nothing" do
      reporter = Progress.silent_reporter()

      assert is_function(reporter, 1)

      # Should not raise and return :ok
      assert :ok = reporter.(%{current: 1, total: 10})
    end
  end

  describe "cli_reporter/1" do
    test "returns a function that prints to stdout" do
      reporter = Progress.cli_reporter([])

      assert is_function(reporter, 1)

      # Capture IO to verify it prints
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          reporter.(%{
            operation: :reembed,
            current: 5,
            total: 10,
            percentage: 50.0,
            message: nil
          })
        end)

      assert output =~ "5/10"
      assert output =~ "50"
    end

    test "includes custom message when provided" do
      reporter = Progress.cli_reporter([])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          reporter.(%{
            operation: :reembed,
            current: 3,
            total: 10,
            percentage: 30.0,
            message: "Processing batch"
          })
        end)

      assert output =~ "Processing batch"
    end

    test "respects quiet option" do
      reporter = Progress.cli_reporter(quiet: true)

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          reporter.(%{
            operation: :reembed,
            current: 5,
            total: 10,
            percentage: 50.0,
            message: nil
          })
        end)

      assert output == ""
    end
  end

  describe "telemetry_reporter/1" do
    test "returns a function that emits telemetry events" do
      event_prefix = [:test, :progress]
      reporter = Progress.telemetry_reporter(event_prefix)

      assert is_function(reporter, 1)

      # Attach a handler to capture the event
      test_pid = self()

      :telemetry.attach(
        "test-progress-handler",
        event_prefix ++ [:progress],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

      reporter.(%{
        operation: :reembed,
        current: 5,
        total: 10,
        percentage: 50.0,
        message: "Testing"
      })

      assert_receive {:telemetry_event, [:test, :progress, :progress], measurements, metadata}
      assert measurements.current == 5
      assert measurements.total == 10
      assert measurements.percentage == 50.0
      assert metadata.operation == :reembed
      assert metadata.message == "Testing"

      :telemetry.detach("test-progress-handler")
    end
  end

  describe "report/2" do
    test "calls the callback with the event" do
      test_pid = self()

      callback = fn event ->
        send(test_pid, {:progress, event})
        :ok
      end

      event = %{
        operation: :reembed,
        current: 1,
        total: 5,
        percentage: 20.0,
        message: nil
      }

      assert :ok = Progress.report(callback, event)
      assert_receive {:progress, ^event}
    end

    test "handles nil callback gracefully" do
      event = %{
        operation: :reembed,
        current: 1,
        total: 5,
        percentage: 20.0,
        message: nil
      }

      assert :ok = Progress.report(nil, event)
    end

    test "builds event from current and total" do
      test_pid = self()

      callback = fn event ->
        send(test_pid, {:progress, event})
        :ok
      end

      assert :ok = Progress.report(callback, :reembed, 3, 6)

      assert_receive {:progress, event}
      assert event.operation == :reembed
      assert event.current == 3
      assert event.total == 6
      assert event.percentage == 50.0
    end

    test "calculates correct percentage" do
      test_pid = self()

      callback = fn event ->
        send(test_pid, {:progress, event})
        :ok
      end

      Progress.report(callback, :test, 1, 3)
      assert_receive {:progress, %{percentage: percentage}}
      # 1/3 = 33.33...%
      assert_in_delta percentage, 33.33, 0.1
    end
  end

  describe "build_event/4" do
    test "creates a progress event struct" do
      event = Progress.build_event(:reembed, 5, 10, "Processing")

      assert event.operation == :reembed
      assert event.current == 5
      assert event.total == 10
      assert event.percentage == 50.0
      assert event.message == "Processing"
    end

    test "handles zero total gracefully" do
      event = Progress.build_event(:reembed, 0, 0, nil)

      assert event.current == 0
      assert event.total == 0
      assert event.percentage == 0.0
    end

    test "defaults message to nil" do
      event = Progress.build_event(:reembed, 1, 5)

      assert event.message == nil
    end
  end
end
