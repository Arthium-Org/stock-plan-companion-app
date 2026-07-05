defmodule StockPlan.Repo.Migrations.CreateStockPlanBronzeRaw do
  use Ecto.Migration

  def change do
    create table(:stock_plan_bronze_raw, primary_key: false) do
      add :id, :string, primary_key: true

      add :ingestion_id,
          references(:stock_plan_ingestions,
            column: :ingestion_id,
            type: :string,
            on_delete: :restrict
          ),
          null: false

      add :sheet_name, :string, null: false
      add :record_type, :string, null: false
      add :row_index, :integer, null: false
      add :parent_index, :integer
      add :raw_row_json, :string, null: false
      add :row_hash, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stock_plan_bronze_raw, [:ingestion_id])
    create unique_index(:stock_plan_bronze_raw, [:ingestion_id, :row_hash])
  end
end
