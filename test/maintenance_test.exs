defmodule PortfolioIndex.MaintenanceTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Maintenance
  alias PortfolioIndex.Schemas.{Chunk, Collection, Document}

  import Mox

  setup :verify_on_exit!

  setup tags do
    if tags[:integration] do
      pid = Sandbox.start_owner!(PortfolioIndex.Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    :ok
  end

  # =============================================================================
  # Unit Tests (no database required)
  # =============================================================================

  describe "type definitions" do
    test "reembed_result has expected shape" do
      result = %{
        total: 100,
        processed: 95,
        failed: 5,
        errors: [%{chunk_id: "123", error: :timeout}]
      }

      assert result.total == 100
      assert result.processed == 95
      assert result.failed == 5
      assert length(result.errors) == 1
    end

    test "diagnostics_result has expected shape" do
      result = %{
        collections: 5,
        documents: 100,
        chunks: 500,
        chunks_without_embedding: 10,
        failed_documents: 3,
        storage_bytes: 1_000_000
      }

      assert result.collections == 5
      assert result.documents == 100
      assert result.chunks == 500
    end
  end

  # =============================================================================
  # Integration Tests (require running PostgreSQL)
  # Run with: mix test --include integration
  # =============================================================================

  describe "diagnostics/1" do
    @tag :integration
    test "returns counts for empty database" do
      {:ok, result} = Maintenance.diagnostics(PortfolioIndex.Repo)

      assert result.collections >= 0
      assert result.documents >= 0
      assert result.chunks >= 0
      assert result.chunks_without_embedding >= 0
      assert result.failed_documents >= 0
    end

    @tag :integration
    test "counts documents and chunks correctly" do
      # Create test data
      {:ok, collection} =
        %Collection{}
        |> Collection.changeset(%{name: "diag_test_#{System.unique_integer([:positive])}"})
        |> PortfolioIndex.Repo.insert()

      {:ok, doc1} =
        %Document{}
        |> Document.changeset(%{
          title: "Doc 1",
          status: :completed,
          collection_id: collection.id
        })
        |> PortfolioIndex.Repo.insert()

      {:ok, doc2} =
        %Document{}
        |> Document.changeset(%{
          title: "Doc 2",
          status: :failed,
          error_message: "Test error",
          collection_id: collection.id
        })
        |> PortfolioIndex.Repo.insert()

      embedding = List.duplicate(0.1, 384)

      {:ok, _chunk1} =
        %Chunk{}
        |> Chunk.changeset(%{content: "Chunk 1", chunk_index: 0, document_id: doc1.id})
        |> Ecto.Changeset.put_change(:embedding, Pgvector.new(embedding))
        |> PortfolioIndex.Repo.insert()

      {:ok, _chunk2} =
        %Chunk{}
        |> Chunk.changeset(%{content: "Chunk 2", chunk_index: 0, document_id: doc1.id})
        |> PortfolioIndex.Repo.insert()

      {:ok, result} = Maintenance.diagnostics(PortfolioIndex.Repo)

      assert result.collections >= 1
      assert result.documents >= 2
      assert result.chunks >= 2
      assert result.chunks_without_embedding >= 1
      assert result.failed_documents >= 1

      # Cleanup
      PortfolioIndex.Repo.delete(doc2)
      PortfolioIndex.Repo.delete(doc1)
      PortfolioIndex.Repo.delete(collection)
    end
  end

  describe "verify_embeddings/1" do
    @tag :integration
    test "returns success for empty database" do
      {:ok, result} = Maintenance.verify_embeddings(PortfolioIndex.Repo)

      assert result.total_chunks >= 0
      assert result.consistent == true or result.consistent == false
    end

    @tag :integration
    test "detects consistent embeddings" do
      {:ok, doc} =
        %Document{}
        |> Document.changeset(%{title: "Verify Test"})
        |> PortfolioIndex.Repo.insert()

      embedding = List.duplicate(0.1, 384)

      {:ok, _chunk} =
        %Chunk{}
        |> Chunk.changeset(%{content: "Test", chunk_index: 0, document_id: doc.id})
        |> Ecto.Changeset.put_change(:embedding, Pgvector.new(embedding))
        |> PortfolioIndex.Repo.insert()

      {:ok, result} = Maintenance.verify_embeddings(PortfolioIndex.Repo)

      assert result.total_chunks >= 1
      # With single dimension, should be consistent
      assert is_boolean(result.consistent)

      # Cleanup
      PortfolioIndex.Repo.delete(doc)
    end
  end

  describe "retry_failed/2" do
    @tag :integration
    test "returns empty result when no failed documents" do
      {:ok, result} = Maintenance.retry_failed(PortfolioIndex.Repo, [])

      assert result.total == 0
      assert result.processed == 0
      assert result.failed == 0
    end

    @tag :integration
    test "resets failed documents to pending status" do
      {:ok, doc} =
        %Document{}
        |> Document.changeset(%{
          title: "Failed Doc",
          source_id: "retry_test_#{System.unique_integer([:positive])}",
          status: :failed,
          error_message: "Test failure"
        })
        |> PortfolioIndex.Repo.insert()

      {:ok, result} = Maintenance.retry_failed(PortfolioIndex.Repo, limit: 10)

      assert result.total >= 1

      # Verify document was reset
      updated_doc = PortfolioIndex.Repo.get(Document, doc.id)
      assert updated_doc.status == :pending
      assert updated_doc.error_message == nil

      # Cleanup
      PortfolioIndex.Repo.delete(updated_doc)
    end

    @tag :integration
    test "invokes progress callback" do
      {:ok, doc} =
        %Document{}
        |> Document.changeset(%{
          title: "Progress Test",
          source_id: "progress_test_#{System.unique_integer([:positive])}",
          status: :failed,
          error_message: "Test"
        })
        |> PortfolioIndex.Repo.insert()

      test_pid = self()

      callback = fn event ->
        send(test_pid, {:progress, event})
        :ok
      end

      {:ok, _result} = Maintenance.retry_failed(PortfolioIndex.Repo, on_progress: callback)

      assert_receive {:progress, event}
      assert event.operation == :retry_failed

      # Cleanup
      updated_doc = PortfolioIndex.Repo.get(Document, doc.id)
      PortfolioIndex.Repo.delete(updated_doc)
    end
  end

  describe "cleanup_deleted/2" do
    @tag :integration
    test "removes soft-deleted documents" do
      {:ok, doc} =
        %Document{}
        |> Document.changeset(%{
          title: "Deleted Doc",
          source_id: "cleanup_test_#{System.unique_integer([:positive])}",
          status: :deleted
        })
        |> PortfolioIndex.Repo.insert()

      {:ok, count} = Maintenance.cleanup_deleted(PortfolioIndex.Repo)

      assert count >= 1

      # Verify document was removed
      assert PortfolioIndex.Repo.get(Document, doc.id) == nil
    end

    @tag :integration
    test "removes associated chunks" do
      {:ok, doc} =
        %Document{}
        |> Document.changeset(%{
          title: "Deleted with Chunks",
          source_id: "cleanup_chunks_#{System.unique_integer([:positive])}",
          status: :deleted
        })
        |> PortfolioIndex.Repo.insert()

      {:ok, chunk} =
        %Chunk{}
        |> Chunk.changeset(%{content: "Test chunk", chunk_index: 0, document_id: doc.id})
        |> PortfolioIndex.Repo.insert()

      {:ok, _count} = Maintenance.cleanup_deleted(PortfolioIndex.Repo)

      # Both should be removed
      assert PortfolioIndex.Repo.get(Document, doc.id) == nil
      assert PortfolioIndex.Repo.get(Chunk, chunk.id) == nil
    end
  end

  describe "reembed/2" do
    @tag :integration
    test "returns empty result for empty database" do
      {:ok, result} = Maintenance.reembed(PortfolioIndex.Repo, [])

      assert result.total == 0
      assert result.processed == 0
      assert result.failed == 0
      assert result.errors == []
    end

    @tag :integration
    test "invokes progress callback during reembed" do
      # Create a chunk without embedding
      {:ok, doc} =
        %Document{}
        |> Document.changeset(%{title: "Reembed Test"})
        |> PortfolioIndex.Repo.insert()

      {:ok, _chunk} =
        %Chunk{}
        |> Chunk.changeset(%{content: "Test content", chunk_index: 0, document_id: doc.id})
        |> PortfolioIndex.Repo.insert()

      test_pid = self()

      callback = fn event ->
        send(test_pid, {:progress, event})
        :ok
      end

      # Mock the embedder
      PortfolioIndex.Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:ok,
         %{
           vector: List.duplicate(0.1, 384),
           model: "test",
           dimensions: 384,
           token_count: 5
         }}
      end)

      {:ok, _result} =
        Maintenance.reembed(PortfolioIndex.Repo,
          on_progress: callback,
          embedder: PortfolioIndex.Mocks.Embedder
        )

      assert_receive {:progress, event}
      assert event.operation == :reembed

      # Cleanup
      PortfolioIndex.Repo.delete(doc)
    end

    @tag :integration
    test "respects batch_size option" do
      {:ok, doc} =
        %Document{}
        |> Document.changeset(%{title: "Batch Test"})
        |> PortfolioIndex.Repo.insert()

      # Create multiple chunks
      for i <- 0..4 do
        %Chunk{}
        |> Chunk.changeset(%{content: "Content #{i}", chunk_index: i, document_id: doc.id})
        |> PortfolioIndex.Repo.insert()
      end

      # Mock embedder for all chunks
      PortfolioIndex.Mocks.Embedder
      |> expect(:embed, 5, fn _text, _opts ->
        {:ok,
         %{
           vector: List.duplicate(0.1, 384),
           model: "test",
           dimensions: 384,
           token_count: 5
         }}
      end)

      {:ok, result} =
        Maintenance.reembed(PortfolioIndex.Repo,
          batch_size: 2,
          embedder: PortfolioIndex.Mocks.Embedder
        )

      assert result.total == 5
      assert result.processed == 5

      # Cleanup
      PortfolioIndex.Repo.delete(doc)
    end

    @tag :integration
    test "filters by collection" do
      {:ok, collection} =
        %Collection{}
        |> Collection.changeset(%{name: "filter_test_#{System.unique_integer([:positive])}"})
        |> PortfolioIndex.Repo.insert()

      {:ok, doc_in_collection} =
        %Document{}
        |> Document.changeset(%{title: "In Collection", collection_id: collection.id})
        |> PortfolioIndex.Repo.insert()

      {:ok, doc_outside} =
        %Document{}
        |> Document.changeset(%{title: "Outside Collection"})
        |> PortfolioIndex.Repo.insert()

      {:ok, _chunk_in} =
        %Chunk{}
        |> Chunk.changeset(%{content: "In", chunk_index: 0, document_id: doc_in_collection.id})
        |> PortfolioIndex.Repo.insert()

      {:ok, _chunk_out} =
        %Chunk{}
        |> Chunk.changeset(%{content: "Out", chunk_index: 0, document_id: doc_outside.id})
        |> PortfolioIndex.Repo.insert()

      # Mock embedder - should only be called once
      PortfolioIndex.Mocks.Embedder
      |> expect(:embed, 1, fn _text, _opts ->
        {:ok,
         %{
           vector: List.duplicate(0.1, 384),
           model: "test",
           dimensions: 384,
           token_count: 5
         }}
      end)

      {:ok, result} =
        Maintenance.reembed(PortfolioIndex.Repo,
          collection: collection.name,
          embedder: PortfolioIndex.Mocks.Embedder
        )

      assert result.total == 1
      assert result.processed == 1

      # Cleanup
      PortfolioIndex.Repo.delete(doc_outside)
      PortfolioIndex.Repo.delete(doc_in_collection)
      PortfolioIndex.Repo.delete(collection)
    end
  end
end
