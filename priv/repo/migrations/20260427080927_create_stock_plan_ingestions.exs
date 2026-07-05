defmodule StockPlan.Repo.Migrations.CreateStockPlanIngestions do
  use Ecto.Migration

  def change do
    create table(:stock_plan_ingestions, primary_key: false) do
      add :ingestion_id, :string, primary_key: true
      add :account_id, :string, null: false
      add :broker, :string, null: false
      add :source_type, :string, null: false
      add :file_name, :string, null: false
      add :file_hash, :string, null: false
      add :status, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stock_plan_ingestions, [:account_id])
    create index(:stock_plan_ingestions, [:status])
  end
end
