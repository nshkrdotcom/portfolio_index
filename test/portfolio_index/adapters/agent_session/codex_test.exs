defmodule PortfolioIndex.Adapters.AgentSession.CodexTest do
  # Not async because we register global names for adapter processes
  use ExUnit.Case, async: false

  alias PortfolioIndex.Adapters.AgentSession.Codex

  describe "behaviour implementation" do
    test "implements PortfolioCore.Ports.AgentSession behaviour" do
      behaviours =
        Codex.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert PortfolioCore.Ports.AgentSession in behaviours
    end
  end

  describe "provider_name/0" do
    test "returns \"codex\"" do
      assert Codex.provider_name() == "codex"
    end
  end

  describe "capabilities/0" do
    test "returns ok tuple with capability list" do
      assert {:ok, capabilities} = Codex.capabilities()
      assert is_list(capabilities)
      assert [_ | _] = capabilities
    end

    test "includes expected capabilities" do
      {:ok, capabilities} = Codex.capabilities()
      names = Enum.map(capabilities, & &1.name)

      assert "streaming" in names
      assert "tool_use" in names
      assert "interrupt" in names
      assert "mcp" in names
      assert "file_operations" in names
      assert "bash" in names
    end

    test "capabilities have required fields" do
      {:ok, capabilities} = Codex.capabilities()

      for cap <- capabilities do
        assert Map.has_key?(cap, :name)
        assert Map.has_key?(cap, :type)
        assert Map.has_key?(cap, :enabled)
      end
    end
  end

  describe "validate_config/1" do
    test "accepts valid config with working_directory" do
      assert :ok = Codex.validate_config(%{working_directory: "/tmp"})
    end

    test "rejects non-map config" do
      assert {:error, _} = Codex.validate_config("invalid")
    end

    test "rejects config without working_directory" do
      assert {:error, _} = Codex.validate_config(%{})
    end

    test "rejects config with non-string working_directory" do
      assert {:error, _} = Codex.validate_config(%{working_directory: 123})
    end

    test "rejects config with empty working_directory" do
      assert {:error, _} = Codex.validate_config(%{working_directory: ""})
    end
  end

  describe "start_session/2" do
    setup do
      {:ok, store} = AgentSessionManager.Adapters.InMemorySessionStore.start_link([])

      stop_if_alive(AgentSessionManager.Adapters.CodexAdapter)

      {:ok, adapter} =
        AgentSessionManager.Adapters.CodexAdapter.start_link(
          name: AgentSessionManager.Adapters.CodexAdapter,
          working_directory: "/tmp",
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
               Codex.start_session("test-agent", store: store, adapter: adapter)

      assert is_binary(session_id)
    end

    test "returns error when store is not configured" do
      original = Application.get_env(:portfolio_index, :agent_session)
      Application.put_env(:portfolio_index, :agent_session, [])

      assert {:error, {:not_configured, :store}} = Codex.start_session("test-agent")

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
      {:ok, mock_sdk} = start_mock_codex_sdk()

      stop_if_alive(AgentSessionManager.Adapters.CodexAdapter)

      {:ok, adapter} =
        AgentSessionManager.Adapters.CodexAdapter.start_link(
          name: AgentSessionManager.Adapters.CodexAdapter,
          working_directory: "/tmp",
          sdk_module: PortfolioIndex.Adapters.AgentSession.CodexTest.MockCodexSDK,
          sdk_pid: mock_sdk
        )

      {:ok, session_id} =
        Codex.start_session("test-agent", store: store, adapter: adapter)

      on_exit(fn ->
        stop_if_alive(adapter)
        stop_if_alive(store)
        stop_if_alive(mock_sdk)
      end)

      %{store: store, adapter: adapter, session_id: session_id, mock_sdk: mock_sdk}
    end

    test "executes and returns run_result", ctx do
      assert {:ok, result} =
               Codex.execute(
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
  end

  describe "end_session/1" do
    setup do
      {:ok, store} = AgentSessionManager.Adapters.InMemorySessionStore.start_link([])

      stop_if_alive(AgentSessionManager.Adapters.CodexAdapter)

      {:ok, adapter} =
        AgentSessionManager.Adapters.CodexAdapter.start_link(
          name: AgentSessionManager.Adapters.CodexAdapter,
          working_directory: "/tmp",
          sdk_module: nil,
          sdk_pid: nil
        )

      {:ok, session_id} =
        Codex.start_session("test-agent", store: store, adapter: adapter)

      original = Application.get_env(:portfolio_index, :agent_session)

      Application.put_env(:portfolio_index, :agent_session,
        store: store,
        codex: adapter
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
      assert :ok = Codex.end_session(session_id)
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

  defp start_mock_codex_sdk do
    PortfolioIndex.Adapters.AgentSession.CodexTest.MockCodexSDK.start_link()
  end

  defmodule MockCodexSDK do
    @moduledoc false
    use GenServer

    # Alias the real Codex SDK events to avoid collision with
    # PortfolioIndex.Adapters.AgentSession.Codex
    alias Elixir.Codex.Events, as: CodexEvents

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def run_streamed(pid, _thread, _input, _opts) do
      GenServer.call(pid, :run_streamed)
    end

    def raw_events(result) do
      result
    end

    def cancel(_pid), do: :ok

    @impl true
    def init(_opts), do: {:ok, %{}}

    @impl true
    def handle_call(:run_streamed, _from, state) do
      events = [
        %CodexEvents.ThreadStarted{
          thread_id: "mock-thread",
          metadata: %{}
        },
        %CodexEvents.TurnStarted{
          thread_id: "mock-thread",
          turn_id: "turn-1"
        },
        %CodexEvents.TurnCompleted{
          thread_id: "mock-thread",
          turn_id: "turn-1",
          status: "completed",
          usage: %{input_tokens: 15, output_tokens: 25}
        }
      ]

      {:reply, {:ok, events}, state}
    end
  end
end
