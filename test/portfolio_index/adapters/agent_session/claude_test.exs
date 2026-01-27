defmodule PortfolioIndex.Adapters.AgentSession.ClaudeTest do
  # Not async because we register global names for adapter processes
  use ExUnit.Case, async: false

  alias PortfolioIndex.Adapters.AgentSession.Claude

  describe "behaviour implementation" do
    test "implements PortfolioCore.Ports.AgentSession behaviour" do
      behaviours =
        Claude.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert PortfolioCore.Ports.AgentSession in behaviours
    end
  end

  describe "provider_name/0" do
    test "returns \"claude\"" do
      assert Claude.provider_name() == "claude"
    end
  end

  describe "capabilities/0" do
    test "returns ok tuple with capability list" do
      assert {:ok, capabilities} = Claude.capabilities()
      assert is_list(capabilities)
      assert capabilities != []
    end

    test "includes expected capabilities" do
      {:ok, capabilities} = Claude.capabilities()
      names = Enum.map(capabilities, & &1.name)

      assert "streaming" in names
      assert "tool_use" in names
      assert "vision" in names
      assert "system_prompts" in names
      assert "interrupt" in names
    end

    test "capabilities have required fields" do
      {:ok, capabilities} = Claude.capabilities()

      for cap <- capabilities do
        assert Map.has_key?(cap, :name)
        assert Map.has_key?(cap, :type)
        assert Map.has_key?(cap, :enabled)
      end
    end
  end

  describe "validate_config/1" do
    test "accepts valid config with no special requirements" do
      assert :ok = Claude.validate_config(%{})
    end

    test "accepts config with model" do
      assert :ok = Claude.validate_config(%{model: "claude-sonnet-4-20250514"})
    end

    test "rejects non-map config" do
      assert {:error, _} = Claude.validate_config("invalid")
    end

    test "rejects config with invalid model type" do
      assert {:error, _} = Claude.validate_config(%{model: 123})
    end
  end

  describe "start_session/2" do
    setup do
      {:ok, store} = AgentSessionManager.Adapters.InMemorySessionStore.start_link([])

      # Stop any existing named process first
      stop_if_alive(AgentSessionManager.Adapters.ClaudeAdapter)

      {:ok, adapter} =
        AgentSessionManager.Adapters.ClaudeAdapter.start_link(
          name: AgentSessionManager.Adapters.ClaudeAdapter,
          sdk_module: nil,
          sdk_pid: nil
        )

      on_exit(fn ->
        stop_if_alive(adapter)
        stop_if_alive(store)
      end)

      %{store: store, adapter: adapter}
    end

    test "starts a session and returns session_id", %{store: store, adapter: adapter} do
      assert {:ok, session_id} =
               Claude.start_session("test-agent", store: store, adapter: adapter)

      assert is_binary(session_id)
    end

    test "returns error when store is not configured" do
      original = Application.get_env(:portfolio_index, :agent_session)
      Application.put_env(:portfolio_index, :agent_session, [])

      assert {:error, {:not_configured, :store}} = Claude.start_session("test-agent")

      if original do
        Application.put_env(:portfolio_index, :agent_session, original)
      else
        Application.delete_env(:portfolio_index, :agent_session)
      end
    end
  end

  describe "execute/3" do
    setup do
      {:ok, store} = AgentSessionManager.Adapters.InMemorySessionStore.start_link([])

      # Create a mock SDK module for testing
      {:ok, mock_sdk} = start_mock_claude_sdk()

      # Stop any existing named process first
      stop_if_alive(AgentSessionManager.Adapters.ClaudeAdapter)

      {:ok, adapter} =
        AgentSessionManager.Adapters.ClaudeAdapter.start_link(
          name: AgentSessionManager.Adapters.ClaudeAdapter,
          sdk_module: PortfolioIndex.Adapters.AgentSession.ClaudeTest.MockClaudeQuerySDK,
          sdk_pid: mock_sdk
        )

      {:ok, session_id} =
        Claude.start_session("test-agent", store: store, adapter: adapter)

      on_exit(fn ->
        stop_if_alive(adapter)
        stop_if_alive(store)
        stop_if_alive(mock_sdk)
      end)

      %{store: store, adapter: adapter, session_id: session_id, mock_sdk: mock_sdk}
    end

    test "executes and returns run_result", ctx do
      assert {:ok, result} =
               Claude.execute(
                 ctx.session_id,
                 %{messages: [%{role: "user", content: "Hello"}]},
                 store: ctx.store,
                 adapter: ctx.adapter
               )

      assert is_map(result)
      assert Map.has_key?(result, :output)
      assert Map.has_key?(result, :token_usage)
      assert Map.has_key?(result, :turn_count)
      assert Map.has_key?(result, :events)
    end

    test "handles string input", ctx do
      assert {:ok, result} =
               Claude.execute(
                 ctx.session_id,
                 "Hello world",
                 store: ctx.store,
                 adapter: ctx.adapter
               )

      assert is_map(result)
    end
  end

  describe "end_session/1" do
    setup do
      {:ok, store} = AgentSessionManager.Adapters.InMemorySessionStore.start_link([])

      stop_if_alive(AgentSessionManager.Adapters.ClaudeAdapter)

      {:ok, adapter} =
        AgentSessionManager.Adapters.ClaudeAdapter.start_link(
          name: AgentSessionManager.Adapters.ClaudeAdapter,
          sdk_module: nil,
          sdk_pid: nil
        )

      {:ok, session_id} =
        Claude.start_session("test-agent", store: store, adapter: adapter)

      original = Application.get_env(:portfolio_index, :agent_session)

      Application.put_env(:portfolio_index, :agent_session,
        store: store,
        claude: adapter
      )

      on_exit(fn ->
        if original do
          Application.put_env(:portfolio_index, :agent_session, original)
        else
          Application.delete_env(:portfolio_index, :agent_session)
        end

        stop_if_alive(adapter)
        stop_if_alive(store)
      end)

      %{store: store, adapter: adapter, session_id: session_id}
    end

    test "ends a session successfully", %{session_id: session_id} do
      assert :ok = Claude.end_session(session_id)
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp stop_if_alive(pid_or_name) when is_pid(pid_or_name) do
    if Process.alive?(pid_or_name), do: GenServer.stop(pid_or_name, :normal, 1000)
  catch
    :exit, _ -> :ok
  end

  defp stop_if_alive(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> stop_if_alive(pid)
    end
  end

  defp stop_if_alive(_), do: :ok

  # ===========================================================================
  # Mock SDK for testing
  # ===========================================================================

  defp start_mock_claude_sdk do
    PortfolioIndex.Adapters.AgentSession.ClaudeTest.MockClaudeQuerySDK.start_link()
  end

  defmodule MockClaudeQuerySDK do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def query(pid, _input, _opts) do
      GenServer.call(pid, :query)
    end

    @impl true
    def init(_opts), do: {:ok, %{}}

    @impl true
    def handle_call(:query, _from, state) do
      # Return a list of mock ClaudeAgentSDK.Message structs
      messages = [
        %ClaudeAgentSDK.Message{
          type: :system,
          subtype: :init,
          data: %{session_id: "mock-session", model: "claude-sonnet-4-20250514", tools: []},
          raw: nil
        },
        %ClaudeAgentSDK.Message{
          type: :assistant,
          subtype: nil,
          data: %{
            message: %{
              "content" => [%{"type" => "text", "text" => "Hello! How can I help?"}]
            }
          },
          raw: nil
        },
        %ClaudeAgentSDK.Message{
          type: :result,
          subtype: :success,
          data: %{
            usage: %{input_tokens: 10, output_tokens: 20},
            num_turns: 1,
            total_cost_usd: 0.001
          },
          raw: %{"usage" => %{"input_tokens" => 10, "output_tokens" => 20}}
        }
      ]

      {:reply, messages, state}
    end
  end
end
