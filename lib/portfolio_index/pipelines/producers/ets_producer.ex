defmodule PortfolioIndex.Pipelines.Producers.ETSProducer do
  @moduledoc """
  Broadway producer that reads from an ETS table.

  Used for internal queuing between pipeline stages.

  ## Configuration

      producer: [
        module: {ETSProducer, [table: :my_queue]}
      ]
  """

  use GenStage
  require Logger

  alias Broadway.{Message, NoopAcknowledger}

  @poll_interval 100

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    table = Keyword.fetch!(opts, :table)

    state = %{
      table: table,
      demand: 0
    }

    # Schedule polling
    schedule_poll()

    {:producer, state}
  end

  @impl true
  def handle_demand(demand, state) do
    {events, remaining_demand} = fetch_events(state.table, state.demand + demand)
    {:noreply, to_messages(events), %{state | demand: remaining_demand}}
  end

  @impl true
  def handle_info(:poll, state) do
    {events, remaining_demand} = fetch_events(state.table, state.demand)
    schedule_poll()
    {:noreply, to_messages(events), %{state | demand: remaining_demand}}
  end

  # Private functions

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp fetch_events(table, demand) when demand > 0 do
    # Get up to `demand` items from the ETS table
    items =
      :ets.tab2list(table)
      |> Enum.take(demand)

    # Delete fetched items
    Enum.each(items, fn {key, _value} ->
      :ets.delete(table, key)
    end)

    events = Enum.map(items, fn {_key, value} -> value end)
    remaining = demand - length(events)

    {events, remaining}
  end

  defp fetch_events(_table, demand), do: {[], demand}

  defp to_messages(events) do
    acknowledger = NoopAcknowledger.init()

    Enum.map(events, fn event ->
      %Message{data: event, acknowledger: acknowledger}
    end)
  end
end
