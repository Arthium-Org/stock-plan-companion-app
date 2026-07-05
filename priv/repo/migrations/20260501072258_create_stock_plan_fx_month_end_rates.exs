defmodule StockPlan.Repo.Migrations.CreateStockPlanFxMonthlyRates do
  use Ecto.Migration

  def change do
    create table(:stock_plan_fx_monthly_rates, primary_key: false) do
      add :id, :string, primary_key: true
      add :rate_date, :date, null: false
      add :year_month, :string, null: false
      add :currency_pair, :string, null: false, default: "USD/INR"
      add :tt_buying_rate_month_end, :string
      add :standard_rate_month_end, :string
      add :standard_rate_month_avg, :string
      add :source, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:stock_plan_fx_monthly_rates, [:year_month, :currency_pair])
  end
end
