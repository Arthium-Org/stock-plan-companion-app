defmodule StockPlan.Repo.Migrations.CreateStockPlanTranches do
  use Ecto.Migration

  def change do
    create table(:stock_plan_tranches, primary_key: false) do
      add :id, :string, primary_key: true

      add :origin_id,
          references(:stock_plan_origins, column: :id, type: :string, on_delete: :restrict),
          null: false

      add :ingestion_id,
          references(:stock_plan_ingestions,
            column: :ingestion_id,
            type: :string,
            on_delete: :restrict
          ),
          null: false

      add :vest_date, :date, null: false
      add :vest_quantity, :string
      add :vest_fmv, :string
      add :vest_fx_rate, :string
      add :tax_withheld_qty, :string
      add :net_quantity, :string
      add :status, :string, null: false
      add :metadata_json, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stock_plan_tranches, [:origin_id])
    create index(:stock_plan_tranches, [:ingestion_id])
    create index(:stock_plan_tranches, [:vest_date])
  end
end
