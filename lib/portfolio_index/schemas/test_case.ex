defmodule PortfolioIndex.Schemas.TestCase do
  @moduledoc """
  Ecto schema for evaluation test cases.
  Links questions to their expected relevant chunks (ground truth).

  ## Overview

  Test cases are used to evaluate retrieval quality. Each test case consists of:
    - A question that should be answered using the linked chunks
    - One or more relevant chunks (ground truth)
    - Optional metadata about how the test case was created

  ## Sources

  Test cases can be created in two ways:
    - `:synthetic` - Generated automatically by an LLM from chunk content
    - `:manual` - Created manually by a user with expert knowledge

  ## Usage

      # Create a manual test case
      {:ok, test_case} =
        %TestCase{}
        |> TestCase.changeset(%{
          question: "What is the capital of France?",
          source: :manual,
          collection: "geography"
        })
        |> Repo.insert()

      # Link relevant chunks
      test_case
      |> TestCase.add_relevant_chunks([chunk1, chunk2])
      |> Repo.update()
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias PortfolioIndex.Schemas.Chunk

  @type source :: :synthetic | :manual

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          question: String.t(),
          source: source(),
          collection: String.t() | nil,
          metadata: map(),
          relevant_chunks: [Chunk.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_evaluation_test_cases" do
    field(:question, :string)
    field(:source, Ecto.Enum, values: [:synthetic, :manual], default: :manual)
    field(:collection, :string)
    field(:metadata, :map, default: %{})

    many_to_many(:relevant_chunks, Chunk,
      join_through: "portfolio_evaluation_test_case_chunks",
      on_replace: :delete
    )

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating test cases.

  ## Required Fields
    - `:question` - The question text

  ## Optional Fields
    - `:source` - How the test case was created (`:synthetic` or `:manual`)
    - `:collection` - Filter test cases by collection name
    - `:metadata` - Arbitrary metadata map

  ## Examples

      iex> changeset(%TestCase{}, %{question: "What is Elixir?"})
      #Ecto.Changeset<...>

      iex> changeset(%TestCase{}, %{
      ...>   question: "How do I use GenServer?",
      ...>   source: :synthetic,
      ...>   collection: "elixir_guides",
      ...>   metadata: %{source_chunk_id: "abc123"}
      ...> })
      #Ecto.Changeset<...>
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(test_case, attrs) do
    test_case
    |> cast(attrs, [:question, :source, :collection, :metadata])
    |> validate_required([:question])
  end

  @doc """
  Add relevant chunks to a test case.

  Creates a changeset that will update the many-to-many association
  with the provided chunks. Use with `Repo.update/1`.

  ## Parameters
    - `test_case` - The test case to update
    - `chunks` - List of Chunk structs to link as ground truth

  ## Examples

      test_case
      |> TestCase.add_relevant_chunks([chunk1, chunk2])
      |> Repo.update()
  """
  @spec add_relevant_chunks(t(), [Chunk.t()]) :: Ecto.Changeset.t()
  def add_relevant_chunks(test_case, chunks) when is_list(chunks) do
    test_case
    |> cast(%{}, [])
    |> put_assoc(:relevant_chunks, chunks)
  end
end
