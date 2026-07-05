defmodule StockPlan.Repo.Migrations.CreateStockPlanHoldings do
  use Ecto.Migration

  def change do
    create table(:stock_plan_holdings, primary_key: false) do
      add :id, :string, primary_key: true
      add :ingestion_id, :string, null: false
      add :account_id, :string, null: false
      add :symbol, :string
      add :plan_type, :string, null: false
      add :grant_number, :string
      add :grant_date, :date
      add :granted_qty, :string
      add :vest_date, :date
      add :vest_period, :integer
      add :vested_qty, :string
      add :released_qty, :string
      add :sellable_qty, :string
      add :blocked_qty, :string
      add :cost_basis, :string
      add :purchase_price, :string
      add :status, :string, null: false
      add :vest_fx_rate, :string
      add :metadata_json, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:stock_plan_holdings, [:account_id, :ingestion_id])
  end
end
