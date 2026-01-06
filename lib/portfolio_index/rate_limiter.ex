defmodule PortfolioIndex.RateLimiter do
  @moduledoc """
  Simple ETS-based rate limiter using sliding window counters.

  Replaces Hammer for local use - no need for poolboy/worker pools
  when running a single-user local application.

  ## Usage

      # Check if request is allowed (100 requests per 60 seconds)
      case RateLimiter.check_rate("api_key", 60_000, 100) do
        {:allow, count} -> # proceed
        {:deny, limit} -> # rate limited
      end

  """

  @table_name :portfolio_rate_limiter

  @doc """
  Ensure the ETS table exists.
  """
  @spec ensure_table() :: :ok
  def ensure_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :named_table,
          :public,
          :set,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

        :ok

      _tid ->
        :ok
    end
  end

  @doc """
  Check if a request should be allowed under the rate limit.

  Returns `{:allow, current_count}` if allowed, `{:deny, limit}` if rate limited.

  ## Parameters

    * `key` - Unique identifier for this rate limit bucket
    * `interval_ms` - Time window in milliseconds
    * `limit` - Maximum requests allowed in the window

  """
  @spec check_rate(term(), pos_integer(), pos_integer()) ::
          {:allow, pos_integer()} | {:deny, pos_integer()}
  def check_rate(key, interval_ms, limit) do
    ensure_table()
    now = System.monotonic_time(:millisecond)
    window_start = now - interval_ms

    # Get current bucket state
    case :ets.lookup(@table_name, key) do
      [{^key, timestamps}] ->
        # Filter out old timestamps outside the window
        valid_timestamps = Enum.filter(timestamps, &(&1 > window_start))
        count = length(valid_timestamps)

        if count < limit do
          # Add new timestamp and allow
          new_timestamps = [now | valid_timestamps]
          :ets.insert(@table_name, {key, new_timestamps})
          {:allow, count + 1}
        else
          # Update with filtered timestamps but deny
          :ets.insert(@table_name, {key, valid_timestamps})
          {:deny, limit}
        end

      [] ->
        # First request for this key
        :ets.insert(@table_name, {key, [now]})
        {:allow, 1}
    end
  end

  @doc """
  Reset the rate limit for a key.
  """
  @spec reset(term()) :: :ok
  def reset(key) do
    ensure_table()
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Get the current count for a key within the window.
  """
  @spec count(term(), pos_integer()) :: non_neg_integer()
  def count(key, interval_ms) do
    ensure_table()
    now = System.monotonic_time(:millisecond)
    window_start = now - interval_ms

    case :ets.lookup(@table_name, key) do
      [{^key, timestamps}] ->
        Enum.count(timestamps, &(&1 > window_start))

      [] ->
        0
    end
  end
end
