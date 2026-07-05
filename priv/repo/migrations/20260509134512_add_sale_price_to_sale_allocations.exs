defmodule StockPlan.Repo.Migrations.AddSalePriceToSaleAllocations do
  use Ecto.Migration

  def change do
    alter table(:stock_plan_sale_allocations) do
      # SafeDecimal — proceeds per share from G&L
      add :sale_price, :string
    end
  end
end
