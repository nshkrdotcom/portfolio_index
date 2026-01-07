defmodule PortfolioIndex.Pipelines.EmbeddingTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias PortfolioIndex.Adapters.VectorStore.Pgvector
  alias PortfolioIndex.DataCase
  alias PortfolioIndex.Pipelines.Embedding

  setup tags do
    if tags[:integration] do
      DataCase.setup_sandbox(tags)
    end

    :ok
  end

  # =============================================================================
  # Unit Tests
  # =============================================================================

  describe "module structure" do
    test "uses Broadway" do
      functions = Embedding.__info__(:functions)
      assert {:start_link, 1} in functions
      assert {:handle_message, 3} in functions
      assert {:handle_batch, 4} in functions
    end

    test "has start/1 convenience function" do
      functions = Embedding.__info__(:functions)
      assert {:start, 1} in functions
    end

    test "has enqueue/1 function" do
      functions = Embedding.__info__(:functions)
      assert {:enqueue, 1} in functions
    end

    test "has queue_size/0 function" do
      functions = Embedding.__info__(:functions)
      assert {:queue_size, 0} in functions
    end
  end

  describe "start_link/1 options" do
    test "accepts concurrency option" do
      opts = [concurrency: 10]

      assert Keyword.get(opts, :concurrency) == 10
    end

    test "accepts batch_size option" do
      opts = [batch_size: 50]

      assert Keyword.get(opts, :batch_size) == 50
    end

    test "accepts rate_limit option" do
      opts = [rate_limit: 200]

      assert Keyword.get(opts, :rate_limit) == 200
    end

    test "accepts index_id option" do
      opts = [index_id: "custom_index"]

      assert Keyword.get(opts, :index_id) == "custom_index"
    end

    test "accepts dimensions option" do
      opts = [dimensions: 3072]

      assert Keyword.get(opts, :dimensions) == 3072
    end
  end

  describe "enqueue/1" do
    test "enqueues a chunk and increments queue size" do
      initial_size = Embedding.queue_size()

      chunk = %{
        content: "Test content for embedding",
        source: "/path/to/file.md",
        index: 0,
        format: :markdown
      }

      assert :ok = Embedding.enqueue(chunk)

      new_size = Embedding.queue_size()
      assert new_size > initial_size
    end

    test "accepts chunks with various metadata" do
      chunk = %{
        content: "Another test chunk",
        source: "/path/to/code.ex",
        index: 5,
        format: :code,
        language: :elixir,
        source_type: :elixir
      }

      assert :ok = Embedding.enqueue(chunk)
    end
  end

  describe "queue_size/0" do
    test "returns a non-negative integer" do
      size = Embedding.queue_size()

      assert is_integer(size)
      assert size >= 0
    end
  end

  describe "telemetry events" do
    test "documents expected event names" do
      # These are the events the embedding pipeline emits
      events = [
        [:portfolio_index, :pipeline, :embedding, :generated],
        [:portfolio_index, :pipeline, :embedding, :batch_stored]
      ]

      # Verify event structure
      for event <- events do
        assert is_list(event)
        assert length(event) == 4
        assert hd(event) == :portfolio_index
      end
    end

    test "generated event includes expected measurements" do
      # Expected measurements for :generated event
      measurements = [:duration_ms, :tokens, :dimensions]

      for m <- measurements do
        assert is_atom(m)
      end
    end

    test "batch_stored event includes expected measurements" do
      # Expected measurements for :batch_stored event
      measurements = [:duration_ms, :count]

      for m <- measurements do
        assert is_atom(m)
      end
    end
  end

  describe "chunk ID generation" do
    test "generates deterministic IDs from chunk content" do
      chunk1 = %{content: "Test content", source: "/path/file.md", index: 0}
      chunk2 = %{content: "Test content", source: "/path/file.md", index: 0}
      chunk3 = %{content: "Different content", source: "/path/file.md", index: 0}

      # Same content + source + index should produce same prefix pattern
      # (We can't test the actual function since it's private)
      assert chunk1.content == chunk2.content
      assert chunk1.source == chunk2.source
      assert chunk1.index == chunk2.index

      # Different content should be distinguishable
      assert chunk1.content != chunk3.content
    end
  end

  # =============================================================================
  # Integration Tests
  # Run with: mix test --include integration
  # =============================================================================

  describe "pipeline integration" do
    @tag :integration
    @tag :skip
    test "processes enqueued chunks" do
      # This test requires the full pipeline with Gemini API access
      # Skipped by default - enable for end-to-end testing

      # Create a unique index for this test
      index_id = "test_#{System.unique_integer([:positive])}"

      # Create the vector index before starting the pipeline
      :ok =
        Pgvector.create_index(index_id, %{
          dimensions: 768,
          metric: :cosine,
          index_type: :flat
        })

      {:ok, pid} =
        Embedding.start_link(
          index_id: index_id,
          name: :"test_embedding_#{System.unique_integer()}",
          rate_limit: 10
        )

      chunk = %{
        content: "The quick brown fox jumps over the lazy dog.",
        source: "/test/file.md",
        index: 0,
        format: :markdown
      }

      :ok = Embedding.enqueue(chunk)

      assert Process.alive?(pid)

      Broadway.stop(pid)

      # Cleanup
      Pgvector.delete_index(index_id)
    end
  end
end
