# Design: M17 — REST API

## Architecture

```
Mobile App / External Client
  ↓ JSON
Phoenix API Pipeline (router.ex)
  ↓
API Controllers (thin layer)
  ↓
Existing Context Modules (Portfolio, Tax, SellAdvisor)
  ↓
Existing DB (SQLite)
```

No new business logic. API controllers serialize context module output to JSON.

## Router

```elixir
scope "/api", StockPlanWeb.API do
  pipe_through [:api, :api_auth]

  get "/portfolio", PortfolioController, :index
  get "/portfolio/summary", PortfolioController, :summary

  get "/tax/schedule-fa", TaxController, :schedule_fa
  get "/tax/schedule-fa/download", TaxController, :download_fa
  get "/tax/capital-gains", TaxController, :capital_gains

  post "/sell/advise", SellController, :advise

  get "/price/current", MarketController, :current_price

  post "/upload/benefit-history", UploadController, :benefit_history
  post "/upload/gl-expanded", UploadController, :gl_expanded
  post "/upload/holdings", UploadController, :holdings
end
```

## API Auth Plug

```elixir
defmodule StockPlanWeb.API.AuthPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    api_key = Application.get_env(:stock_plan, :api_key)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token == api_key ->
        conn

      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{status: "error", message: "Invalid API key"})
        |> halt()
    end
  end
end
```

## Controller Pattern

```elixir
defmodule StockPlanWeb.API.PortfolioController do
  use StockPlanWeb, :controller

  @account_id "default"

  def index(conn, _params) do
    hierarchical = Portfolio.build(@account_id)
    flat = Portfolio.flat_holdings(hierarchical)
    current_price = StockPrice.current_price("ADBE")
    current_fx = FX.current_rate()
    summary = Portfolio.compute_summary(flat, current_price)

    json(conn, %{
      status: "ok",
      data: %{
        holdings: serialize_hierarchical(hierarchical),
        summary: serialize_summary(summary),
        current_price: current_price,
        current_fx: to_string(current_fx)
      }
    })
  end
end
```

## Serialization

Decimals → strings (avoid float precision loss):

```elixir
defp serialize_decimal(nil), do: nil
defp serialize_decimal(%Decimal{} = d), do: Decimal.to_string(d)
```

## CORS

```elixir
# In endpoint.ex or a plug
plug Corsica,
  origins: ["http://localhost:3000", "capacitor://localhost"],
  allow_headers: ["authorization", "content-type"]
```

## File Layout

```
lib/stock_plan_web/
  ├── controllers/api/
  │   ├── portfolio_controller.ex
  │   ├── tax_controller.ex
  │   ├── sell_controller.ex
  │   ├── market_controller.ex
  │   └── upload_controller.ex
  ├── plugs/
  │   └── api_auth.ex
  └── router.ex  (add api scope)
```
