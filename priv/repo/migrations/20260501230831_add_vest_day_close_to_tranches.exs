defmodule StockPlan.Repo.Migrations.AddVestDayCloseToTranches do
  use Ecto.Migration

  def change do
    alter table(:stock_plan_tranches) do
      add :vest_day_close, :string
    end
  end
end
