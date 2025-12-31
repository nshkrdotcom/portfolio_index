defmodule PortfolioIndex.Schemas.Collection do
  @moduledoc """
  Ecto schema for document collections.
  Collections group related documents for organized retrieval and routing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_collections" do
    field(:name, :string)
    field(:description, :string)
    field(:metadata, :map, default: %{})
    field(:document_count, :integer, default: 0, virtual: true)

    has_many(:documents, PortfolioIndex.Schemas.Document)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating collections.

  ## Required fields
    - `:name` - Unique name for the collection

  ## Optional fields
    - `:description` - Human-readable description
    - `:metadata` - Arbitrary metadata map

  ## Examples

      iex> changeset(%Collection{}, %{name: "docs"})
      #Ecto.Changeset<...>

      iex> changeset(%Collection{}, %{name: "products", description: "Product docs"})
      #Ecto.Changeset<...>
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:name, :description, :metadata])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end

  @doc """
  Validate name uniqueness.

  Adds a unique constraint on the name field. This will be checked
  at database insert/update time.

  ## Examples

      iex> %Collection{}
      ...> |> changeset(%{name: "docs"})
      ...> |> validate_unique_name()
      ...> |> Repo.insert()
      {:ok, %Collection{}}
  """
  @spec validate_unique_name(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_unique_name(changeset) do
    unique_constraint(changeset, :name)
  end
end
