defmodule StockPlan.Repo.Migrations.AddBhSnapshotJsonToIngestions do
  use Ecto.Migration

  def change do
    alter table(:stock_plan_ingestions) do
      add :bh_snapshot_json, :text, null: true
    end
  end
end
