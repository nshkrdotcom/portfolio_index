defmodule PortfolioIndex.Schemas.Chunk do
  @moduledoc """
  Ecto schema for document chunks with vector embeddings.
  Supports pgvector for similarity search.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_chunks" do
    field(:content, :string)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:chunk_index, :integer)
    field(:token_count, :integer)
    field(:start_char, :integer)
    field(:end_char, :integer)
    field(:metadata, :map, default: %{})

    belongs_to(:document, PortfolioIndex.Schemas.Document)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating chunks.

  ## Required fields
    - `:content` - The text content of the chunk
    - `:chunk_index` - Position of chunk within document (0-indexed)

  ## Optional fields
    - `:embedding` - Vector embedding (use `embedding_changeset/2` to set)
    - `:token_count` - Number of tokens in chunk
    - `:start_char` - Starting character offset in original document
    - `:end_char` - Ending character offset in original document
    - `:metadata` - Arbitrary metadata map
    - `:document_id` - Parent document ID

  ## Examples

      iex> changeset(%Chunk{}, %{content: "Hello world", chunk_index: 0})
      #Ecto.Changeset<...>

      iex> changeset(%Chunk{}, %{
      ...>   content: "Chunk text",
      ...>   chunk_index: 5,
      ...>   token_count: 42,
      ...>   start_char: 100,
      ...>   end_char: 200
      ...> })
      #Ecto.Changeset<...>
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [
      :content,
      :embedding,
      :chunk_index,
      :token_count,
      :start_char,
      :end_char,
      :metadata,
      :document_id
    ])
    |> validate_required([:content, :chunk_index])
    |> validate_number(:chunk_index, greater_than_or_equal_to: 0)
    |> validate_number(:token_count, greater_than_or_equal_to: 0)
    |> validate_number(:start_char, greater_than_or_equal_to: 0)
    |> validate_number(:end_char, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:document_id)
  end

  @doc """
  Changeset for updating embedding.

  Converts a list of floats to a Pgvector and updates the chunk.

  ## Parameters
    - `chunk` - The chunk to update
    - `embedding` - List of float values representing the embedding vector

  ## Examples

      iex> embedding_changeset(chunk, [0.1, 0.2, 0.3, ...])
      #Ecto.Changeset<...>
  """
  @spec embedding_changeset(t(), [float()]) :: Ecto.Changeset.t()
  def embedding_changeset(chunk, embedding) when is_list(embedding) do
    pgvector = Pgvector.new(embedding)

    chunk
    |> cast(%{}, [])
    |> put_change(:embedding, pgvector)
  end
end
