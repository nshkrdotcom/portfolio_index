defmodule PortfolioIndex.Adapters.AgentSession.ConfigTest do
  use ExUnit.Case, async: true

  alias PortfolioIndex.Adapters.AgentSession.Config

  describe "resolve_store/1" do
    test "returns store from opts when provided" do
      {:ok, store} = AgentSessionManager.Adapters.InMemorySessionStore.start_link([])

      assert Config.resolve_store(store: store) == store
      GenServer.stop(store)
    end

    test "returns error when not configured and no opts" do
      # Clear any existing config for this test
      original = Application.get_env(:portfolio_index, :agent_session)
      Application.put_env(:portfolio_index, :agent_session, [])

      assert {:error, {:not_configured, :store}} = Config.resolve_store([])

      # Restore original
      if original do
        Application.put_env(:portfolio_index, :agent_session, original)
      else
        Application.delete_env(:portfolio_index, :agent_session)
      end
    end

    test "resolves store from application config tuple" do
      original = Application.get_env(:portfolio_index, :agent_session)

      Application.put_env(:portfolio_index, :agent_session,
        store: {AgentSessionManager.Adapters.InMemorySessionStore, []}
      )

      store = Config.resolve_store([])
      assert is_pid(store)
      GenServer.stop(store)

      # Restore original
      if original do
        Application.put_env(:portfolio_index, :agent_session, original)
      else
        Application.delete_env(:portfolio_index, :agent_session)
      end
    end

    test "resolves store from application config pid" do
      original = Application.get_env(:portfolio_index, :agent_session)
      {:ok, store} = AgentSessionManager.Adapters.InMemorySessionStore.start_link([])

      Application.put_env(:portfolio_index, :agent_session, store: store)

      assert Config.resolve_store([]) == store
      GenServer.stop(store)

      if original do
        Application.put_env(:portfolio_index, :agent_session, original)
      else
        Application.delete_env(:portfolio_index, :agent_session)
      end
    end
  end

  describe "resolve_adapter/2" do
    test "returns adapter from opts when provided" do
      {:ok, adapter} =
        AgentSessionManager.Adapters.ClaudeAdapter.start_link(
          sdk_module: nil,
          sdk_pid: nil
        )

      assert Config.resolve_adapter(:claude, adapter: adapter) == adapter
      GenServer.stop(adapter)
    end

    test "returns error when not configured and no opts" do
      original = Application.get_env(:portfolio_index, :agent_session)
      Application.put_env(:portfolio_index, :agent_session, [])

      assert {:error, {:not_configured, :claude}} = Config.resolve_adapter(:claude, [])

      if original do
        Application.put_env(:portfolio_index, :agent_session, original)
      else
        Application.delete_env(:portfolio_index, :agent_session)
      end
    end
  end
end
