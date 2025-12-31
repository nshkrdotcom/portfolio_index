# credo:disable-for-this-file Credo.Check.Refactor.Apply
defmodule PortfolioIndex.Adapters.VectorStore.Memory do
  @moduledoc """
  In-memory vector store using HNSWLib for fast similarity search.
  Useful for testing, development, and small datasets.

  ## Configuration

      config :portfolio_index, PortfolioIndex.Adapters.VectorStore.Memory,
        dimensions: 384,
        max_elements: 10_000,
        ef_construction: 200,
        m: 16

  ## Usage

  Add to supervision tree:

      children = [
        {PortfolioIndex.Adapters.VectorStore.Memory, name: :my_index, dimensions: 384}
      ]

  Or start manually:

      {:ok, pid} = Memory.start_link(name: :my_index, dimensions: 384)

  ## Examples

      # Insert a vector
      :ok = Memory.insert(pid, "doc_1", embedding, %{content: "hello"})

      # Search for similar vectors
      {:ok, results} = Memory.search(pid, query_embedding, limit: 10)

      # Delete a vector
      :ok = Memory.delete(pid, "doc_1")

  ## Notes

  - Data is not persisted across restarts by default
  - Supports optional file-based persistence via save/load
  - Thread-safe for concurrent reads and writes
  - Uses soft deletion (vectors marked as deleted but not removed from index)
  """

  @behaviour PortfolioCore.Ports.VectorStore

  use GenServer

  require Logger

  @default_opts [
    max_elements: 10_000,
    ef_construction: 200,
    m: 16,
    space: :cosine,
    dimensions: 384
  ]

  @type store :: GenServer.server()
  @type id :: String.t()
  @type embedding :: [float()]
  @type metadata :: map()

  # =============================================================================
  # Client API
  # =============================================================================

  @doc """
  Starts the Memory vector store GenServer.

  ## Options

    * `:name` - The name to register the GenServer under (optional)
    * `:dimensions` - Vector dimensions (default: 384)
    * `:max_elements` - Maximum number of elements (default: 10,000)
    * `:ef_construction` - HNSW ef_construction parameter (default: 200)
    * `:m` - HNSW m parameter (default: 16)
    * `:space` - Distance metric (default: :cosine)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    unless Code.ensure_loaded?(HNSWLib.Index) do
      raise """
      HNSWLib is required for the in-memory vector store but is not available.

      Add {:hnswlib, "~> 0.1"} to your dependencies in mix.exs.
      """
    end

    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns a child specification for the Memory store.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Insert a vector with metadata.

  ## Parameters

    * `store` - The GenServer pid or name
    * `id` - Unique identifier for the vector
    * `embedding` - The embedding vector as a list of floats
    * `metadata` - A map of metadata associated with the vector
    * `opts` - Options (currently unused)

  ## Returns

    * `:ok` on success
    * `{:error, {:dimension_mismatch, details}}` if dimensions don't match

  """
  @spec insert(store(), id(), embedding(), metadata(), keyword()) :: :ok | {:error, term()}
  def insert(store, id, embedding, metadata \\ %{}, _opts \\ []) do
    GenServer.call(store, {:insert, id, embedding, metadata})
  end

  @doc """
  Insert multiple vectors in batch.

  ## Parameters

    * `store` - The GenServer pid or name
    * `items` - List of `{id, embedding, metadata}` tuples
    * `opts` - Options (currently unused)

  ## Returns

    * `{:ok, count}` with number of vectors inserted
    * `{:error, reason}` on failure

  """
  @spec insert_batch(store(), [{id(), embedding(), metadata()}], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def insert_batch(store, items, _opts \\ []) do
    GenServer.call(store, {:insert_batch, items})
  end

  @doc """
  Search for similar vectors (GenServer API).

  ## Parameters

    * `store` - The GenServer pid or name
    * `embedding` - Query vector
    * `opts` - Search options:
      * `:limit` - Maximum number of results (default: 10)
      * `:min_score` - Minimum similarity score (default: nil)
      * `:include_vector` - Whether to include vectors in results (default: false)

  ## Returns

    * `{:ok, results}` - List of search results with :id, :score, :metadata
    * `{:error, reason}` on failure

  """
  @spec search(store(), embedding(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(store, embedding, opts) when is_list(opts) do
    GenServer.call(store, {:search, embedding, opts})
  end

  @doc """
  Delete a vector by ID.

  Uses soft deletion - the vector is marked as deleted but not removed from
  the HNSWLib index (which doesn't support true deletion).

  ## Parameters

    * `store` - The GenServer pid or name
    * `id` - The vector ID to delete
    * `opts` - Options (currently unused)

  ## Returns

    * `:ok` on success
    * `{:error, :not_found}` if vector doesn't exist

  """
  @spec delete(store(), id(), keyword()) :: :ok | {:error, :not_found | term()}
  def delete(store, id, _opts) when is_pid(store) or is_atom(store) do
    GenServer.call(store, {:delete, id})
  end

  @doc """
  Get a vector by ID.

  ## Parameters

    * `store` - The GenServer pid or name
    * `id` - The vector ID to retrieve
    * `opts` - Options (currently unused)

  ## Returns

    * `{:ok, result}` - Map with :id, :vector, :metadata
    * `{:error, :not_found}` if vector doesn't exist

  """
  @spec get(store(), id(), keyword()) :: {:ok, map()} | {:error, :not_found}
  def get(store, id, _opts \\ []) do
    GenServer.call(store, {:get, id})
  end

  @doc """
  Save index to file.

  Persists the entire index state including vectors, metadata, and deletion
  information to a binary file.

  ## Parameters

    * `store` - The GenServer pid or name
    * `path` - File path to save to

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure

  """
  @spec save(store(), String.t()) :: :ok | {:error, term()}
  def save(store, path) do
    GenServer.call(store, {:save, path})
  end

  @doc """
  Load index from file.

  Restores the entire index state from a previously saved file.

  ## Parameters

    * `store` - The GenServer pid or name
    * `path` - File path to load from

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure

  """
  @spec load(store(), String.t()) :: :ok | {:error, term()}
  def load(store, path) do
    GenServer.call(store, {:load, path})
  end

  @doc """
  Get index statistics.

  ## Returns

  Map with:
    * `:count` - Number of live vectors (excluding deleted)
    * `:dimensions` - Vector dimensions
    * `:max_elements` - Maximum capacity
    * `:deleted_count` - Number of soft-deleted vectors

  """
  @spec stats(store()) :: map()
  def stats(store) do
    GenServer.call(store, :stats)
  end

  @doc """
  Clear all data from the index.

  Removes all vectors and resets the index to empty state.

  """
  @spec clear(store()) :: :ok
  def clear(store) do
    GenServer.call(store, :clear)
  end

  # =============================================================================
  # Behaviour Callbacks (required but delegated)
  # =============================================================================

  @impl PortfolioCore.Ports.VectorStore
  def create_index(_index_id, _config) do
    # Memory store doesn't use separate indices - it's a single store
    :ok
  end

  @impl PortfolioCore.Ports.VectorStore
  def delete_index(_index_id) do
    # Memory store doesn't use separate indices
    :ok
  end

  @impl PortfolioCore.Ports.VectorStore
  def index_stats(_index_id) do
    {:error, :use_stats_function}
  end

  @impl PortfolioCore.Ports.VectorStore
  def index_exists?(_index_id) do
    true
  end

  @impl PortfolioCore.Ports.VectorStore
  def store(_index_id, id, vector, metadata) do
    # Delegate to default server if started with a registered name
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      pid -> insert(pid, id, vector, metadata)
    end
  end

  @impl PortfolioCore.Ports.VectorStore
  def store_batch(_index_id, items) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      pid -> insert_batch(pid, items)
    end
  end

  @impl PortfolioCore.Ports.VectorStore
  def search(_index_id, vector, k, opts) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      pid -> search(pid, vector, Keyword.put(opts, :limit, k))
    end
  end

  @impl PortfolioCore.Ports.VectorStore
  def delete(_index_id, id) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      pid -> delete(pid, id, [])
    end
  end

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl GenServer
  def init(opts) do
    opts = Keyword.merge(@default_opts, opts)
    dimensions = opts[:dimensions]
    max_elements = opts[:max_elements]
    space = opts[:space]

    {:ok, index} = apply(HNSWLib.Index, :new, [space, dimensions, max_elements])

    state = %{
      index: index,
      dimensions: dimensions,
      max_elements: max_elements,
      space: space,
      ids: [],
      vectors: [],
      metadata: [],
      deleted: MapSet.new()
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:insert, id, embedding, metadata}, _from, state) do
    dims = length(embedding)

    if dims != state.dimensions do
      {:reply, {:error, {:dimension_mismatch, %{expected: state.dimensions, got: dims}}}, state}
    else
      state = do_insert(state, id, embedding, metadata)
      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_call({:insert_batch, items}, _from, state) do
    result =
      Enum.reduce_while(items, {:ok, state, 0}, fn {id, embedding, metadata}, {:ok, s, count} ->
        dims = length(embedding)

        if dims != s.dimensions do
          {:halt, {:error, {:dimension_mismatch, %{expected: s.dimensions, got: dims, id: id}}}}
        else
          new_state = do_insert(s, id, embedding, metadata)
          {:cont, {:ok, new_state, count + 1}}
        end
      end)

    case result do
      {:ok, new_state, count} ->
        {:reply, {:ok, count}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:search, query_embedding, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 10)
    min_score = Keyword.get(opts, :min_score)
    include_vector = Keyword.get(opts, :include_vector, false)

    results = do_search(state, query_embedding, limit, min_score, include_vector)
    {:reply, {:ok, results}, state}
  end

  @impl GenServer
  def handle_call({:delete, id}, _from, state) do
    # Find the last non-deleted entry with this id
    case find_live_index(state, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      idx ->
        state = %{state | deleted: MapSet.put(state.deleted, idx)}
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_call({:get, id}, _from, state) do
    # Find the last non-deleted entry with this id
    case find_live_index(state, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      idx ->
        result = %{
          id: Enum.at(state.ids, idx),
          vector: Enum.at(state.vectors, idx),
          metadata: Enum.at(state.metadata, idx)
        }

        {:reply, {:ok, result}, state}
    end
  end

  @impl GenServer
  def handle_call({:save, path}, _from, state) do
    # Save index and state to file
    index_path = path <> ".hnsw"
    state_path = path <> ".meta"

    # Save HNSWLib index
    case apply(HNSWLib.Index, :save_index, [state.index, index_path]) do
      :ok ->
        # Save our metadata
        state_data = %{
          dimensions: state.dimensions,
          max_elements: state.max_elements,
          space: state.space,
          ids: state.ids,
          vectors: state.vectors,
          metadata: state.metadata,
          deleted: MapSet.to_list(state.deleted)
        }

        case File.write(state_path, :erlang.term_to_binary(state_data)) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:load, path}, _from, state) do
    index_path = path <> ".hnsw"
    state_path = path <> ".meta"

    with {:ok, binary} <- File.read(state_path),
         state_data <- :erlang.binary_to_term(binary),
         space <- state_data.space,
         dims <- state_data.dimensions,
         {:ok, index} <- apply(HNSWLib.Index, :load_index, [space, dims, index_path]) do
      new_state = %{
        index: index,
        dimensions: state_data.dimensions,
        max_elements: state_data.max_elements,
        space: state_data.space,
        ids: state_data.ids,
        vectors: state_data.vectors,
        metadata: state_data.metadata,
        deleted: MapSet.new(state_data.deleted)
      }

      {:reply, :ok, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    live_count = length(state.ids) - MapSet.size(state.deleted)

    stats = %{
      count: live_count,
      dimensions: state.dimensions,
      max_elements: state.max_elements,
      deleted_count: MapSet.size(state.deleted)
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call(:clear, _from, state) do
    {:ok, index} = apply(HNSWLib.Index, :new, [state.space, state.dimensions, state.max_elements])

    new_state = %{
      state
      | index: index,
        ids: [],
        vectors: [],
        metadata: [],
        deleted: MapSet.new()
    }

    {:reply, :ok, new_state}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp do_insert(state, id, embedding, metadata) do
    # Check if id already exists - if so, mark old one as deleted
    state =
      case Enum.find_index(state.ids, &(&1 == id)) do
        nil ->
          state

        existing_idx ->
          %{state | deleted: MapSet.put(state.deleted, existing_idx)}
      end

    # Add to HNSWLib index
    tensor = apply(Nx, :tensor, [[embedding], [type: :f32]])
    :ok = apply(HNSWLib.Index, :add_items, [state.index, tensor])

    # Track id, vector, and metadata
    %{
      state
      | ids: state.ids ++ [id],
        vectors: state.vectors ++ [embedding],
        metadata: state.metadata ++ [metadata]
    }
  end

  defp do_search(state, query_embedding, limit, min_score, include_vector) do
    total_count = length(state.ids)

    if total_count == 0 do
      []
    else
      # Request more results to account for deleted items
      k = min(limit + MapSet.size(state.deleted), total_count)

      query = apply(Nx, :tensor, [[query_embedding], [type: :f32]])
      {:ok, labels, distances} = apply(HNSWLib.Index, :knn_query, [state.index, query, [k: k]])

      label_list = apply(Nx, :to_flat_list, [labels])
      distance_list = apply(Nx, :to_flat_list, [distances])

      label_list
      |> Enum.zip(distance_list)
      |> Enum.reject(fn {idx, _distance} -> MapSet.member?(state.deleted, idx) end)
      |> Enum.map(fn {idx, distance} ->
        score = 1.0 - distance

        base = %{
          id: Enum.at(state.ids, idx),
          metadata: Enum.at(state.metadata, idx),
          score: score
        }

        if include_vector do
          Map.put(base, :vector, Enum.at(state.vectors, idx))
        else
          Map.put(base, :vector, nil)
        end
      end)
      |> maybe_filter_by_score(min_score)
      |> Enum.take(limit)
    end
  end

  defp maybe_filter_by_score(results, nil), do: results

  defp maybe_filter_by_score(results, min_score) do
    Enum.filter(results, fn %{score: score} -> score >= min_score end)
  end

  # Find the last non-deleted entry with the given id.
  # Returns the index or nil if not found.
  defp find_live_index(state, id) do
    state.ids
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {stored_id, idx} ->
      if stored_id == id and not MapSet.member?(state.deleted, idx) do
        idx
      end
    end)
  end
end
