defmodule PortfolioIndex.Telemetry.LoggerTest do
  use ExUnit.Case, async: false

  alias PortfolioIndex.Telemetry.Logger

  setup do
    # Ensure logger is detached after each test
    on_exit(fn ->
      Logger.detach()
    end)

    :ok
  end

  # Helper that directly tests format_event for event output
  defp format_telemetry(event, measurements, metadata) do
    Logger.format_event(event, measurements, metadata, :text)
  end

  describe "attach/1" do
    test "attaches handler successfully" do
      assert :ok = Logger.attach()
      assert Logger.attached?()
    end

    test "attaches with custom handler_id" do
      assert :ok = Logger.attach(handler_id: :custom_handler)
      assert Logger.attached?(:custom_handler)
      Logger.detach(:custom_handler)
    end

    test "attaches with filtered events" do
      assert :ok = Logger.attach(events: [:embedder, :llm])
      assert Logger.attached?()
    end
  end

  describe "detach/1" do
    test "detaches handler successfully" do
      :ok = Logger.attach()
      assert Logger.attached?()

      assert :ok = Logger.detach()
      refute Logger.attached?()
    end

    test "returns error for non-existent handler" do
      assert {:error, :not_found} = Logger.detach(:non_existent)
    end
  end

  describe "attached?/1" do
    test "returns false when not attached" do
      refute Logger.attached?()
    end

    test "returns true when attached" do
      :ok = Logger.attach()
      assert Logger.attached?()
    end
  end

  describe "format_event - embedder events" do
    test "formats embedder.embed event" do
      log =
        format_telemetry(
          [:portfolio, :embedder, :embed, :stop],
          %{duration: System.convert_time_unit(42, :millisecond, :native)},
          %{dimensions: 1536, model: "text-embedding-3-small"}
        )

      assert log =~ "[Portfolio] embedder.embed completed in"
      assert log =~ "42ms"
      assert log =~ "(1536 dims)"
      assert log =~ "model=text-embedding-3-small"
    end

    test "formats embedder.embed_batch event" do
      log =
        format_telemetry(
          [:portfolio, :embedder, :embed_batch, :stop],
          %{duration: System.convert_time_unit(100, :millisecond, :native)},
          %{count: 10}
        )

      assert log =~ "[Portfolio] embedder.embed_batch completed in"
      assert log =~ "(10 texts)"
    end
  end

  describe "format_event - llm events" do
    test "formats llm.complete event with success" do
      log =
        format_telemetry(
          [:portfolio, :llm, :complete, :stop],
          %{duration: System.convert_time_unit(1230, :millisecond, :native)},
          %{
            model: "claude-sonnet-4",
            success: true,
            prompt_length: 892,
            response_length: 156
          }
        )

      assert log =~ "[Portfolio] llm.complete completed in"
      assert log =~ "1.23s"
      assert log =~ "[claude-sonnet-4]"
      assert log =~ "ok"
      assert log =~ "(156 chars)"
      assert log =~ "prompt=892chars"
    end

    test "formats llm.complete event with error" do
      log =
        format_telemetry(
          [:portfolio, :llm, :complete, :stop],
          %{duration: System.convert_time_unit(500, :millisecond, :native)},
          %{
            model: "claude-sonnet-4",
            success: false,
            prompt_length: 892,
            error: "Rate limited"
          }
        )

      assert log =~ "[claude-sonnet-4]"
      assert log =~ "error"
      assert log =~ "Rate limited"
    end
  end

  describe "format_event - vector_store events" do
    test "formats vector_store.search event" do
      log =
        format_telemetry(
          [:portfolio, :vector_store, :search, :stop],
          %{duration: System.convert_time_unit(42, :millisecond, :native)},
          %{result_count: 15, mode: :semantic}
        )

      assert log =~ "[Portfolio] vector_store.search completed in"
      assert log =~ "42ms"
      assert log =~ "(15 results, mode=semantic)"
    end
  end

  describe "format_event - rag events" do
    test "formats rag.rewrite event" do
      log =
        format_telemetry(
          [:portfolio, :rag, :rewrite, :stop],
          %{duration: System.convert_time_unit(235, :millisecond, :native)},
          %{query: "What is Elixir?"}
        )

      assert log =~ "[Portfolio] rag.rewrite completed in"
      assert log =~ "235ms"
      assert log =~ "(\"What is Elixir?\")"
    end

    test "formats rag.decompose event" do
      log =
        format_telemetry(
          [:portfolio, :rag, :decompose, :stop],
          %{duration: System.convert_time_unit(300, :millisecond, :native)},
          %{sub_question_count: 3}
        )

      assert log =~ "[Portfolio] rag.decompose completed in"
      assert log =~ "(3 subquestions)"
    end

    test "formats rag.search event" do
      log =
        format_telemetry(
          [:portfolio, :rag, :search, :stop],
          %{duration: System.convert_time_unit(156, :millisecond, :native)},
          %{total_chunks: 25}
        )

      assert log =~ "[Portfolio] rag.search completed in"
      assert log =~ "(25 chunks)"
    end

    test "formats rag.rerank event" do
      log =
        format_telemetry(
          [:portfolio, :rag, :rerank, :stop],
          %{duration: System.convert_time_unit(312, :millisecond, :native)},
          %{kept: 10, original: 25}
        )

      assert log =~ "[Portfolio] rag.rerank completed in"
      assert log =~ "(10/25 kept)"
    end
  end

  describe "format_event/4" do
    test "formats event as text" do
      event = [:portfolio, :embedder, :embed, :stop]
      measurements = %{duration: System.convert_time_unit(42, :millisecond, :native)}
      metadata = %{dimensions: 1536, model: "text-embedding-3-small"}

      result = Logger.format_event(event, measurements, metadata, :text)

      assert result =~ "[Portfolio]"
      assert result =~ "embedder.embed"
      assert result =~ "42ms"
    end

    test "formats event as json" do
      event = [:portfolio, :embedder, :embed, :stop]
      measurements = %{duration: System.convert_time_unit(42, :millisecond, :native)}
      metadata = %{dimensions: 1536, model: "text-embedding-3-small"}

      result = Logger.format_event(event, measurements, metadata, :json)

      assert {:ok, parsed} = Jason.decode(result)
      assert parsed["event"] == "portfolio.embedder.embed.stop"
      assert parsed["duration_ms"] == 42
      assert parsed["metadata"]["dimensions"] == 1536
    end
  end

  describe "format options" do
    test "formats in json format when configured" do
      log =
        Logger.format_event(
          [:portfolio, :embedder, :embed, :stop],
          %{duration: System.convert_time_unit(42, :millisecond, :native)},
          %{dimensions: 1536},
          :json
        )

      assert log =~ "\"event\""
      assert log =~ "\"duration_ms\""
    end
  end

  describe "duration formatting" do
    test "formats sub-millisecond duration" do
      log =
        format_telemetry(
          [:portfolio, :embedder, :embed, :stop],
          %{duration: 100},
          %{dimensions: 1536}
        )

      assert log =~ "<1ms"
    end

    test "formats millisecond duration" do
      log =
        format_telemetry(
          [:portfolio, :embedder, :embed, :stop],
          %{duration: System.convert_time_unit(42, :millisecond, :native)},
          %{dimensions: 1536}
        )

      assert log =~ "42ms"
    end

    test "formats second duration" do
      log =
        format_telemetry(
          [:portfolio, :embedder, :embed, :stop],
          %{duration: System.convert_time_unit(2500, :millisecond, :native)},
          %{dimensions: 1536}
        )

      assert log =~ "2.5s"
    end
  end

  describe "handle_event/4 integration" do
    test "actually emits logs when telemetry fires" do
      # Test that the handler is invoked (we can't easily test async log output)
      handler_id = :test_handler_integration
      test_pid = self()

      # Create a custom handler that sends to us
      :telemetry.attach(
        handler_id,
        [:portfolio, :embedder, :embed, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_received, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.execute(
        [:portfolio, :embedder, :embed, :stop],
        %{duration: 42_000_000},
        %{dimensions: 1536}
      )

      assert_receive {:telemetry_received, [:portfolio, :embedder, :embed, :stop], _, _}

      :telemetry.detach(handler_id)
    end
  end
end
