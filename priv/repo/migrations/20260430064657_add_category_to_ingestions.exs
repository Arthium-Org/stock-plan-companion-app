defmodule StockPlan.Repo.Migrations.AddCategoryToIngestions do
  use Ecto.Migration

  def change do
    alter table(:stock_plan_ingestions) do
      add :category, :string
    end
  end
end
