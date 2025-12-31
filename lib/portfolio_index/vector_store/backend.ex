defmodule PortfolioIndex.VectorStore.Backend do
  @moduledoc """
  Backend resolution and override utilities for vector store operations.
  Allows per-call backend switching without global configuration changes.

  ## Usage

      # Use default backend from config
      Backend.search(embedding, limit: 5)

      # Override backend for this call
      Backend.search(embedding, limit: 5, backend: :memory)

      # Use specific backend module
      Backend.search(embedding, backend: PortfolioIndex.Adapters.VectorStore.Qdrant)

      # Use module with options
      Backend.search(embedding, backend: {Memory, store: pid})

  ## Configuration

      config :portfolio_index, PortfolioIndex.VectorStore.Backend,
        default: :pgvector

  ## Backend Aliases

  The following aliases are available for convenience:

    * `:pgvector` - `PortfolioIndex.Adapters.VectorStore.Pgvector`
    * `:memory` - `PortfolioIndex.Adapters.VectorStore.Memory`
    * `:qdrant` - `PortfolioIndex.Adapters.VectorStore.Qdrant` (if available)

  """

  alias PortfolioIndex.Adapters.VectorStore

  @type backend_spec :: atom() | module() | {module(), keyword()}

  @backend_aliases %{
    pgvector: VectorStore.Pgvector,
    qdrant: VectorStore.Qdrant,
    memory: VectorStore.Memory
  }

  @doc """
  Resolve backend specification to module and options.

  ## Examples

      iex> Backend.resolve(:memory)
      {PortfolioIndex.Adapters.VectorStore.Memory, []}

      iex> Backend.resolve({Memory, store: pid})
      {PortfolioIndex.Adapters.VectorStore.Memory, [store: pid]}

      iex> Backend.resolve(nil)
      {PortfolioIndex.Adapters.VectorStore.Pgvector, []}  # default

  """
  @spec resolve(backend_spec() | nil) :: {module(), keyword()}
  def resolve(nil), do: default()

  def resolve({module, opts}) when is_atom(module) and is_list(opts) do
    {resolve_alias(module), opts}
  end

  def resolve(backend) when is_atom(backend) do
    {resolve_alias(backend), []}
  end

  @doc """
  Get the default backend from configuration.

  Returns `{module, opts}` tuple.
  """
  @spec default() :: {module(), keyword()}
  def default do
    config = Application.get_env(:portfolio_index, __MODULE__, [])
    backend = Keyword.get(config, :default, :pgvector)
    opts = Keyword.get(config, :opts, [])

    {resolve_alias(backend), opts}
  end

  @doc """
  Execute search with backend resolution.

  The `:backend` option is extracted from opts and used to resolve the backend.
  Remaining options are passed to the backend's search function.

  ## Options

    * `:backend` - Backend specification (see module docs)
    * `:limit` - Maximum number of results (default: 10)
    * `:min_score` - Minimum similarity score
    * `:filter` - Metadata filter

  """
  @spec search([float()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(embedding, opts \\ []) do
    {backend_spec, opts} = Keyword.pop(opts, :backend)
    {module, backend_opts} = resolve(backend_spec)

    dispatch_search(module, embedding, backend_opts, opts)
  end

  @doc """
  Execute insert with backend resolution.

  ## Options

    * `:backend` - Backend specification (see module docs)

  """
  @spec insert(String.t(), [float()], map(), keyword()) :: :ok | {:error, term()}
  def insert(id, embedding, metadata, opts \\ []) do
    {backend_spec, opts} = Keyword.pop(opts, :backend)
    {module, backend_opts} = resolve(backend_spec)

    dispatch_insert(module, id, embedding, metadata, backend_opts, opts)
  end

  @doc """
  Execute batch insert with backend resolution.

  ## Options

    * `:backend` - Backend specification (see module docs)

  """
  @spec insert_batch([{String.t(), [float()], map()}], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def insert_batch(items, opts \\ []) do
    {backend_spec, opts} = Keyword.pop(opts, :backend)
    {module, backend_opts} = resolve(backend_spec)

    dispatch_insert_batch(module, items, backend_opts, opts)
  end

  @doc """
  Execute delete with backend resolution.

  ## Options

    * `:backend` - Backend specification (see module docs)

  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(id, opts \\ []) do
    {backend_spec, opts} = Keyword.pop(opts, :backend)
    {module, backend_opts} = resolve(backend_spec)

    dispatch_delete(module, id, backend_opts, opts)
  end

  @doc """
  Get item by ID with backend resolution.

  ## Options

    * `:backend` - Backend specification (see module docs)

  """
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, :not_found} | {:error, term()}
  def get(id, opts \\ []) do
    {backend_spec, opts} = Keyword.pop(opts, :backend)
    {module, backend_opts} = resolve(backend_spec)

    dispatch_get(module, id, backend_opts, opts)
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp resolve_alias(alias_or_module) do
    Map.get(@backend_aliases, alias_or_module, alias_or_module)
  end

  # Memory backend uses GenServer store
  defp dispatch_search(VectorStore.Memory, embedding, backend_opts, opts) do
    store = Keyword.fetch!(backend_opts, :store)
    VectorStore.Memory.search(store, embedding, opts)
  end

  # Pgvector uses index_id pattern
  defp dispatch_search(VectorStore.Pgvector, embedding, _backend_opts, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    k = Keyword.get(opts, :limit, 10)
    VectorStore.Pgvector.search(index_id, embedding, k, opts)
  end

  # Generic module dispatch
  defp dispatch_search(module, embedding, _backend_opts, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    k = Keyword.get(opts, :limit, 10)
    module.search(index_id, embedding, k, opts)
  end

  defp dispatch_insert(VectorStore.Memory, id, embedding, metadata, backend_opts, opts) do
    store = Keyword.fetch!(backend_opts, :store)
    VectorStore.Memory.insert(store, id, embedding, metadata, opts)
  end

  defp dispatch_insert(VectorStore.Pgvector, id, embedding, metadata, _backend_opts, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    VectorStore.Pgvector.store(index_id, id, embedding, metadata)
  end

  defp dispatch_insert(module, id, embedding, metadata, _backend_opts, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    module.store(index_id, id, embedding, metadata)
  end

  defp dispatch_insert_batch(VectorStore.Memory, items, backend_opts, opts) do
    store = Keyword.fetch!(backend_opts, :store)
    VectorStore.Memory.insert_batch(store, items, opts)
  end

  defp dispatch_insert_batch(VectorStore.Pgvector, items, _backend_opts, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    VectorStore.Pgvector.store_batch(index_id, items)
  end

  defp dispatch_insert_batch(module, items, _backend_opts, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    module.store_batch(index_id, items)
  end

  defp dispatch_delete(VectorStore.Memory, id, backend_opts, opts) do
    store = Keyword.fetch!(backend_opts, :store)
    VectorStore.Memory.delete(store, id, opts)
  end

  defp dispatch_delete(VectorStore.Pgvector, id, _backend_opts, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    VectorStore.Pgvector.delete(index_id, id)
  end

  defp dispatch_delete(module, id, _backend_opts, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    module.delete(index_id, id)
  end

  defp dispatch_get(VectorStore.Memory, id, backend_opts, opts) do
    store = Keyword.fetch!(backend_opts, :store)
    VectorStore.Memory.get(store, id, opts)
  end

  defp dispatch_get(VectorStore.Pgvector, _id, _backend_opts, _opts) do
    # Pgvector doesn't have a direct get - would need to implement
    {:error, :not_implemented}
  end

  defp dispatch_get(_module, _id, _backend_opts, _opts) do
    {:error, :not_implemented}
  end
end
