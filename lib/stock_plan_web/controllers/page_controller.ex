defmodule StockPlanWeb.PageController do
  use StockPlanWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
