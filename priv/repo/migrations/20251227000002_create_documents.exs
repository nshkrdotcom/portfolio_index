defmodule PortfolioIndex.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:store_id, :string, null: false)
      add(:content, :text, null: false)
      add(:content_hash, :string, null: false)
      add(:metadata, :map, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:documents, [:store_id]))
    create(index(:documents, [:content_hash]))
    create(index(:documents, [:store_id, :id], unique: true))
  end
end
