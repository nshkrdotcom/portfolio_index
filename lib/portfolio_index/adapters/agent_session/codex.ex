defmodule PortfolioIndex.Adapters.AgentSession.Codex do
  @moduledoc """
  Agent session adapter for Codex (OpenAI).

  Implements `PortfolioCore.Ports.AgentSession` by delegating to
  `AgentSessionManager.SessionManager` with `AgentSessionManager.Adapters.CodexAdapter`
  as the underlying provider.

  ## Architecture

      PortfolioIndex.Adapters.AgentSession.Codex  (this module - port impl)
          |
      AgentSessionManager.SessionManager          (orchestration)
          |
      AgentSessionManager.Adapters.CodexAdapter   (provider adapter)

  ## Configuration

      config :portfolio_index, :agent_session,
        store: {AgentSessionManager.Adapters.InMemorySessionStore, []},
        codex: {AgentSessionManager.Adapters.CodexAdapter, [working_directory: "/tmp"]}

  ## Rate Limiting

  All `execute/3` calls go through `PortfolioIndex.Adapters.RateLimiter` before
  delegating to the SessionManager.

  ## Telemetry

  Emits the following telemetry events:

    - `[:portfolio_index, :agent_session, :start_session, :start | :stop | :exception]`
    - `[:portfolio_index, :agent_session, :execute, :start | :stop | :exception]`
    - `[:portfolio_index, :agent_session, :cancel, :start | :stop | :exception]`
    - `[:portfolio_index, :agent_session, :end_session, :start | :stop | :exception]`
  """

  @behaviour PortfolioCore.Ports.AgentSession

  require Logger

  alias AgentSessionManager.SessionManager
  alias PortfolioIndex.Adapters.AgentSession.Config
  alias PortfolioIndex.Adapters.RateLimiter

  @provider :codex
  @adapter_module AgentSessionManager.Adapters.CodexAdapter

  # ===========================================================================
  # AgentSession Callbacks
  # ===========================================================================

  @impl true
  def provider_name, do: "codex"

  @impl true
  def capabilities do
    {:ok,
     [
       %{name: "streaming", type: :sampling, enabled: true},
       %{name: "tool_use", type: :tool, enabled: true},
       %{name: "interrupt", type: :sampling, enabled: true},
       %{name: "mcp", type: :tool, enabled: true},
       %{name: "file_operations", type: :tool, enabled: true},
       %{name: "bash", type: :tool, enabled: true}
     ]}
  end

  @impl true
  def validate_config(config) do
    cond do
      not is_map(config) ->
        {:error, "config must be a map"}

      not Map.has_key?(config, :working_directory) ->
        {:error, "working_directory is required"}

      not is_binary(config.working_directory) ->
        {:error, "working_directory must be a string"}

      config.working_directory == "" ->
        {:error, "working_directory cannot be empty"}

      true ->
        :ok
    end
  end

  @impl true
  def start_session(agent_id, opts \\ []) do
    metadata = telemetry_metadata(%{agent_id: agent_id})

    :telemetry.span(
      [:portfolio_index, :agent_session, :start_session],
      metadata,
      fn ->
        result = do_start_session(agent_id, opts)

        case result do
          {:ok, session_id} ->
            {result, Map.put(metadata, :session_id, session_id)}

          {:error, _} = error ->
            {error, metadata}
        end
      end
    )
  end

  @impl true
  def execute(session_id, input, opts \\ []) do
    metadata = telemetry_metadata(%{session_id: session_id})

    :telemetry.span(
      [:portfolio_index, :agent_session, :execute],
      metadata,
      fn ->
        # Rate limit before executing
        RateLimiter.wait(@provider, :agent_session)

        result = do_execute(session_id, input, opts)

        case result do
          {:ok, run_result} ->
            RateLimiter.record_success(@provider, :agent_session)
            enriched = Map.merge(metadata, extract_telemetry_measurements(run_result))
            {result, enriched}

          {:error, :rate_limited} = error ->
            RateLimiter.record_failure(@provider, :agent_session, :rate_limited)
            {error, metadata}

          {:error, _} = error ->
            RateLimiter.record_failure(@provider, :agent_session, :server_error)
            {error, metadata}
        end
      end
    )
  end

  @impl true
  def cancel(session_id, run_id) do
    metadata = telemetry_metadata(%{session_id: session_id, run_id: run_id})

    :telemetry.span(
      [:portfolio_index, :agent_session, :cancel],
      metadata,
      fn ->
        result = do_cancel(session_id, run_id)
        {result, metadata}
      end
    )
  end

  @impl true
  def end_session(session_id) do
    metadata = telemetry_metadata(%{session_id: session_id})

    :telemetry.span(
      [:portfolio_index, :agent_session, :end_session],
      metadata,
      fn ->
        result = do_end_session(session_id)
        {result, metadata}
      end
    )
  end

  # ===========================================================================
  # Private Implementation
  # ===========================================================================

  defp do_start_session(agent_id, opts) do
    with {:ok, store} <- resolve_store(opts),
         {:ok, adapter} <- resolve_adapter(opts) do
      attrs = %{
        agent_id: agent_id,
        context: Keyword.get(opts, :context, %{}),
        metadata: Keyword.get(opts, :metadata, %{}),
        tags: Keyword.get(opts, :tags, [])
      }

      case SessionManager.start_session(store, adapter, attrs) do
        {:ok, session} ->
          case SessionManager.activate_session(store, session.id) do
            {:ok, _activated} -> {:ok, session.id}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_execute(session_id, input, opts) do
    with {:ok, store} <- resolve_store(opts),
         {:ok, adapter} <- resolve_adapter(opts) do
      input_map = normalize_input(input)

      case SessionManager.start_run(store, adapter, session_id, input_map, opts) do
        {:ok, run} ->
          case SessionManager.execute_run(store, adapter, run.id) do
            {:ok, result} ->
              {:ok, normalize_run_result(result)}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_cancel(session_id, run_id) do
    with {:ok, store} <- resolve_store([]),
         {:ok, adapter} <- resolve_adapter([]) do
      case SessionManager.get_session(store, session_id) do
        {:ok, _session} ->
          case SessionManager.cancel_run(store, adapter, run_id) do
            {:ok, cancelled_run_id} -> {:ok, cancelled_run_id}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_end_session(session_id) do
    with {:ok, store} <- resolve_store([]) do
      case SessionManager.complete_session(store, session_id) do
        {:ok, _session} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp resolve_store(opts) do
    case Config.resolve_store(opts) do
      {:error, _} = error -> error
      store -> {:ok, store}
    end
  end

  defp resolve_adapter(opts) do
    case Config.resolve_adapter(@provider, opts) do
      {:error, _} = error ->
        error

      adapter when is_pid(adapter) ->
        {:ok, ensure_named_adapter(adapter)}

      adapter ->
        {:ok, adapter}
    end
  end

  defp ensure_named_adapter(pid) do
    case Process.whereis(@adapter_module) do
      ^pid -> @adapter_module
      nil -> pid
      _other -> pid
    end
  end

  defp normalize_input(input) when is_map(input), do: input
  defp normalize_input(input) when is_binary(input), do: %{prompt: input}
  defp normalize_input(input), do: %{data: input}

  defp normalize_run_result(result) when is_map(result) do
    %{
      output: Map.get(result, :output),
      token_usage: Map.get(result, :token_usage),
      turn_count: Map.get(result, :turn_count, 1),
      events: Map.get(result, :events, [])
    }
  end

  defp extract_telemetry_measurements(run_result) do
    token_usage = Map.get(run_result, :token_usage, %{})

    %{
      input_tokens: Map.get(token_usage, :input_tokens, 0),
      output_tokens: Map.get(token_usage, :output_tokens, 0),
      turn_count: Map.get(run_result, :turn_count, 1)
    }
  end

  defp telemetry_metadata(extra) do
    Map.merge(%{provider: "codex"}, extra)
  end
end
