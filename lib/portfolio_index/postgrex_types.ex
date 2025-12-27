Postgrex.Types.define(
  PortfolioIndex.PostgrexTypes,
  Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(),
  []
)
