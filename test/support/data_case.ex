defmodule PortfolioIndex.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.
  """

  alias Ecto.Adapters.SQL.Sandbox

  use ExUnit.CaseTemplate

  using do
    quote do
      alias PortfolioIndex.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import PortfolioIndex.DataCase
    end
  end

  setup tags do
    PortfolioIndex.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(PortfolioIndex.Repo, shared: not tags[:async])

    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
