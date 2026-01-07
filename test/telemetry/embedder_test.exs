defmodule PortfolioIndex.Telemetry.EmbedderTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias PortfolioIndex.Telemetry.Embedder

  defmodule TestHandler do
    def handle_event(event, measurements, metadata, %{parent: parent}) do
      send(parent, {:telemetry, event, measurements, metadata})
    end
  end

  describe "span/2" do
    test "emits start and stop events" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-embedder-span-#{inspect(ref)}",
        [
          [:portfolio, :embedder, :embed, :start],
          [:portfolio, :embedder, :embed, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      result =
        Embedder.span([model: "text-embedding-3-small", provider: :openai], fn ->
          {:ok, %{vector: [0.1, 0.2, 0.3], dimensions: 3, token_count: 5}}
        end)

      assert {:ok, _} = result

      assert_receive {:telemetry, [:portfolio, :embedder, :embed, :start], _, start_meta}
      assert start_meta[:model] == "text-embedding-3-small"
      assert start_meta[:provider] == :openai

      assert_receive {:telemetry, [:portfolio, :embedder, :embed, :stop], stop_measurements,
                      stop_meta}

      assert stop_measurements[:duration] > 0
      assert stop_meta[:dimensions] == 3
      assert stop_meta[:token_count] == 5

      :telemetry.detach("test-embedder-span-#{inspect(ref)}")
    end

    test "extracts text length from text" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-embedder-text-#{inspect(ref)}",
        [[:portfolio, :embedder, :embed, :start]],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      Embedder.span([model: "test", text: "Hello, world!"], fn ->
        {:ok, %{vector: [0.1], dimensions: 1}}
      end)

      assert_receive {:telemetry, [:portfolio, :embedder, :embed, :start], _, start_meta}
      assert start_meta[:text_length] == 13

      :telemetry.detach("test-embedder-text-#{inspect(ref)}")
    end

    test "emits exception event on error" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-embedder-exception-#{inspect(ref)}",
        [
          [:portfolio, :embedder, :embed, :start],
          [:portfolio, :embedder, :embed, :exception]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      assert_raise RuntimeError, fn ->
        Embedder.span([model: "test"], fn ->
          raise "Embedding error"
        end)
      end

      assert_receive {:telemetry, [:portfolio, :embedder, :embed, :start], _, _}
      assert_receive {:telemetry, [:portfolio, :embedder, :embed, :exception], _, meta}
      assert meta[:kind] == :error

      :telemetry.detach("test-embedder-exception-#{inspect(ref)}")
    end
  end

  describe "batch_span/2" do
    test "emits start and stop events for batch" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-embedder-batch-#{inspect(ref)}",
        [
          [:portfolio, :embedder, :embed_batch, :start],
          [:portfolio, :embedder, :embed_batch, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      result =
        Embedder.batch_span([model: "text-embedding-3-small", batch_size: 10], fn ->
          {:ok, %{embeddings: List.duplicate(%{vector: [0.1]}, 10), total_tokens: 50}}
        end)

      assert {:ok, _} = result

      assert_receive {:telemetry, [:portfolio, :embedder, :embed_batch, :start], _, start_meta}
      assert start_meta[:model] == "text-embedding-3-small"
      assert start_meta[:batch_size] == 10

      assert_receive {:telemetry, [:portfolio, :embedder, :embed_batch, :stop], _, stop_meta}
      assert stop_meta[:count] == 10
      assert stop_meta[:total_tokens] == 50

      :telemetry.detach("test-embedder-batch-#{inspect(ref)}")
    end

    test "extracts batch size from texts list" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-embedder-batch-texts-#{inspect(ref)}",
        [[:portfolio, :embedder, :embed_batch, :start]],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      Embedder.batch_span([model: "test", texts: ["a", "b", "c"]], fn ->
        {:ok, %{embeddings: []}}
      end)

      assert_receive {:telemetry, [:portfolio, :embedder, :embed_batch, :start], _, start_meta}
      assert start_meta[:batch_size] == 3

      :telemetry.detach("test-embedder-batch-texts-#{inspect(ref)}")
    end
  end
end
