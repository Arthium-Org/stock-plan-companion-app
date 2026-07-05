defmodule StockPlan.Repo.Migrations.AddOrderNumberToSaleAllocations do
  use Ecto.Migration

  def change do
    alter table(:stock_plan_sale_allocations) do
      add :order_number, :string
    end
  end
end
