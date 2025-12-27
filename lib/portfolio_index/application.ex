defmodule PortfolioIndex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      PortfolioIndex.Repo,

      # Telemetry
      PortfolioIndex.Telemetry,

      # Neo4j connection pool (boltx)
      {Boltx, Application.get_env(:boltx, Boltx, [])},

      # Pipeline supervisor (starts Broadway pipelines on demand)
      {DynamicSupervisor, strategy: :one_for_one, name: PortfolioIndex.PipelineSupervisor}
    ]

    opts = [strategy: :one_for_one, name: PortfolioIndex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
