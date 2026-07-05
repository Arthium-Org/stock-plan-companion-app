# Design Document: M7b — Stock Price Service

## Overview

M7b fetches stock prices from Yahoo Finance for two purposes: historical close prices stored as `vest_day_close` on tranches (fallback when broker FMV unavailable), and current prices for live portfolio valuation. Uses Yahoo Finance v8 API (free, no auth required).

### Architecture

```
Yahoo Finance API
     |
     ├── Historical: /v8/finance/chart/{symbol}?period1=...&period2=...
     │     → daily adjusted close prices
     │     → stored as vest_day_close on tranches
     │
     └── Current: /v8/finance/chart/{symbol}?range=1d
           → latest price
           → cached in-memory (ETS or Agent)
```

## Components

### 1. StockPrice Service (`lib/stock_plan/stock_price.ex`)

```elixir
defmodule StockPlan.StockPrice do
  @doc "Get adjusted close price for a symbol on a specific date"
  @spec get_close(String.t(), Date.t()) :: String.t() | nil
  def get_close(symbol, date)

  @doc "Get adjusted close prices for a date range (batch)"
  @spec get_close_range(String.t(), Date.t(), Date.t()) :: %{Date.t() => String.t()}
  def get_close_range(symbol, from_date, to_date)

  @doc "Get current/latest price (cached)"
  @spec current_price(String.t()) :: String.t() | nil
  def current_price(symbol)
end
```

### 2. Yahoo Finance Client (`lib/stock_plan/stock_price/yahoo.ex`)

**Historical data:**
```
GET https://query1.finance.yahoo.com/v8/finance/chart/ADBE?period1=1704067200&period2=1735689600&interval=1d
```

Response includes `chart.result[0].indicators.adjclose[0].adjclose` array aligned with `chart.result[0].timestamp` array.

**Current price:**
```
GET https://query1.finance.yahoo.com/v8/finance/chart/ADBE?range=1d&interval=1d
```

Response includes `chart.result[0].meta.regularMarketPrice`.

### 3. Schema Change

Add `vest_day_close` to tranches:

```elixir
# Migration
alter table(:stock_plan_tranches) do
  add :vest_day_close, :string  # SafeDecimal, nullable
end
```

### 4. Silver Builder Phase 4 — Stock Price Enrichment

After Phase 3 (FX rates):

```
Phase 4: Stock Prices
  1. Collect all unique (symbol, vest_date) from VESTED tranches
  2. Batch fetch from Yahoo: get_close_range(symbol, min_date, max_date)
  3. Fill vest_day_close on each tranche
```

### 5. Price Cache (Current Price)

Simple ETS or Agent-based cache:
- Key: symbol
- Value: {price, fetched_at}
- TTL: 15 minutes
- On miss: fetch from Yahoo, store, return

## Display Logic (UI layer, not M7b)

```
vest FMV to display:
  IF vest_fmv (from G&L) → show vest_fmv (labeled "Actual FMV")
  ELIF vest_day_close (from Yahoo) → show vest_day_close (labeled "Close Price")
  ELSE → show "N/A"
```

## Implementation Notes

- Yahoo Finance v8 API is free but may rate-limit. Add 1-second delay between batch calls.
- Historical data: one API call per symbol covers entire date range (efficient).
- `period1`/`period2` are Unix timestamps.
- Weekend/holiday dates: Yahoo returns data only for trading days. For a vest on Saturday, use Friday's close. The batch range includes all trading days — match tranche vest_date to nearest trading day ≤ vest_date.
- HTTP client: use built-in `Finch` (already in Phoenix deps) or `Req`.
- No new hex dependency needed if using Finch.
