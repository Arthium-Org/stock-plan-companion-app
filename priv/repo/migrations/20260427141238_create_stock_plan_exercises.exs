defmodule StockPlan.Repo.Migrations.CreateStockPlanExercises do
  use Ecto.Migration

  def change do
    create table(:stock_plan_exercises, primary_key: false) do
      add :id, :string, primary_key: true

      add :tranche_id,
          references(:stock_plan_tranches, column: :id, type: :string, on_delete: :restrict),
          null: false

      add :ingestion_id,
          references(:stock_plan_ingestions,
            column: :ingestion_id,
            type: :string,
            on_delete: :restrict
          ),
          null: false

      add :exercise_date, :date, null: false
      add :exercise_quantity, :string, null: false
      add :exercise_fmv, :string
      add :exercise_fx_rate, :string
      add :exercise_price, :string, null: false
      add :tax_withheld_qty, :string
      add :net_quantity, :string
      add :metadata_json, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stock_plan_exercises, [:tranche_id])
    create index(:stock_plan_exercises, [:ingestion_id])
  end
end
