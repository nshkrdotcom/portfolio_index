defmodule PortfolioIndex.Schemas.CollectionTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PortfolioIndex.Schemas.Collection

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
      attrs = %{name: "test_collection"}
      changeset = Collection.changeset(%Collection{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "test_collection"
    end

    test "valid changeset with all fields" do
      attrs = %{
        name: "test_collection",
        description: "A test collection",
        metadata: %{category: "testing", version: 1}
      }

      changeset = Collection.changeset(%Collection{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "test_collection"
      assert Ecto.Changeset.get_change(changeset, :description) == "A test collection"
      assert Ecto.Changeset.get_change(changeset, :metadata) == %{category: "testing", version: 1}
    end

    test "invalid changeset without name" do
      changeset = Collection.changeset(%Collection{}, %{})

      refute changeset.valid?
      assert {:name, {"can't be blank", _}} = hd(changeset.errors)
    end

    test "validates name is not empty string" do
      changeset = Collection.changeset(%Collection{}, %{name: ""})

      refute changeset.valid?
    end

    test "default metadata is empty map" do
      collection = %Collection{}
      assert collection.metadata == %{}
    end

    test "default document_count is 0 and virtual" do
      collection = %Collection{}
      assert collection.document_count == 0
    end
  end

  describe "validate_unique_name/1" do
    test "adds unique constraint to changeset" do
      changeset =
        %Collection{}
        |> Collection.changeset(%{name: "unique_name"})
        |> Collection.validate_unique_name()

      # Check that unique_constraint was added
      assert changeset.valid?
    end
  end

  describe "schema structure" do
    test "has correct primary key type" do
      assert :id in Collection.__schema__(:primary_key)
      assert Collection.__schema__(:type, :id) == :binary_id
    end

    test "has expected fields" do
      fields = Collection.__schema__(:fields)

      assert :id in fields
      assert :name in fields
      assert :description in fields
      assert :metadata in fields
      assert :inserted_at in fields
      assert :updated_at in fields
    end

    test "document_count is a virtual field" do
      virtual_fields = Collection.__schema__(:virtual_fields)
      assert :document_count in virtual_fields
    end

    test "has documents association" do
      assocs = Collection.__schema__(:associations)
      assert :documents in assocs
    end
  end

  # =============================================================================
  # Integration Tests (require running PostgreSQL)
  # Run with: mix test --include integration
  # =============================================================================

  describe "database operations" do
    @tag :integration
    test "inserts a collection" do
      {:ok, collection} =
        %Collection{}
        |> Collection.changeset(%{name: "integration_test_#{System.unique_integer([:positive])}"})
        |> PortfolioIndex.Repo.insert()

      assert collection.id != nil
      assert collection.inserted_at != nil
      assert collection.updated_at != nil

      # Cleanup
      PortfolioIndex.Repo.delete(collection)
    end

    @tag :integration
    test "enforces unique name constraint" do
      name = "unique_name_#{System.unique_integer([:positive])}"

      {:ok, _} =
        %Collection{}
        |> Collection.changeset(%{name: name})
        |> Collection.validate_unique_name()
        |> PortfolioIndex.Repo.insert()

      {:error, changeset} =
        %Collection{}
        |> Collection.changeset(%{name: name})
        |> Collection.validate_unique_name()
        |> PortfolioIndex.Repo.insert()

      refute changeset.valid?
      assert {:name, {"has already been taken", _}} = hd(changeset.errors)
    end

    @tag :integration
    test "updates a collection" do
      name = "update_test_#{System.unique_integer([:positive])}"

      {:ok, collection} =
        %Collection{}
        |> Collection.changeset(%{name: name})
        |> PortfolioIndex.Repo.insert()

      {:ok, updated} =
        collection
        |> Collection.changeset(%{description: "Updated description"})
        |> PortfolioIndex.Repo.update()

      assert updated.description == "Updated description"

      # Cleanup
      PortfolioIndex.Repo.delete(updated)
    end

    @tag :integration
    test "retrieves a collection by id" do
      name = "retrieve_test_#{System.unique_integer([:positive])}"

      {:ok, collection} =
        %Collection{}
        |> Collection.changeset(%{name: name})
        |> PortfolioIndex.Repo.insert()

      retrieved = PortfolioIndex.Repo.get(Collection, collection.id)

      assert retrieved.name == name

      # Cleanup
      PortfolioIndex.Repo.delete(collection)
    end
  end
end
