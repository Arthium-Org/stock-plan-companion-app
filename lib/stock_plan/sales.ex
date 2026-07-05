defmodule StockPlan.Sales do
  @moduledoc false
  alias StockPlan.Repo
  alias StockPlan.Schema.{Sale, SaleAllocation}

  _ = {Repo, Sale, SaleAllocation}
end
