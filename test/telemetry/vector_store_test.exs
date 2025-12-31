defmodule PortfolioIndex.Telemetry.VectorStoreTest do
  use ExUnit.Case, async: false

  alias PortfolioIndex.Telemetry.VectorStore

  defmodule TestHandler do
    def handle_event(event, measurements, metadata, %{parent: parent}) do
      send(parent, {:telemetry, event, measurements, metadata})
    end
  end

  describe "search_span/2" do
    test "emits start and stop events" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-vs-search-#{inspect(ref)}",
        [
          [:portfolio, :vector_store, :search, :start],
          [:portfolio, :vector_store, :search, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      result =
        VectorStore.search_span([backend: :pgvector, limit: 10, mode: :semantic], fn ->
          {:ok, [%{id: 1}, %{id: 2}, %{id: 3}]}
        end)

      assert {:ok, _} = result

      assert_receive {:telemetry, [:portfolio, :vector_store, :search, :start], _, start_meta}
      assert start_meta[:backend] == :pgvector
      assert start_meta[:limit] == 10
      assert start_meta[:mode] == :semantic

      assert_receive {:telemetry, [:portfolio, :vector_store, :search, :stop], stop_measurements,
                      stop_meta}

      assert stop_measurements[:duration] > 0
      assert stop_meta[:result_count] == 3

      :telemetry.detach("test-vs-search-#{inspect(ref)}")
    end

    test "handles direct list results" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-vs-search-list-#{inspect(ref)}",
        [[:portfolio, :vector_store, :search, :stop]],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      VectorStore.search_span([backend: :memory], fn ->
        [%{id: 1}, %{id: 2}]
      end)

      assert_receive {:telemetry, [:portfolio, :vector_store, :search, :stop], _, stop_meta}
      assert stop_meta[:result_count] == 2

      :telemetry.detach("test-vs-search-list-#{inspect(ref)}")
    end

    test "emits exception event on error" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-vs-exception-#{inspect(ref)}",
        [
          [:portfolio, :vector_store, :search, :start],
          [:portfolio, :vector_store, :search, :exception]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      assert_raise RuntimeError, fn ->
        VectorStore.search_span([backend: :pgvector], fn ->
          raise "Search error"
        end)
      end

      assert_receive {:telemetry, [:portfolio, :vector_store, :search, :start], _, _}
      assert_receive {:telemetry, [:portfolio, :vector_store, :search, :exception], _, meta}
      assert meta[:kind] == :error

      :telemetry.detach("test-vs-exception-#{inspect(ref)}")
    end
  end

  describe "insert_span/2" do
    test "emits start and stop events" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-vs-insert-#{inspect(ref)}",
        [
          [:portfolio, :vector_store, :insert, :start],
          [:portfolio, :vector_store, :insert, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      result =
        VectorStore.insert_span([backend: :pgvector, collection: "docs", id: "doc-1"], fn ->
          {:ok, %{id: "doc-1"}}
        end)

      assert {:ok, _} = result

      assert_receive {:telemetry, [:portfolio, :vector_store, :insert, :start], _, start_meta}
      assert start_meta[:backend] == :pgvector
      assert start_meta[:collection] == "docs"
      assert start_meta[:id] == "doc-1"

      assert_receive {:telemetry, [:portfolio, :vector_store, :insert, :stop], _, stop_meta}
      assert stop_meta[:success] == true

      :telemetry.detach("test-vs-insert-#{inspect(ref)}")
    end
  end

  describe "batch_insert_span/2" do
    test "emits start and stop events for batch" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-vs-batch-#{inspect(ref)}",
        [
          [:portfolio, :vector_store, :insert_batch, :start],
          [:portfolio, :vector_store, :insert_batch, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      result =
        VectorStore.batch_insert_span([backend: :pgvector, count: 50], fn ->
          {:ok, %{inserted: 50}}
        end)

      assert {:ok, _} = result

      assert_receive {:telemetry, [:portfolio, :vector_store, :insert_batch, :start], _,
                      start_meta}

      assert start_meta[:backend] == :pgvector
      assert start_meta[:count] == 50

      assert_receive {:telemetry, [:portfolio, :vector_store, :insert_batch, :stop], _, stop_meta}
      assert stop_meta[:success] == true
      assert stop_meta[:inserted_count] == 50

      :telemetry.detach("test-vs-batch-#{inspect(ref)}")
    end

    test "extracts count from items list" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-vs-batch-items-#{inspect(ref)}",
        [[:portfolio, :vector_store, :insert_batch, :start]],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      VectorStore.batch_insert_span([backend: :memory, items: [1, 2, 3, 4, 5]], fn ->
        :ok
      end)

      assert_receive {:telemetry, [:portfolio, :vector_store, :insert_batch, :start], _,
                      start_meta}

      assert start_meta[:count] == 5

      :telemetry.detach("test-vs-batch-items-#{inspect(ref)}")
    end
  end
end
