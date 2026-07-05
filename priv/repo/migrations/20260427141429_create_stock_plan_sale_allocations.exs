defmodule StockPlan.Repo.Migrations.CreateStockPlanSaleAllocations do
  use Ecto.Migration

  def change do
    create table(:stock_plan_sale_allocations, primary_key: false) do
      add :id, :string, primary_key: true

      add :sale_id,
          references(:stock_plan_sales, column: :id, type: :string, on_delete: :restrict),
          null: false

      add :tranche_id,
          references(:stock_plan_tranches, column: :id, type: :string, on_delete: :restrict),
          null: false

      add :exercise_id,
          references(:stock_plan_exercises, column: :id, type: :string, on_delete: :restrict)

      add :quantity, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stock_plan_sale_allocations, [:sale_id])
    create index(:stock_plan_sale_allocations, [:tranche_id])
    create index(:stock_plan_sale_allocations, [:exercise_id])
  end
end
