defmodule PortfolioIndex.VectorStore.IndexManager do
  @moduledoc """
  Manages vector store indexes including auto-creation and configuration.

  This module provides a unified interface for index lifecycle management
  across different vector store backends. It abstracts the differences
  between backends like pgvector (table-based) and memory (GenServer-based).

  ## Usage

      # Ensure index exists, creating if necessary
      IndexManager.ensure_index(Pgvector, index_id: "my_index", dimensions: 768)

      # Check if index exists
      IndexManager.index_exists?(Pgvector, index_id: "my_index")

      # Get index statistics
      {:ok, stats} = IndexManager.index_stats(Pgvector, index_id: "my_index")

      # Rebuild index (after bulk inserts)
      IndexManager.rebuild_index(Pgvector, index_id: "my_index")

  ## Backend-Specific Options

  ### pgvector

    * `:index_id` - Unique identifier for the index (required)
    * `:dimensions` - Vector dimensions (required for creation)
    * `:metric` - Distance metric: `:cosine`, `:euclidean`, `:dot_product` (default: `:cosine`)
    * `:index_type` - Index type: `:hnsw`, `:ivfflat`, `:flat` (default: `:hnsw`)
    * `:m` - HNSW m parameter (default: 16)
    * `:ef_construction` - HNSW ef_construction (default: 64)
    * `:lists` - IVFFlat lists parameter (default: 100)

  ### memory

    * `:store` - GenServer pid or name (required)
    * `:dimensions` - Vector dimensions (optional, auto-detected)
    * `:max_elements` - Maximum elements (default: 10,000)

  """

  alias PortfolioIndex.Adapters.VectorStore.{Memory, Pgvector}

  @doc """
  Ensure index exists, creating if necessary.

  Options vary by backend:
  - pgvector: Creates HNSW index on embedding column
  - qdrant: Creates collection with specified config
  - memory: Initializes HNSWLib index (already done at GenServer start)
  """
  @spec ensure_index(module(), keyword()) :: :ok | {:error, term()}
  def ensure_index(backend, opts \\ [])

  def ensure_index(Memory, opts) do
    # Memory store creates index on start_link, just verify it's running
    store = Keyword.get(opts, :store)

    if store && Process.alive?(store) do
      :ok
    else
      {:error, :store_not_running}
    end
  end

  def ensure_index(Pgvector, opts) do
    index_id = Keyword.fetch!(opts, :index_id)
    dimensions = Keyword.fetch!(opts, :dimensions)
    metric = Keyword.get(opts, :metric, :cosine)
    index_type = Keyword.get(opts, :index_type, :hnsw)

    config = %{
      dimensions: dimensions,
      metric: metric,
      index_type: index_type,
      options: build_index_options(index_type, opts)
    }

    case Pgvector.create_index(index_id, config) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def ensure_index(module, opts) do
    # Generic fallback for other modules implementing VectorStore
    index_id = Keyword.get(opts, :index_id, "default")
    dimensions = Keyword.get(opts, :dimensions, 384)
    config = %{dimensions: dimensions, metric: Keyword.get(opts, :metric, :cosine)}

    case module.create_index(index_id, config) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if index exists.
  """
  @spec index_exists?(module(), keyword()) :: boolean()
  def index_exists?(backend, opts \\ [])

  def index_exists?(Memory, opts) do
    store = Keyword.get(opts, :store)
    store && Process.alive?(store)
  end

  def index_exists?(Pgvector, opts) do
    index_id = Keyword.fetch!(opts, :index_id)
    Pgvector.index_exists?(index_id)
  end

  def index_exists?(module, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    module.index_exists?(index_id)
  end

  @doc """
  Get index statistics.
  """
  @spec index_stats(module(), keyword()) :: {:ok, map()} | {:error, term()}
  def index_stats(backend, opts \\ [])

  def index_stats(Memory, opts) do
    store = Keyword.get(opts, :store)

    if store do
      stats = Memory.stats(store)

      {:ok,
       %{
         count: stats.count,
         dimensions: stats.dimensions,
         metric: :cosine,
         size_bytes: nil
       }}
    else
      {:error, :store_not_specified}
    end
  end

  def index_stats(Pgvector, opts) do
    index_id = Keyword.fetch!(opts, :index_id)
    Pgvector.index_stats(index_id)
  end

  def index_stats(module, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    module.index_stats(index_id)
  end

  @doc """
  Rebuild index (useful after bulk inserts).

  For pgvector, this triggers REINDEX on the vector index.
  For memory stores, this is a no-op as HNSWLib maintains its index.
  """
  @spec rebuild_index(module(), keyword()) :: :ok | {:error, term()}
  def rebuild_index(backend, opts \\ [])

  def rebuild_index(Memory, _opts) do
    # HNSWLib maintains index automatically
    :ok
  end

  def rebuild_index(Pgvector, opts) do
    index_id = Keyword.fetch!(opts, :index_id)
    table_name = "vectors_#{String.replace(String.downcase(index_id), ~r/[^a-zA-Z0-9_]/, "_")}"
    index_name = "#{table_name}_embedding_idx"

    sql = "REINDEX INDEX #{index_name}"

    case PortfolioIndex.Repo.query(sql) do
      {:ok, _} -> :ok
      {:error, %Postgrex.Error{postgres: %{code: :undefined_object}}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def rebuild_index(_module, _opts) do
    # Generic no-op
    :ok
  end

  @doc """
  Drop index.
  """
  @spec drop_index(module(), keyword()) :: :ok | {:error, term()}
  def drop_index(backend, opts \\ [])

  def drop_index(Memory, opts) do
    store = Keyword.get(opts, :store)

    if store do
      Memory.clear(store)
    else
      {:error, :store_not_specified}
    end
  end

  def drop_index(Pgvector, opts) do
    index_id = Keyword.fetch!(opts, :index_id)
    Pgvector.delete_index(index_id)
  end

  def drop_index(module, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    module.delete_index(index_id)
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp build_index_options(:hnsw, opts) do
    %{
      m: Keyword.get(opts, :m, 16),
      ef_construction: Keyword.get(opts, :ef_construction, 64)
    }
  end

  defp build_index_options(:ivfflat, opts) do
    %{
      lists: Keyword.get(opts, :lists, 100)
    }
  end

  defp build_index_options(_type, _opts), do: %{}
end
