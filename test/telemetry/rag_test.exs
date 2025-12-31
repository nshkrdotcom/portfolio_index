defmodule PortfolioIndex.Telemetry.RAGTest do
  use ExUnit.Case, async: false

  alias PortfolioIndex.RAG.Pipeline.Context
  alias PortfolioIndex.Telemetry.RAG

  defmodule TestHandler do
    def handle_event(event, measurements, metadata, %{parent: parent}) do
      send(parent, {:telemetry, event, measurements, metadata})
    end
  end

  describe "step_span/3" do
    test "emits start and stop events for rewrite step" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-rag-rewrite-#{inspect(ref)}",
        [
          [:portfolio, :rag, :rewrite, :start],
          [:portfolio, :rag, :rewrite, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      ctx = Context.new("What is Elixir?")

      result_ctx =
        RAG.step_span(:rewrite, ctx, fn c ->
          %{c | rewritten_query: "elixir programming language"}
        end)

      assert result_ctx.rewritten_query == "elixir programming language"

      assert_receive {:telemetry, [:portfolio, :rag, :rewrite, :start], _, start_meta}
      assert start_meta[:step] == :rewrite
      assert start_meta[:question] == "What is Elixir?"

      assert_receive {:telemetry, [:portfolio, :rag, :rewrite, :stop], stop_measurements,
                      stop_meta}

      assert stop_measurements[:duration] > 0
      assert stop_meta[:query] == "elixir programming language"
      assert stop_meta[:success] == true

      :telemetry.detach("test-rag-rewrite-#{inspect(ref)}")
    end

    test "emits events for decompose step" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-rag-decompose-#{inspect(ref)}",
        [
          [:portfolio, :rag, :decompose, :start],
          [:portfolio, :rag, :decompose, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      ctx = Context.new("Compare Elixir and Go")

      result_ctx =
        RAG.step_span(:decompose, ctx, fn c ->
          %{c | sub_questions: ["What is Elixir?", "What is Go?"]}
        end)

      assert length(result_ctx.sub_questions) == 2

      assert_receive {:telemetry, [:portfolio, :rag, :decompose, :start], _, _}
      assert_receive {:telemetry, [:portfolio, :rag, :decompose, :stop], _, stop_meta}
      assert stop_meta[:sub_question_count] == 2

      :telemetry.detach("test-rag-decompose-#{inspect(ref)}")
    end

    test "emits exception event on error" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-rag-exception-#{inspect(ref)}",
        [
          [:portfolio, :rag, :rewrite, :start],
          [:portfolio, :rag, :rewrite, :exception]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      ctx = Context.new("Test question")

      assert_raise RuntimeError, fn ->
        RAG.step_span(:rewrite, ctx, fn _c ->
          raise "Pipeline error"
        end)
      end

      assert_receive {:telemetry, [:portfolio, :rag, :rewrite, :start], _, _}
      assert_receive {:telemetry, [:portfolio, :rag, :rewrite, :exception], _, meta}
      assert meta[:kind] == :error

      :telemetry.detach("test-rag-exception-#{inspect(ref)}")
    end
  end

  describe "search_span/3" do
    test "emits start and stop events for search" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-rag-search-#{inspect(ref)}",
        [
          [:portfolio, :rag, :search, :start],
          [:portfolio, :rag, :search, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      ctx = Context.new("What is Elixir?")

      results =
        RAG.search_span(ctx, [mode: :hybrid, collections: ["docs"], limit: 10], fn ->
          [%{id: 1, content: "Elixir is..."}, %{id: 2, content: "More about Elixir"}]
        end)

      assert length(results) == 2

      assert_receive {:telemetry, [:portfolio, :rag, :search, :start], _, start_meta}
      assert start_meta[:mode] == :hybrid
      assert start_meta[:collections] == ["docs"]
      assert start_meta[:limit] == 10

      assert_receive {:telemetry, [:portfolio, :rag, :search, :stop], _, stop_meta}
      assert stop_meta[:result_count] == 2

      :telemetry.detach("test-rag-search-#{inspect(ref)}")
    end
  end

  describe "rerank_span/3" do
    test "emits start and stop events for rerank" do
      ref = make_ref()

      :telemetry.attach_many(
        "test-rag-rerank-#{inspect(ref)}",
        [
          [:portfolio, :rag, :rerank, :start],
          [:portfolio, :rag, :rerank, :stop]
        ],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      ctx =
        Context.new("What is Elixir?")
        |> Map.put(:results, List.duplicate(%{id: 1}, 20))

      results =
        RAG.rerank_span(ctx, [threshold: 0.5], fn ->
          List.duplicate(%{id: 1, score: 0.8}, 10)
        end)

      assert length(results) == 10

      assert_receive {:telemetry, [:portfolio, :rag, :rerank, :start], _, start_meta}
      assert start_meta[:input_count] == 20
      assert start_meta[:threshold] == 0.5

      assert_receive {:telemetry, [:portfolio, :rag, :rerank, :stop], _, stop_meta}
      assert stop_meta[:output_count] == 10
      assert stop_meta[:kept] == 10
      assert stop_meta[:original] == 20

      :telemetry.detach("test-rag-rerank-#{inspect(ref)}")
    end
  end

  describe "correction_event/2" do
    test "emits correction event" do
      ref = make_ref()

      :telemetry.attach(
        "test-rag-correct-#{inspect(ref)}",
        [:portfolio, :rag, :self_correct],
        &TestHandler.handle_event/4,
        %{parent: self()}
      )

      ctx = Context.new("Test question")

      :ok = RAG.correction_event(ctx, "Answer not grounded in context")

      assert_receive {:telemetry, [:portfolio, :rag, :self_correct], measurements, meta}
      assert measurements[:count] == 1
      assert meta[:correction_count] == 1
      assert meta[:reason] == "Answer not grounded in context"

      :telemetry.detach("test-rag-correct-#{inspect(ref)}")
    end
  end
end
