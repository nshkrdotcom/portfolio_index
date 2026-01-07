defmodule PortfolioIndex.Adapters.RateLimiter do
  @moduledoc """
  Rate limiter adapter using Foundation resilience primitives.

  Provides per-provider rate limiting with backoff windows for API calls.
  Uses Foundation.RateLimit.BackoffWindow for tracking backoff state.

  ## Usage

      # Check if request is allowed
      case RateLimiter.check(:openai) do
        :ok -> make_api_call()
        {:backoff, ms} -> Process.sleep(ms)
      end

      # Or block until allowed
      RateLimiter.wait(:openai)
      make_api_call()

      # Record outcomes for adaptive limiting
      case result do
        {:ok, _} -> RateLimiter.record_success(:openai, :chat)
        {:error, :rate_limited} -> RateLimiter.record_failure(:openai, :chat, :rate_limited)
      end

  ## Default Backoff Durations

  - `:rate_limited` (429) - 60 seconds
  - `:timeout` - 5 seconds
  - `:server_error` (5xx) - 10 seconds
  - Other failures - 2 seconds
  """

  @behaviour PortfolioCore.Ports.RateLimiter

  alias Foundation.RateLimit.BackoffWindow

  # Named registry for rate limiter backoff windows
  @registry_name :portfolio_rate_limiter_registry

  # Default backoff durations in milliseconds
  @backoff_durations %{
    rate_limited: 60_000,
    timeout: 5_000,
    server_error: 10_000,
    default: 2_000
  }

  # ETS table for tracking success/failure counts
  @stats_table :rate_limiter_stats

  @registry_override_key {__MODULE__, :registry_name}
  @stats_override_key {__MODULE__, :stats_table}

  @doc false
  def registry_name do
    Process.get(@registry_override_key) ||
      Application.get_env(:portfolio_index, :rate_limiter_registry, @registry_name)
  end

  @doc false
  def stats_table do
    Process.get(@stats_override_key) ||
      Application.get_env(:portfolio_index, :rate_limiter_stats_table, @stats_table)
  end

  @doc false
  def __supertester_set_table__(:registry_name, table) do
    Process.put(@registry_override_key, table)
  end

  def __supertester_set_table__(:stats_table, table) do
    Process.put(@stats_override_key, table)
  end

  def __supertester_set_table__(_key, _table), do: :ok

  @doc """
  Check if a request to the provider is currently allowed.
  """
  @impl true
  def check(provider) do
    check(provider, :default)
  end

  @doc """
  Check if a request to the provider for a specific operation is allowed.
  """
  @impl true
  def check(provider, operation) do
    key = make_key(provider, operation)
    limiter = get_limiter(key)

    if BackoffWindow.should_backoff?(limiter) do
      # Calculate remaining backoff time
      backoff_until = :atomics.get(limiter, 1)
      now = System.monotonic_time(:millisecond)
      remaining = max(0, backoff_until - now)
      {:backoff, remaining}
    else
      :ok
    end
  end

  @doc """
  Block until a request to the provider is allowed.
  """
  @impl true
  def wait(provider) do
    wait(provider, :default)
  end

  @doc """
  Block until a request to the provider for a specific operation is allowed.
  """
  @impl true
  def wait(provider, operation) do
    key = make_key(provider, operation)
    limiter = get_limiter(key)
    BackoffWindow.wait(limiter)
    :ok
  end

  @doc """
  Record a successful API call.
  """
  @impl true
  def record_success(provider, operation) do
    key = make_key(provider, operation)
    limiter = get_limiter(key)

    # Clear any active backoff
    BackoffWindow.clear(limiter)

    # Update stats
    _ = ensure_stats_table()
    update_stats(key, :success)

    :ok
  end

  @doc """
  Record a failed API call.
  """
  @impl true
  def record_failure(provider, operation, reason) do
    key = make_key(provider, operation)
    limiter = get_limiter(key)

    # Set backoff based on failure reason
    duration = Map.get(@backoff_durations, reason, @backoff_durations.default)
    BackoffWindow.set(limiter, duration)

    # Update stats
    _ = ensure_stats_table()
    update_stats(key, :failure, reason)

    :ok
  end

  @doc """
  Configure rate limits for a provider.

  Note: This implementation primarily uses backoff windows.
  Configuration is stored but limits are enforced via backoff behavior.
  """
  @impl true
  def configure(provider, config) do
    _ = ensure_stats_table()
    :ets.insert(stats_table(), {{:config, provider}, config})
    :ok
  end

  @doc """
  Get the current status of rate limiting for a provider.
  """
  @impl true
  def status(provider) do
    key = make_key(provider, :default)
    limiter = get_limiter(key)
    in_backoff = BackoffWindow.should_backoff?(limiter)

    backoff_until =
      if in_backoff do
        backoff_until_ms = :atomics.get(limiter, 1)
        # Convert monotonic time to DateTime (approximate)
        now_mono = System.monotonic_time(:millisecond)
        diff_ms = backoff_until_ms - now_mono
        DateTime.add(DateTime.utc_now(), diff_ms, :millisecond)
      else
        nil
      end

    _ = ensure_stats_table()
    stats = get_stats(key)

    %{
      provider: provider,
      in_backoff: in_backoff,
      backoff_until: backoff_until,
      success_count: stats.success_count,
      failure_count: stats.failure_count,
      last_failure: stats.last_failure
    }
  end

  # Private helpers

  defp get_limiter(key) do
    registry = ensure_registry()

    try do
      BackoffWindow.for_key(registry, key)
    rescue
      ArgumentError ->
        registry = ensure_registry()
        BackoffWindow.for_key(registry, key)
    end
  end

  defp ensure_registry do
    registry = registry_name() || @registry_name

    cond do
      is_atom(registry) ->
        case :ets.whereis(registry) do
          :undefined ->
            try do
              BackoffWindow.new_registry(name: registry)
            rescue
              ArgumentError ->
                registry
            end

          _tid ->
            registry
        end

      is_reference(registry) ->
        case :ets.info(registry) do
          :undefined ->
            new_registry = BackoffWindow.new_registry()
            set_registry_override(new_registry)
            new_registry

          _info ->
            registry
        end

      true ->
        registry
    end
  end

  defp make_key(provider, operation) do
    {provider, operation}
  end

  defp ensure_stats_table do
    table = stats_table() || @stats_table

    cond do
      is_atom(table) ->
        case :ets.whereis(table) do
          :undefined ->
            create_named_stats_table(table)

          _tid ->
            :ok
        end

      is_reference(table) ->
        case :ets.info(table) do
          :undefined ->
            new_table = create_stats_table()
            set_stats_override(new_table)
            :ok

          _info ->
            :ok
        end

      true ->
        :ok
    end
  end

  defp create_named_stats_table(name) do
    try do
      :ets.new(name, [
        :named_table,
        :public,
        :set,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

      :ok
    rescue
      ArgumentError -> :ok
    end
  end

  defp create_stats_table do
    :ets.new(:rate_limiter_stats, [
      :public,
      :set,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
  end

  defp set_registry_override(registry) do
    if Process.get(@registry_override_key) do
      Process.put(@registry_override_key, registry)
    else
      Application.put_env(:portfolio_index, :rate_limiter_registry, registry)
    end
  end

  defp set_stats_override(table) do
    if Process.get(@stats_override_key) do
      Process.put(@stats_override_key, table)
    else
      Application.put_env(:portfolio_index, :rate_limiter_stats_table, table)
    end
  end

  defp update_stats(key, :success) do
    table = stats_table()

    case safe_lookup(table, {:stats, key}) do
      [{_, stats}] ->
        new_stats = %{stats | success_count: stats.success_count + 1}
        :ets.insert(table, {{:stats, key}, new_stats})

      [] ->
        :ets.insert(
          table,
          {{:stats, key}, %{success_count: 1, failure_count: 0, last_failure: nil}}
        )

      :missing ->
        _ = ensure_stats_table()
        update_stats(key, :success)
    end
  end

  defp update_stats(key, :failure, reason) do
    table = stats_table()

    case safe_lookup(table, {:stats, key}) do
      [{_, stats}] ->
        new_stats = %{stats | failure_count: stats.failure_count + 1, last_failure: reason}
        :ets.insert(table, {{:stats, key}, new_stats})

      [] ->
        :ets.insert(
          table,
          {{:stats, key}, %{success_count: 0, failure_count: 1, last_failure: reason}}
        )

      :missing ->
        _ = ensure_stats_table()
        update_stats(key, :failure, reason)
    end
  end

  defp get_stats(key) do
    case safe_lookup(stats_table(), {:stats, key}) do
      [{_, stats}] -> stats
      [] -> %{success_count: 0, failure_count: 0, last_failure: nil}
      :missing -> %{success_count: 0, failure_count: 0, last_failure: nil}
    end
  end

  defp safe_lookup(table, key) do
    :ets.lookup(table, key)
  rescue
    ArgumentError -> :missing
  end
end
