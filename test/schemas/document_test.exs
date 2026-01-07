defmodule PortfolioIndex.Schemas.DocumentTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Schemas.Document

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
    test "valid changeset with minimal fields" do
      attrs = %{}
      changeset = Document.changeset(%Document{}, attrs)

      assert changeset.valid?
    end

    test "valid changeset with all fields" do
      attrs = %{
        source_id: "source_123",
        content_hash: "abc123hash",
        title: "Test Document",
        source_path: "/path/to/doc.md",
        metadata: %{author: "test", version: 1},
        status: :processing,
        error_message: nil,
        chunk_count: 5
      }

      changeset = Document.changeset(%Document{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :source_id) == "source_123"
      assert Ecto.Changeset.get_change(changeset, :content_hash) == "abc123hash"
      assert Ecto.Changeset.get_change(changeset, :title) == "Test Document"
      assert Ecto.Changeset.get_change(changeset, :source_path) == "/path/to/doc.md"
      assert Ecto.Changeset.get_change(changeset, :status) == :processing
      assert Ecto.Changeset.get_change(changeset, :chunk_count) == 5
    end

    test "validates status enum values" do
      valid_statuses = [:pending, :processing, :completed, :failed, :deleted]

      for status <- valid_statuses do
        changeset = Document.changeset(%Document{}, %{status: status})
        assert changeset.valid?, "Expected status #{status} to be valid"
      end
    end

    test "rejects invalid status values" do
      changeset = Document.changeset(%Document{}, %{status: :invalid_status})
      refute changeset.valid?
    end

    test "default status is pending" do
      document = %Document{}
      assert document.status == :pending
    end

    test "default metadata is empty map" do
      document = %Document{}
      assert document.metadata == %{}
    end

    test "default chunk_count is 0" do
      document = %Document{}
      assert document.chunk_count == 0
    end
  end

  describe "status_changeset/3" do
    test "updates status without error message" do
      document = %Document{status: :pending}
      changeset = Document.status_changeset(document, :processing)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == :processing
      refute Ecto.Changeset.get_change(changeset, :error_message)
    end

    test "updates status with error message" do
      document = %Document{status: :processing}
      changeset = Document.status_changeset(document, :failed, "Connection timeout")

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == :failed
      assert Ecto.Changeset.get_change(changeset, :error_message) == "Connection timeout"
    end

    test "clears error message when transitioning to non-failed status" do
      document = %Document{status: :failed, error_message: "Previous error"}
      changeset = Document.status_changeset(document, :pending)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == :pending
      assert Ecto.Changeset.get_change(changeset, :error_message) == nil
    end
  end

  describe "compute_hash/1" do
    test "computes SHA256 hash of content" do
      content = "Hello, world!"
      hash = Document.compute_hash(content)

      # SHA256 of "Hello, world!" is a known value
      expected = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "produces different hashes for different content" do
      hash1 = Document.compute_hash("Content A")
      hash2 = Document.compute_hash("Content B")

      refute hash1 == hash2
    end

    test "produces same hash for same content" do
      content = "Reproducible content"
      hash1 = Document.compute_hash(content)
      hash2 = Document.compute_hash(content)

      assert hash1 == hash2
    end

    test "handles empty string" do
      hash = Document.compute_hash("")
      expected = :crypto.hash(:sha256, "") |> Base.encode16(case: :lower)
      assert hash == expected
    end

    test "handles unicode content" do
      content = "Hello, \u4e16\u754c! \u{1F600}"
      hash = Document.compute_hash(content)

      assert is_binary(hash)
      assert String.length(hash) == 64
    end
  end

  describe "schema structure" do
    test "has correct primary key type" do
      assert :id in Document.__schema__(:primary_key)
      assert Document.__schema__(:type, :id) == :binary_id
    end

    test "has expected fields" do
      fields = Document.__schema__(:fields)

      assert :id in fields
      assert :source_id in fields
      assert :content_hash in fields
      assert :title in fields
      assert :source_path in fields
      assert :metadata in fields
      assert :status in fields
      assert :error_message in fields
      assert :chunk_count in fields
      assert :collection_id in fields
      assert :inserted_at in fields
      assert :updated_at in fields
    end

    test "has collection association" do
      assocs = Document.__schema__(:associations)
      assert :collection in assocs
    end

    test "has chunks association" do
      assocs = Document.__schema__(:associations)
      assert :chunks in assocs
    end
  end

  # =============================================================================
  # Integration Tests (require running PostgreSQL)
  # Run with: mix test --include integration
  # =============================================================================

  describe "database operations" do
    @tag :integration
    test "inserts a document" do
      {:ok, document} =
        %Document{}
        |> Document.changeset(%{
          source_id: "test_#{System.unique_integer([:positive])}",
          title: "Test Document"
        })
        |> PortfolioIndex.Repo.insert()

      assert document.id != nil
      assert document.status == :pending
      assert document.inserted_at != nil
      assert document.updated_at != nil

      # Cleanup
      PortfolioIndex.Repo.delete(document)
    end

    @tag :integration
    test "updates document status" do
      {:ok, document} =
        %Document{}
        |> Document.changeset(%{title: "Status Test"})
        |> PortfolioIndex.Repo.insert()

      {:ok, updated} =
        document
        |> Document.status_changeset(:completed)
        |> PortfolioIndex.Repo.update()

      assert updated.status == :completed

      # Cleanup
      PortfolioIndex.Repo.delete(updated)
    end

    @tag :integration
    test "queries documents by status" do
      import Ecto.Query

      source_id = "query_test_#{System.unique_integer([:positive])}"

      {:ok, doc1} =
        %Document{}
        |> Document.changeset(%{source_id: "#{source_id}_1", status: :pending})
        |> PortfolioIndex.Repo.insert()

      {:ok, doc2} =
        %Document{}
        |> Document.changeset(%{source_id: "#{source_id}_2", status: :completed})
        |> PortfolioIndex.Repo.insert()

      pending_docs =
        Document
        |> where([d], d.status == :pending and like(d.source_id, ^"#{source_id}%"))
        |> PortfolioIndex.Repo.all()

      assert length(pending_docs) == 1
      assert hd(pending_docs).source_id == "#{source_id}_1"

      # Cleanup
      PortfolioIndex.Repo.delete(doc1)
      PortfolioIndex.Repo.delete(doc2)
    end
  end
end
