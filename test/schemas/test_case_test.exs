defmodule PortfolioIndex.Schemas.TestCaseTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Schemas.TestCase

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
        question: "What is Elixir?"
      }

      changeset = TestCase.changeset(%TestCase{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :question) == "What is Elixir?"
    end

    test "valid changeset with all fields" do
      attrs = %{
        question: "How does GenServer work?",
        source: :synthetic,
        collection: "elixir_docs",
        metadata: %{generated_from: "chunk_123"}
      }

      changeset = TestCase.changeset(%TestCase{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :question) == "How does GenServer work?"
      assert Ecto.Changeset.get_change(changeset, :source) == :synthetic
      assert Ecto.Changeset.get_change(changeset, :collection) == "elixir_docs"
      assert Ecto.Changeset.get_change(changeset, :metadata) == %{generated_from: "chunk_123"}
    end

    test "invalid changeset without question" do
      changeset = TestCase.changeset(%TestCase{}, %{})

      refute changeset.valid?
      assert {:question, {"can't be blank", _}} = hd(changeset.errors)
    end

    test "validates source is one of allowed values" do
      valid_synthetic = TestCase.changeset(%TestCase{}, %{question: "Q", source: :synthetic})
      assert valid_synthetic.valid?

      valid_manual = TestCase.changeset(%TestCase{}, %{question: "Q", source: :manual})
      assert valid_manual.valid?
    end

    test "default source is :manual" do
      test_case = %TestCase{}
      assert test_case.source == :manual
    end

    test "default metadata is empty map" do
      test_case = %TestCase{}
      assert test_case.metadata == %{}
    end
  end

  describe "schema structure" do
    test "has correct primary key type" do
      assert :id in TestCase.__schema__(:primary_key)
      assert TestCase.__schema__(:type, :id) == :binary_id
    end

    test "has expected fields" do
      fields = TestCase.__schema__(:fields)

      assert :id in fields
      assert :question in fields
      assert :source in fields
      assert :collection in fields
      assert :metadata in fields
      assert :inserted_at in fields
      assert :updated_at in fields
    end

    test "has relevant_chunks association" do
      assocs = TestCase.__schema__(:associations)
      assert :relevant_chunks in assocs
    end
  end

  describe "add_relevant_chunks/2" do
    test "creates changeset to add chunks" do
      test_case = %TestCase{id: Ecto.UUID.generate(), question: "Test?"}

      chunks = [
        %PortfolioIndex.Schemas.Chunk{id: Ecto.UUID.generate(), content: "C1", chunk_index: 0},
        %PortfolioIndex.Schemas.Chunk{id: Ecto.UUID.generate(), content: "C2", chunk_index: 1}
      ]

      changeset = TestCase.add_relevant_chunks(test_case, chunks)

      assert changeset.valid?
      assert is_list(Ecto.Changeset.get_change(changeset, :relevant_chunks))
    end
  end
end
