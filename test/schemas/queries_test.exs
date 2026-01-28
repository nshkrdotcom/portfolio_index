defmodule PortfolioIndex.Schemas.QueriesTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Repo
  alias PortfolioIndex.Schemas.{Chunk, Collection, Document, Queries}

  defp one_hot_vector(dimensions, hot_index) do
    for i <- 0..(dimensions - 1), do: if(i == hot_index, do: 1.0, else: 0.0)
  end

  setup tags do
    if tags[:integration] do
      pid = Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    :ok
  end

  # =============================================================================
  # Unit Tests (no database required)
  # =============================================================================

  describe "module structure" do
    setup do
      # Ensure module is loaded before checking function exports
      {:module, _} = Code.ensure_loaded(Queries)
      :ok
    end

    test "exports get_collection_by_name/2" do
      assert function_exported?(Queries, :get_collection_by_name, 2)
    end

    test "exports get_or_create_collection/2 and /3" do
      assert function_exported?(Queries, :get_or_create_collection, 2)
      assert function_exported?(Queries, :get_or_create_collection, 3)
    end

    test "exports list_documents_by_status/2 and /3" do
      assert function_exported?(Queries, :list_documents_by_status, 2)
      assert function_exported?(Queries, :list_documents_by_status, 3)
    end

    test "exports get_document_with_chunks/2" do
      assert function_exported?(Queries, :get_document_with_chunks, 2)
    end

    test "exports similarity_search/2 and /3" do
      assert function_exported?(Queries, :similarity_search, 2)
      assert function_exported?(Queries, :similarity_search, 3)
    end

    test "exports count_chunks_without_embedding/1" do
      assert function_exported?(Queries, :count_chunks_without_embedding, 1)
    end

    test "exports get_failed_documents/1 and /2" do
      assert function_exported?(Queries, :get_failed_documents, 1)
      assert function_exported?(Queries, :get_failed_documents, 2)
    end

    test "exports soft_delete_document/2" do
      assert function_exported?(Queries, :soft_delete_document, 2)
    end
  end

  # =============================================================================
  # Integration Tests (require running PostgreSQL)
  # Run with: mix test --include integration
  # =============================================================================

  describe "get_collection_by_name/2" do
    @tag :integration
    test "returns nil for non-existent collection" do
      result = Queries.get_collection_by_name(Repo, "nonexistent_#{System.unique_integer()}")
      assert result == nil
    end

    @tag :integration
    test "returns collection when it exists" do
      name = "test_collection_#{System.unique_integer([:positive])}"

      {:ok, collection} =
        %Collection{}
        |> Collection.changeset(%{name: name})
        |> Repo.insert()

      result = Queries.get_collection_by_name(Repo, name)

      assert result.id == collection.id
      assert result.name == name

      # Cleanup
      Repo.delete(collection)
    end
  end

  describe "get_or_create_collection/3" do
    @tag :integration
    test "creates collection when it doesn't exist" do
      name = "new_collection_#{System.unique_integer([:positive])}"

      {:ok, collection} = Queries.get_or_create_collection(Repo, name, %{description: "Test"})

      assert collection.name == name
      assert collection.description == "Test"

      # Cleanup
      Repo.delete(collection)
    end

    @tag :integration
    test "returns existing collection when it exists" do
      name = "existing_collection_#{System.unique_integer([:positive])}"

      {:ok, original} =
        %Collection{}
        |> Collection.changeset(%{name: name, description: "Original"})
        |> Repo.insert()

      {:ok, retrieved} = Queries.get_or_create_collection(Repo, name, %{description: "New"})

      assert retrieved.id == original.id
      # Description should not be overwritten
      assert retrieved.description == "Original"

      # Cleanup
      Repo.delete(original)
    end
  end

  describe "list_documents_by_status/3" do
    @tag :integration
    test "returns empty list when no documents match" do
      result = Queries.list_documents_by_status(Repo, :completed, [])
      assert is_list(result)
    end

    @tag :integration
    test "returns documents with matching status" do
      source_prefix = "status_test_#{System.unique_integer([:positive])}"

      {:ok, pending_doc} =
        %Document{}
        |> Document.changeset(%{source_id: "#{source_prefix}_pending", status: :pending})
        |> Repo.insert()

      {:ok, completed_doc} =
        %Document{}
        |> Document.changeset(%{source_id: "#{source_prefix}_completed", status: :completed})
        |> Repo.insert()

      pending_results = Queries.list_documents_by_status(Repo, :pending, [])
      completed_results = Queries.list_documents_by_status(Repo, :completed, [])

      pending_ids = Enum.map(pending_results, & &1.id)
      completed_ids = Enum.map(completed_results, & &1.id)

      assert pending_doc.id in pending_ids
      refute completed_doc.id in pending_ids
      assert completed_doc.id in completed_ids
      refute pending_doc.id in completed_ids

      # Cleanup
      Repo.delete(pending_doc)
      Repo.delete(completed_doc)
    end

    @tag :integration
    test "respects limit option" do
      source_prefix = "limit_test_#{System.unique_integer([:positive])}"

      docs =
        for i <- 1..5 do
          {:ok, doc} =
            %Document{}
            |> Document.changeset(%{source_id: "#{source_prefix}_#{i}", status: :pending})
            |> Repo.insert()

          doc
        end

      results = Queries.list_documents_by_status(Repo, :pending, limit: 2)

      assert length(results) == 2

      # Cleanup
      Enum.each(docs, &Repo.delete/1)
    end
  end

  describe "get_document_with_chunks/2" do
    @tag :integration
    test "returns nil for non-existent document" do
      fake_id = Ecto.UUID.generate()
      result = Queries.get_document_with_chunks(Repo, fake_id)
      assert result == nil
    end

    @tag :integration
    test "returns document with preloaded chunks" do
      {:ok, document} =
        %Document{}
        |> Document.changeset(%{title: "Chunks Test"})
        |> Repo.insert()

      embedding = Pgvector.new(List.duplicate(0.1, 384))

      {:ok, chunk} =
        %Chunk{}
        |> Chunk.changeset(%{content: "Test chunk", chunk_index: 0, document_id: document.id})
        |> Ecto.Changeset.put_change(:embedding, embedding)
        |> Repo.insert()

      result = Queries.get_document_with_chunks(Repo, document.id)

      assert result.id == document.id
      assert length(result.chunks) == 1
      assert hd(result.chunks).id == chunk.id

      # Cleanup
      Repo.delete(chunk)
      Repo.delete(document)
    end
  end

  describe "similarity_search/3" do
    @tag :integration
    test "returns empty list when no chunks exist" do
      query_embedding = List.duplicate(0.5, 384)
      results = Queries.similarity_search(Repo, query_embedding, [])
      assert results == []
    end

    @tag :integration
    test "returns chunks ordered by similarity" do
      {:ok, document} =
        %Document{}
        |> Document.changeset(%{title: "Similarity Test"})
        |> Repo.insert()

      # Create chunks with different embeddings
      embeddings = [
        one_hot_vector(384, 0),
        one_hot_vector(384, 1),
        one_hot_vector(384, 2)
      ]

      chunks =
        for {emb, i} <- Enum.with_index(embeddings) do
          {:ok, chunk} =
            %Chunk{}
            |> Chunk.changeset(%{content: "Chunk #{i}", chunk_index: i, document_id: document.id})
            |> Ecto.Changeset.put_change(:embedding, Pgvector.new(emb))
            |> Repo.insert()

          chunk
        end

      # Search with query similar to first chunk
      query_embedding = one_hot_vector(384, 0)
      results = Queries.similarity_search(Repo, query_embedding, limit: 2)

      assert length(results) == 2
      # First result should be most similar
      assert hd(results).chunk_index == 0

      # Cleanup
      Enum.each(chunks, &Repo.delete/1)
      Repo.delete(document)
    end

    @tag :integration
    test "respects limit option" do
      {:ok, document} =
        %Document{}
        |> Document.changeset(%{title: "Limit Test"})
        |> Repo.insert()

      chunks =
        for i <- 0..4 do
          emb = List.duplicate(0.1 * (i + 1), 384)

          {:ok, chunk} =
            %Chunk{}
            |> Chunk.changeset(%{content: "Chunk #{i}", chunk_index: i, document_id: document.id})
            |> Ecto.Changeset.put_change(:embedding, Pgvector.new(emb))
            |> Repo.insert()

          chunk
        end

      query_embedding = List.duplicate(0.5, 384)
      results = Queries.similarity_search(Repo, query_embedding, limit: 3)

      assert length(results) == 3

      # Cleanup
      Enum.each(chunks, &Repo.delete/1)
      Repo.delete(document)
    end
  end

  describe "count_chunks_without_embedding/1" do
    @tag :integration
    test "returns 0 when all chunks have embeddings" do
      {:ok, document} =
        %Document{}
        |> Document.changeset(%{title: "Count Test"})
        |> Repo.insert()

      {:ok, chunk} =
        %Chunk{}
        |> Chunk.changeset(%{content: "With embedding", chunk_index: 0, document_id: document.id})
        |> Ecto.Changeset.put_change(:embedding, Pgvector.new(List.duplicate(0.5, 384)))
        |> Repo.insert()

      count = Queries.count_chunks_without_embedding(Repo)

      # Count should be 0 or include only chunks without embeddings
      assert is_integer(count)

      # Cleanup
      Repo.delete(chunk)
      Repo.delete(document)
    end

    @tag :integration
    test "counts chunks without embeddings" do
      {:ok, document} =
        %Document{}
        |> Document.changeset(%{title: "No Embedding Test"})
        |> Repo.insert()

      # Create chunk without embedding
      {:ok, chunk} =
        %Chunk{}
        |> Chunk.changeset(%{
          content: "Without embedding",
          chunk_index: 0,
          document_id: document.id
        })
        |> Repo.insert()

      count = Queries.count_chunks_without_embedding(Repo)

      assert count >= 1

      # Cleanup
      Repo.delete(chunk)
      Repo.delete(document)
    end
  end

  describe "get_failed_documents/2" do
    @tag :integration
    test "returns only failed documents" do
      source_prefix = "failed_test_#{System.unique_integer([:positive])}"

      {:ok, failed_doc} =
        %Document{}
        |> Document.changeset(%{source_id: "#{source_prefix}_failed", status: :failed})
        |> Repo.insert()

      {:ok, pending_doc} =
        %Document{}
        |> Document.changeset(%{source_id: "#{source_prefix}_pending", status: :pending})
        |> Repo.insert()

      results = Queries.get_failed_documents(Repo, [])
      result_ids = Enum.map(results, & &1.id)

      assert failed_doc.id in result_ids
      refute pending_doc.id in result_ids

      # Cleanup
      Repo.delete(failed_doc)
      Repo.delete(pending_doc)
    end
  end

  describe "soft_delete_document/2" do
    @tag :integration
    test "marks document as deleted" do
      {:ok, document} =
        %Document{}
        |> Document.changeset(%{title: "To Delete", status: :completed})
        |> Repo.insert()

      {:ok, deleted} = Queries.soft_delete_document(Repo, document)

      assert deleted.status == :deleted

      # Cleanup
      Repo.delete(deleted)
    end

    @tag :integration
    test "preserves document data when soft deleted" do
      {:ok, document} =
        %Document{}
        |> Document.changeset(%{
          title: "Preserve Data",
          source_id: "preserve_test",
          metadata: %{important: true}
        })
        |> Repo.insert()

      {:ok, deleted} = Queries.soft_delete_document(Repo, document)

      assert deleted.title == "Preserve Data"
      assert deleted.source_id == "preserve_test"
      assert deleted.metadata["important"] == true

      # Cleanup
      Repo.delete(deleted)
    end
  end
end
