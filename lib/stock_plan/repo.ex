defmodule StockPlan.Repo do
  use Ecto.Repo,
    otp_app: :stock_plan,
    adapter: Ecto.Adapters.SQLite3
end
