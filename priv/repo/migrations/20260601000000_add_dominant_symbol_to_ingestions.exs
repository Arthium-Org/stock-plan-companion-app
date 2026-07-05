defmodule StockPlan.Repo.Migrations.AddDominantSymbolToIngestions do
  use Ecto.Migration

  def change do
    alter table(:stock_plan_ingestions) do
      add :dominant_symbol, :string
    end

    create index(:stock_plan_ingestions, [:account_id, :category, :dominant_symbol, :status])
  end
end
