defmodule StockPlan.Repo.Migrations.AddHoldingsFieldsToTranches do
  use Ecto.Migration

  def change do
    alter table(:stock_plan_tranches) do
      add :sellable_qty, :string
      add :cost_basis_broker, :string
    end
  end
end
