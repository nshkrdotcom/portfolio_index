defmodule PortfolioIndex.Repo.Migrations.CreateVectorIndexes do
  use Ecto.Migration

  def change do
    # Registry table to track vector indexes and their configurations
    create table(:vector_index_registry, primary_key: false) do
      add(:index_id, :string, primary_key: true)
      add(:dimensions, :integer, null: false)
      add(:metric, :string, null: false, default: "cosine")
      add(:index_type, :string, null: false, default: "ivfflat")
      add(:options, :map, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    # Note: Actual vector tables are created dynamically per index_id
    # using raw SQL in the Pgvector adapter. This is because:
    # 1. Each index may have different dimensions
    # 2. We want to support multiple isolated indexes
    # 3. pgvector syntax requires specific dimension size in column definition
  end
end
