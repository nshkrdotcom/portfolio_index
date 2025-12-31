defmodule PortfolioIndex.Schemas.ChunkTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Schemas.Chunk

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

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        content: "This is the chunk content.",
        chunk_index: 0
      }

      changeset = Chunk.changeset(%Chunk{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :content) == "This is the chunk content."
      assert Ecto.Changeset.get_change(changeset, :chunk_index) == 0
    end

    test "valid changeset with all fields" do
      embedding = List.duplicate(0.1, 384)

      attrs = %{
        content: "Chunk content here",
        embedding: embedding,
        chunk_index: 5,
        token_count: 42,
        start_char: 100,
        end_char: 200,
        metadata: %{source: "test", page: 1}
      }

      changeset = Chunk.changeset(%Chunk{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :content) == "Chunk content here"
      assert Ecto.Changeset.get_change(changeset, :chunk_index) == 5
      assert Ecto.Changeset.get_change(changeset, :token_count) == 42
      assert Ecto.Changeset.get_change(changeset, :start_char) == 100
      assert Ecto.Changeset.get_change(changeset, :end_char) == 200
    end

    test "invalid changeset without content" do
      changeset = Chunk.changeset(%Chunk{}, %{chunk_index: 0})

      refute changeset.valid?
      assert {:content, {"can't be blank", _}} = hd(changeset.errors)
    end

    test "invalid changeset without chunk_index" do
      changeset = Chunk.changeset(%Chunk{}, %{content: "Some content"})

      refute changeset.valid?
      assert {:chunk_index, {"can't be blank", _}} = hd(changeset.errors)
    end

    test "validates chunk_index is non-negative" do
      changeset = Chunk.changeset(%Chunk{}, %{content: "Test", chunk_index: -1})

      refute changeset.valid?
      assert {:chunk_index, _} = hd(changeset.errors)
    end

    test "validates token_count is non-negative" do
      changeset = Chunk.changeset(%Chunk{}, %{content: "Test", chunk_index: 0, token_count: -5})

      refute changeset.valid?
      assert {:token_count, _} = hd(changeset.errors)
    end

    test "validates start_char is non-negative" do
      changeset = Chunk.changeset(%Chunk{}, %{content: "Test", chunk_index: 0, start_char: -1})

      refute changeset.valid?
      assert {:start_char, _} = hd(changeset.errors)
    end

    test "validates end_char is non-negative" do
      changeset = Chunk.changeset(%Chunk{}, %{content: "Test", chunk_index: 0, end_char: -1})

      refute changeset.valid?
      assert {:end_char, _} = hd(changeset.errors)
    end

    test "default metadata is empty map" do
      chunk = %Chunk{}
      assert chunk.metadata == %{}
    end
  end

  describe "embedding_changeset/2" do
    test "updates embedding from float list" do
      chunk = %Chunk{content: "Test", chunk_index: 0}
      embedding = List.duplicate(0.5, 384)

      changeset = Chunk.embedding_changeset(chunk, embedding)

      assert changeset.valid?
      changed_embedding = Ecto.Changeset.get_change(changeset, :embedding)
      assert changed_embedding != nil
    end

    test "handles empty embedding list" do
      chunk = %Chunk{content: "Test", chunk_index: 0}
      embedding = []

      changeset = Chunk.embedding_changeset(chunk, embedding)

      # Empty embedding should still create a valid changeset
      # but the embedding value will be empty
      assert changeset.valid?
    end

    test "preserves other fields when updating embedding" do
      chunk = %Chunk{
        content: "Original content",
        chunk_index: 3,
        token_count: 10,
        metadata: %{key: "value"}
      }

      embedding = List.duplicate(0.25, 384)
      changeset = Chunk.embedding_changeset(chunk, embedding)

      # Original fields should not be changed
      refute Ecto.Changeset.get_change(changeset, :content)
      refute Ecto.Changeset.get_change(changeset, :chunk_index)
      refute Ecto.Changeset.get_change(changeset, :token_count)
    end
  end

  describe "schema structure" do
    test "has correct primary key type" do
      assert :id in Chunk.__schema__(:primary_key)
      assert Chunk.__schema__(:type, :id) == :binary_id
    end

    test "has expected fields" do
      fields = Chunk.__schema__(:fields)

      assert :id in fields
      assert :content in fields
      assert :embedding in fields
      assert :chunk_index in fields
      assert :token_count in fields
      assert :start_char in fields
      assert :end_char in fields
      assert :metadata in fields
      assert :document_id in fields
      assert :inserted_at in fields
      assert :updated_at in fields
    end

    test "embedding field uses Pgvector.Ecto.Vector type" do
      type = Chunk.__schema__(:type, :embedding)
      assert type == Pgvector.Ecto.Vector
    end

    test "has document association" do
      assocs = Chunk.__schema__(:associations)
      assert :document in assocs
    end
  end

  # =============================================================================
  # Integration Tests (require running PostgreSQL)
  # Run with: mix test --include integration
  # =============================================================================

  describe "database operations" do
    @tag :integration
    test "inserts a chunk with embedding" do
      # First create a document to associate with
      {:ok, document} =
        %PortfolioIndex.Schemas.Document{}
        |> PortfolioIndex.Schemas.Document.changeset(%{title: "Test Doc"})
        |> PortfolioIndex.Repo.insert()

      embedding = List.duplicate(0.1, 384)

      {:ok, chunk} =
        %Chunk{}
        |> Chunk.changeset(%{
          content: "Test chunk content",
          chunk_index: 0,
          document_id: document.id
        })
        |> Ecto.Changeset.put_change(:embedding, Pgvector.new(embedding))
        |> PortfolioIndex.Repo.insert()

      assert chunk.id != nil
      assert chunk.content == "Test chunk content"
      assert chunk.chunk_index == 0
      assert chunk.embedding != nil
      assert chunk.inserted_at != nil

      # Cleanup
      PortfolioIndex.Repo.delete(chunk)
      PortfolioIndex.Repo.delete(document)
    end

    @tag :integration
    test "queries chunks by document" do
      import Ecto.Query

      {:ok, document} =
        %PortfolioIndex.Schemas.Document{}
        |> PortfolioIndex.Schemas.Document.changeset(%{title: "Query Test Doc"})
        |> PortfolioIndex.Repo.insert()

      embedding = List.duplicate(0.2, 384)

      for i <- 0..2 do
        %Chunk{}
        |> Chunk.changeset(%{
          content: "Chunk #{i}",
          chunk_index: i,
          document_id: document.id
        })
        |> Ecto.Changeset.put_change(:embedding, Pgvector.new(embedding))
        |> PortfolioIndex.Repo.insert()
      end

      chunks =
        Chunk
        |> where([c], c.document_id == ^document.id)
        |> order_by([c], c.chunk_index)
        |> PortfolioIndex.Repo.all()

      assert length(chunks) == 3
      assert Enum.map(chunks, & &1.chunk_index) == [0, 1, 2]

      # Cleanup
      Enum.each(chunks, &PortfolioIndex.Repo.delete/1)
      PortfolioIndex.Repo.delete(document)
    end

    @tag :integration
    test "performs similarity search" do
      import Ecto.Query

      {:ok, document} =
        %PortfolioIndex.Schemas.Document{}
        |> PortfolioIndex.Schemas.Document.changeset(%{title: "Similarity Test"})
        |> PortfolioIndex.Repo.insert()

      # Insert chunks with different embeddings
      embeddings = [
        List.duplicate(0.9, 384),
        List.duplicate(0.5, 384),
        List.duplicate(0.1, 384)
      ]

      for {emb, i} <- Enum.with_index(embeddings) do
        %Chunk{}
        |> Chunk.changeset(%{
          content: "Chunk #{i}",
          chunk_index: i,
          document_id: document.id
        })
        |> Ecto.Changeset.put_change(:embedding, Pgvector.new(emb))
        |> PortfolioIndex.Repo.insert()
      end

      # Search for similar chunks
      query_embedding = Pgvector.new(List.duplicate(0.9, 384))

      results =
        Chunk
        |> where([c], c.document_id == ^document.id)
        |> order_by([c], fragment("embedding <=> ?", ^query_embedding))
        |> limit(2)
        |> PortfolioIndex.Repo.all()

      assert length(results) == 2
      # First result should be the most similar (0.9 embedding)
      assert hd(results).chunk_index == 0

      # Cleanup
      Chunk
      |> where([c], c.document_id == ^document.id)
      |> PortfolioIndex.Repo.delete_all()

      PortfolioIndex.Repo.delete(document)
    end
  end
end
