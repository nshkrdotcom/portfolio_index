defmodule PortfolioIndex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      []
      |> maybe_add_child(:start_repo, PortfolioIndex.Repo)
      |> maybe_add_child(:start_telemetry, PortfolioIndex.Telemetry)
      |> maybe_add_child(:start_boltx, {Boltx, Application.get_env(:boltx, Boltx, [])})
      |> Kernel.++([
        {DynamicSupervisor, strategy: :one_for_one, name: PortfolioIndex.PipelineSupervisor}
      ])

    opts = [strategy: :one_for_one, name: PortfolioIndex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_child(children, config_key, child) do
    if Application.get_env(:portfolio_index, config_key, true) do
      children ++ [child]
    else
      children
    end
  end
end
