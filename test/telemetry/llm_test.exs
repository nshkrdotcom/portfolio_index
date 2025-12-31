defmodule PortfolioIndex.Telemetry.LLMTest do
  use ExUnit.Case, async: false

  alias PortfolioIndex.Telemetry.LLM

  defmodule TestHandler do
    def handle_event(event, measurements, metadata, %{parent: parent}) do
      send(parent, {:telemetry, event, measurements, metadata})
    end
  end

  setup do
    on_exit(fn ->
      # Clean up any attached handlers
      :telemetry.list_handlers([:portfolio, :llm, :complete, :stop])
      |> Enum.each(fn %{id: id} ->
        :telemetry.detach(id)
      end)
    end)

    :ok
  end

  describe "span/2" do
    test "emits start and stop events" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-llm-span-#{inspect(ref)}",
        [
          [:portfolio, :llm, :complete, :start],
          [:portfolio, :llm, :complete, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      result =
        LLM.span([model: "claude-sonnet-4", provider: :anthropic], fn ->
          {:ok, %{content: "Hello, world!", usage: %{input_tokens: 10, output_tokens: 5}}}
        end)

      assert {:ok, _} = result

      assert_receive {:telemetry, [:portfolio, :llm, :complete, :start], _, start_meta}
      assert start_meta[:model] == "claude-sonnet-4"
      assert start_meta[:provider] == :anthropic

      assert_receive {:telemetry, [:portfolio, :llm, :complete, :stop], stop_measurements,
                      stop_meta}

      assert stop_measurements[:duration] > 0
      assert stop_meta[:success] == true
      assert stop_meta[:response_length] == 13
      assert stop_meta[:input_tokens] == 10
      assert stop_meta[:output_tokens] == 5

      :telemetry.detach("test-llm-span-#{inspect(ref)}")
    end

    test "emits exception event on error" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-llm-exception-#{inspect(ref)}",
        [
          [:portfolio, :llm, :complete, :start],
          [:portfolio, :llm, :complete, :exception]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      assert_raise RuntimeError, fn ->
        LLM.span([model: "claude-sonnet-4"], fn ->
          raise "LLM error"
        end)
      end

      assert_receive {:telemetry, [:portfolio, :llm, :complete, :start], _, _}
      assert_receive {:telemetry, [:portfolio, :llm, :complete, :exception], _, meta}
      assert meta[:kind] == :error

      :telemetry.detach("test-llm-exception-#{inspect(ref)}")
    end

    test "tracks error responses" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-llm-error-response-#{inspect(ref)}",
        [
          [:portfolio, :llm, :complete, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      LLM.span([model: "claude-sonnet-4"], fn ->
        {:error, "Rate limited"}
      end)

      assert_receive {:telemetry, [:portfolio, :llm, :complete, :stop], _, stop_meta}
      assert stop_meta[:success] == false
      assert stop_meta[:error] == "Rate limited"

      :telemetry.detach("test-llm-error-response-#{inspect(ref)}")
    end

    test "enriches metadata with prompt tokens" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-llm-tokens-#{inspect(ref)}",
        [
          [:portfolio, :llm, :complete, :start]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      LLM.span([model: "gpt-4", prompt_length: 400], fn ->
        {:ok, %{content: "response"}}
      end)

      assert_receive {:telemetry, [:portfolio, :llm, :complete, :start], _, start_meta}
      assert start_meta[:prompt_length] == 400
      assert start_meta[:prompt_tokens] == 100

      :telemetry.detach("test-llm-tokens-#{inspect(ref)}")
    end

    test "handles string response" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-llm-string-#{inspect(ref)}",
        [
          [:portfolio, :llm, :complete, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      LLM.span([model: "gpt-4"], fn ->
        "Just a string response"
      end)

      assert_receive {:telemetry, [:portfolio, :llm, :complete, :stop], _, stop_meta}
      assert stop_meta[:success] == true
      assert stop_meta[:response_length] == 22

      :telemetry.detach("test-llm-string-#{inspect(ref)}")
    end
  end

  describe "estimate_tokens/1" do
    test "estimates tokens from text" do
      # ~4 chars per token
      assert LLM.estimate_tokens("Hello, world!") == 3
      assert LLM.estimate_tokens("This is a longer text with more words") == 9
    end

    test "returns 1 for short text" do
      assert LLM.estimate_tokens("Hi") == 1
    end

    test "handles empty string" do
      assert LLM.estimate_tokens("") == 0
    end

    test "handles nil" do
      assert LLM.estimate_tokens(nil) == 0
    end
  end

  describe "extract_usage/1" do
    test "extracts usage from standard format" do
      usage = LLM.extract_usage(%{usage: %{input_tokens: 100, output_tokens: 50}})

      assert usage[:input_tokens] == 100
      assert usage[:output_tokens] == 50
      assert usage[:total_tokens] == 150
    end

    test "extracts usage from OpenAI format" do
      usage = LLM.extract_usage(%{usage: %{prompt_tokens: 100, completion_tokens: 50}})

      assert usage[:input_tokens] == 100
      assert usage[:output_tokens] == 50
    end

    test "extracts usage from string-keyed map" do
      usage = LLM.extract_usage(%{"usage" => %{"input_tokens" => 100, "output_tokens" => 50}})

      assert usage[:input_tokens] == 100
      assert usage[:output_tokens] == 50
    end

    test "returns empty map for missing usage" do
      assert LLM.extract_usage(%{}) == %{}
      assert LLM.extract_usage(nil) == %{}
    end
  end
end
