defmodule PortfolioIndex.Adapters.RateLimiterTest do
  use PortfolioIndex.SupertesterCase, async: false

  alias PortfolioIndex.Adapters.RateLimiter

  setup do
    # Ensure Foundation's registry is initialized
    _ = Foundation.RateLimit.BackoffWindow.default_registry()
    :ok
  end

  describe "check/1" do
    test "returns :ok when no backoff is active" do
      assert :ok = RateLimiter.check(:test_provider_1)
    end

    test "returns {:backoff, ms} when in backoff window" do
      # Record a failure to trigger backoff
      RateLimiter.record_failure(:test_provider_2, :default, :rate_limited)

      result = RateLimiter.check(:test_provider_2)
      assert {:backoff, ms} = result
      assert is_integer(ms) and ms > 0
    end
  end

  describe "check/2" do
    test "returns :ok for specific operation when no backoff" do
      assert :ok = RateLimiter.check(:test_provider_3, :chat)
    end
  end

  describe "wait/1" do
    test "returns :ok immediately when no backoff" do
      assert :ok = RateLimiter.wait(:test_provider_4)
    end
  end

  describe "wait/2" do
    test "returns :ok for specific operation" do
      assert :ok = RateLimiter.wait(:test_provider_5, :embedding)
    end
  end

  describe "record_success/2" do
    test "returns :ok" do
      assert :ok = RateLimiter.record_success(:test_provider_6, :chat)
    end

    test "clears backoff after success" do
      provider = :test_provider_7
      RateLimiter.record_failure(provider, :default, :rate_limited)

      # Should be in backoff
      assert {:backoff, _} = RateLimiter.check(provider)

      # Record success should clear backoff
      RateLimiter.record_success(provider, :default)

      assert :ok = RateLimiter.check(provider)
    end
  end

  describe "record_failure/3" do
    test "returns :ok" do
      assert :ok = RateLimiter.record_failure(:test_provider_8, :chat, :timeout)
    end

    test "triggers backoff for rate_limited failures" do
      provider = :test_provider_9

      # Initially no backoff
      assert :ok = RateLimiter.check(provider)

      # Record rate limit failure
      RateLimiter.record_failure(provider, :default, :rate_limited)

      # Should now be in backoff
      assert {:backoff, ms} = RateLimiter.check(provider)
      assert ms > 0
    end
  end

  describe "configure/2" do
    test "returns :ok" do
      config = %{
        requests_per_minute: 60,
        max_concurrency: 10
      }

      assert :ok = RateLimiter.configure(:test_provider_10, config)
    end
  end

  describe "status/1" do
    test "returns status map" do
      status = RateLimiter.status(:test_provider_11)

      assert is_map(status)
      assert Map.has_key?(status, :provider)
      assert Map.has_key?(status, :in_backoff)
      assert status.provider == :test_provider_11
    end

    test "shows in_backoff true after failure" do
      provider = :test_provider_12
      RateLimiter.record_failure(provider, :default, :rate_limited)

      status = RateLimiter.status(provider)
      assert status.in_backoff == true
    end
  end

  describe "behaviour implementation" do
    test "implements PortfolioCore.Ports.RateLimiter behaviour" do
      behaviours = RateLimiter.__info__(:attributes)[:behaviour] || []
      assert PortfolioCore.Ports.RateLimiter in behaviours
    end
  end
end
