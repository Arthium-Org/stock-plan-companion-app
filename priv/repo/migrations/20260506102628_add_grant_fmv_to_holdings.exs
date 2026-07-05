defmodule StockPlan.Repo.Migrations.AddGrantFmvToHoldings do
  use Ecto.Migration

  def change do
    alter table(:stock_plan_holdings) do
      add :grant_fmv, :string
    end
  end
end
