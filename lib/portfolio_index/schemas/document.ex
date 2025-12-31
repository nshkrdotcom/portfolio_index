defmodule PortfolioIndex.Schemas.Document do
  @moduledoc """
  Ecto schema for ingested documents.
  Tracks document metadata, status, and relationship to chunks.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :pending | :processing | :completed | :failed | :deleted

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "portfolio_documents" do
    field(:source_id, :string)
    field(:content_hash, :string)
    field(:title, :string)
    field(:source_path, :string)
    field(:metadata, :map, default: %{})

    field(:status, Ecto.Enum,
      values: [:pending, :processing, :completed, :failed, :deleted],
      default: :pending
    )

    field(:error_message, :string)
    field(:chunk_count, :integer, default: 0)

    belongs_to(:collection, PortfolioIndex.Schemas.Collection)
    has_many(:chunks, PortfolioIndex.Schemas.Chunk)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating documents.

  ## Optional fields
    - `:source_id` - External identifier for the source document
    - `:content_hash` - SHA256 hash of content for deduplication
    - `:title` - Human-readable title
    - `:source_path` - Original file path
    - `:metadata` - Arbitrary metadata map
    - `:status` - Processing status (default: :pending)
    - `:error_message` - Error message if processing failed
    - `:chunk_count` - Number of chunks generated
    - `:collection_id` - Parent collection ID

  ## Examples

      iex> changeset(%Document{}, %{title: "My Document"})
      #Ecto.Changeset<...>

      iex> changeset(%Document{}, %{source_path: "/docs/readme.md", status: :processing})
      #Ecto.Changeset<...>
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :source_id,
      :content_hash,
      :title,
      :source_path,
      :metadata,
      :status,
      :error_message,
      :chunk_count,
      :collection_id
    ])
    |> validate_number(:chunk_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:collection_id)
  end

  @doc """
  Changeset for updating document status.

  Clears error_message when transitioning to a non-failed status,
  unless a new error message is provided.

  ## Parameters
    - `document` - The document to update
    - `status` - New status value
    - `error_message` - Optional error message (only for :failed status)

  ## Examples

      iex> status_changeset(document, :processing)
      #Ecto.Changeset<...>

      iex> status_changeset(document, :failed, "Connection timeout")
      #Ecto.Changeset<...>
  """
  @spec status_changeset(t(), status(), String.t() | nil) :: Ecto.Changeset.t()
  def status_changeset(document, status, error_message \\ nil) do
    # Clear error message when transitioning away from failed status
    error_msg =
      if status == :failed do
        error_message
      else
        nil
      end

    document
    |> cast(%{status: status, error_message: error_msg}, [:status, :error_message])
    |> validate_required([:status])
  end

  @doc """
  Compute content hash for deduplication.

  Computes a SHA256 hash of the given content string and returns
  it as a lowercase hexadecimal string.

  ## Parameters
    - `content` - The content string to hash

  ## Examples

      iex> Document.compute_hash("Hello, world!")
      "315f5bdb76d078c43b8ac0064e4a0164612b1fce77c869345bfc94c75894edd3"
  """
  @spec compute_hash(String.t()) :: String.t()
  def compute_hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
