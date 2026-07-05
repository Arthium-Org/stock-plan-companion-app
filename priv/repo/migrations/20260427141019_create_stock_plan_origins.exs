defmodule StockPlan.Repo.Migrations.CreateStockPlanOrigins do
  use Ecto.Migration

  def change do
    create table(:stock_plan_origins, primary_key: false) do
      add :id, :string, primary_key: true

      add :ingestion_id,
          references(:stock_plan_ingestions,
            column: :ingestion_id,
            type: :string,
            on_delete: :restrict
          ),
          null: false

      add :account_id, :string, null: false
      add :symbol, :string, null: false
      add :plan_type, :string, null: false
      add :grant_number, :string
      add :origin_date, :date, null: false
      add :total_quantity, :string
      add :origin_fmv, :string
      add :origin_fx_rate, :string
      add :currency, :string, null: false, default: "USD"
      add :status, :string
      add :metadata_json, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stock_plan_origins, [:ingestion_id])
    create index(:stock_plan_origins, [:account_id])
    create index(:stock_plan_origins, [:plan_type])
    create unique_index(:stock_plan_origins, [:ingestion_id, :grant_number])
  end
end
