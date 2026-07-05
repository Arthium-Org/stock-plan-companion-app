# Design Document: M7a — FX Rate Service

## Overview

M7a provides USD/INR FX rates per Indian tax law. Core rule: **use the TT buying rate from the last day of the month BEFORE the transaction month**. Three rate fields stored per month, with fallback priority: TT Buy → RBI month-end → monthly average.

### Schema

```elixir
defmodule StockPlan.Schema.FxMonthlyRate do
  @primary_key {:id, :string, autogenerate: false}
  schema "stock_plan_fx_monthly_rates" do
    field :rate_date, :date                                    # last day of month
    field :year_month, :string                                 # "2024-03"
    field :currency_pair, :string                              # "USD/INR"
    field :tt_buying_rate_month_end, SafeDecimal               # SBI TT Buy (2020+)
    field :standard_rate_month_end, SafeDecimal                # RBI reference (1998+)
    field :standard_rate_month_avg, SafeDecimal                # x-rates.com avg (2016+)
    field :source, :string
    timestamps()
  end
end
```

### FX Service

```elixir
defmodule StockPlan.FX do
  def get_rate(date)           # → Decimal | nil (previous month rule)
  def get_rate_string(date)    # → String | nil
  def current_rate()           # → Decimal | nil (most recent)
  def previous_month_key(date) # → "2024-03"
end
```

**Rate priority:** `pick_best_rate/1` — TT buy → month-end standard → month-avg standard.

### Data Sources

| Field | Source | Coverage |
|---|---|---|
| tt_buying_rate_month_end | SBI (GitHub scraper + taxroutine.com) | 2020–2026 (76 months) |
| standard_rate_month_end | RBI reference rate archive | Aug 1998–2026 (289 months) |
| standard_rate_month_avg | x-rates.com | 2016–2026 (124 months) |

### Silver Builder Phase 3

Fills nil FX fields on Silver records during rebuild:
- `origin.origin_fx_rate` ← `FX.get_rate_string(origin.origin_date)`
- `tranche.vest_fx_rate` ← `FX.get_rate_string(tranche.vest_date)` (VESTED only)
- `sale.sale_fx_rate` ← `FX.get_rate_string(sale.sale_date)`
