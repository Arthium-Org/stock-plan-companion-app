defmodule StockPlan.Repo.Migrations.CreateStockPlanSales do
  use Ecto.Migration

  def change do
    create table(:stock_plan_sales, primary_key: false) do
      add :id, :string, primary_key: true

      add :ingestion_id,
          references(:stock_plan_ingestions,
            column: :ingestion_id,
            type: :string,
            on_delete: :restrict
          ),
          null: false

      add :origin_id,
          references(:stock_plan_origins, column: :id, type: :string, on_delete: :restrict),
          null: false

      add :account_id, :string, null: false
      add :symbol, :string, null: false
      add :sale_date, :date, null: false
      add :total_quantity, :string, null: false
      add :sale_price, :string
      add :sale_fx_rate, :string
      add :proceeds, :string
      add :metadata_json, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stock_plan_sales, [:ingestion_id])
    create index(:stock_plan_sales, [:origin_id])
    create index(:stock_plan_sales, [:account_id])
    create index(:stock_plan_sales, [:sale_date])
  end
end
