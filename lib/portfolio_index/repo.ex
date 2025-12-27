defmodule PortfolioIndex.Repo do
  @moduledoc """
  Ecto Repo for PortfolioIndex PostgreSQL database.

  Used for:
  - Vector storage via pgvector extension
  - Document storage
  - Metadata and configuration
  """

  use Ecto.Repo,
    otp_app: :portfolio_index,
    adapter: Ecto.Adapters.Postgres
end
