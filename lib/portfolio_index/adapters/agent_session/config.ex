defmodule PortfolioIndex.Adapters.AgentSession.Config do
  @moduledoc """
  Resolves SessionStore and ProviderAdapter instances for agent session adapters.

  Agent session adapters need a SessionStore (for persisting session/run/event
  state) and a ProviderAdapter (the underlying agent_session_manager adapter).
  This module resolves those from either explicit opts or Application config.

  ## Application Configuration

      config :portfolio_index, :agent_session,
        store: {AgentSessionManager.Adapters.InMemorySessionStore, []},
        claude: {AgentSessionManager.Adapters.ClaudeAdapter, [model: "claude-sonnet-4-20250514"]},
        codex: {AgentSessionManager.Adapters.CodexAdapter, [working_directory: "/tmp"]}

  ## Runtime Override via Opts

  Both `resolve_store/1` and `resolve_adapter/2` accept opts that can override
  the Application config:

      Config.resolve_store(store: my_store_pid)
      Config.resolve_adapter(:claude, adapter: my_adapter_pid)

  ## Adapter Registration

  When starting adapters from `{module, args}` tuples, the Config module
  registers them with `name: module` so that `ProviderAdapter.name/1` can
  dispatch via the module function rather than GenServer calls.
  """

  @adapter_modules %{
    claude: AgentSessionManager.Adapters.ClaudeAdapter,
    codex: AgentSessionManager.Adapters.CodexAdapter
  }

  @doc """
  Resolves the SessionStore instance from opts or Application config.

  ## Options

    - `:store` - A pid or named process for the session store

  ## Returns

    - A pid or named process reference
    - `{:error, {:not_configured, :store}}` if not configured
  """
  @spec resolve_store(keyword()) :: pid() | atom() | {:error, term()}
  def resolve_store(opts) do
    case Keyword.get(opts, :store) do
      nil -> resolve_from_app_config(:store)
      store -> store
    end
  end

  @doc """
  Resolves the ProviderAdapter instance for the given provider.

  ## Parameters

    - `provider` - The provider atom (`:claude` or `:codex`)
    - `opts` - Options that may contain an `:adapter` override

  ## Returns

    - A pid, named process reference, or module atom
    - `{:error, {:not_configured, provider}}` if not configured
  """
  @spec resolve_adapter(atom(), keyword()) :: pid() | atom() | {:error, term()}
  def resolve_adapter(provider, opts) do
    case Keyword.get(opts, :adapter) do
      nil -> resolve_from_app_config(provider)
      adapter -> adapter
    end
  end

  @doc """
  Returns the adapter module for a given provider atom.
  """
  @spec adapter_module(atom()) :: module() | nil
  def adapter_module(provider) do
    Map.get(@adapter_modules, provider)
  end

  defp resolve_from_app_config(key) do
    config = Application.get_env(:portfolio_index, :agent_session, [])

    case Keyword.get(config, key) do
      {module, args} -> start_if_needed(module, args)
      pid when is_pid(pid) -> pid
      name when is_atom(name) and not is_nil(name) -> name
      nil -> {:error, {:not_configured, key}}
    end
  end

  defp start_if_needed(module, args) do
    # Register with module name so ProviderAdapter.name/1 dispatches via
    # the module function path (is_atom guard) rather than GenServer.call.
    args_with_name = Keyword.put_new(args, :name, module)

    case module.start_link(args_with_name) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      error -> error
    end
  end
end
