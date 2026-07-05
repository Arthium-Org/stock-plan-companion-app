# Design: M14 — Tax Centre (Phase 1)

## Architecture

```
Tax Centre Page (/tax)
  ├── Schedule FA Tab (calendar year)
  │     ├── Year selector
  │     ├── Preview table
  │     └── Download CSV/XLSX
  │
  └── Capital Gains Tab (financial year)
        ├── FY selector
        ├── Summary cards: STCG, LTCG, Net
        └── Detail table: per sale-lot
```

### Data Sources

```
BH Silver (origins + tranches + sales + sale_allocations)
  + FX rates (vest_fx_rate, sale_fx_rate)
  + Stock prices (vest_day_close, historical prices for peak/closing)
  → Tax computations (computed at query time, not stored)
```

Tax Centre reads from BH Silver only. No Holdings dependency.

---

## Feature 1: Schedule FA

### Schedule FA Context Module

```elixir
defmodule StockPlan.Tax.ScheduleFA do
  @doc """
  Build Schedule FA data for a calendar year.
  Returns list of rows, one per lot held during the year.
  """
  def build(account_id, calendar_year) do
    # 1. Find all tranches vested on or before Dec 31 of the year
    # 2. For each tranche: compute quantity held during the year
    #    held_qty = net_quantity - sum(sale_allocations where sale_date <= Dec 31)
    #    If sold entirely BEFORE Jan 1 of CY: skip (not held at any point during CY)
    #    If sold DURING CY: include row, closing_value = 0, sale_proceeds = proceeds from sale
    #    If partially sold during CY: include row, closing = remaining qty × Dec 31 price
    # 3. For each held lot:
    #    - initial_value_inr = cost_basis × qty × vest_fx_rate
    #    - peak_value_inr = peak_price × qty × peak_fx_rate
    #    - closing_value_inr = dec31_price × qty × dec31_fx_rate
    # 4. Return rows
  end
end
```

### Schedule FA Row

```elixir
%{
  plan_type: "RSU" | "ESPP",
  grant_number: String.t(),
  country: "United States",
  nature: "Equity Shares",
  company: "Adobe Inc.",
  date_acquired: Date.t(),           # vest_date (RSU) or purchase_date (ESPP)
  initial_value_usd: Decimal.t(),    # cost_basis × qty
  initial_value_inr: Decimal.t(),    # cost_basis × qty × vest_fx_rate
  peak_value_usd: Decimal.t(),       # peak_price × qty
  peak_value_inr: Decimal.t(),       # peak_price × qty × peak_fx_rate
  closing_value_usd: Decimal.t(),    # dec31_price × qty
  closing_value_inr: Decimal.t(),    # dec31_price × qty × dec31_fx_rate
  quantity_held: Decimal.t(),        # shares held as of Dec 31
  income_from_asset: Decimal.t(),    # dividends etc. (nil for now)
  total_investment_usd: Decimal.t(), # initial cost
  total_investment_inr: Decimal.t()
}
```

### Peak Value — Interval-Based Calculation

Must account for quantity changes during CY (partial sales):

```elixir
def compute_peak(lot, price_series, sales_in_cy) do
  # Build timeline: [{date, qty_held_from_this_date}, ...]
  # Intervals: [CY start or acquisition] → [each sale date] → [Dec 31]
  
  intervals = build_intervals(lot, sales_in_cy, cy_start, cy_end)
  
  # For each interval: peak = max(price in interval) × qty × FX
  Enum.map(intervals, fn {from, to, qty} ->
    peak_price = max_price_in_range(price_series, from, to)
    peak_date = date_of_max_price(price_series, from, to)
    peak_fx = FX.get_rate(peak_date)  # Rule 115: previous month end
    Decimal.mult(qty, Decimal.mult(peak_price, peak_fx))
  end)
  |> Enum.max()
end
```

Fetch price series **once per symbol** (not per row):
```elixir
price_series = StockPrice.get_close_range(symbol, jan1, dec31)
# Reuse across all lots for this symbol
```

### Peak FX Rate
Per Rule 115: `FX.get_rate(peak_date)` — returns SBI TT Buying Rate on last day of month preceding the peak month. `peak_date` is always a trading day (derived from price_series).

### FX Rate Semantics (clarification)

Each Schedule FA metric uses the FX rate appropriate to its date:

| Metric | FX Rate Used | Reason |
|---|---|---|
| Initial value | vest_fx_rate (acquisition date FX) | Value at time of acquisition |
| Peak value | FX for peak price month | Value at peak moment |
| Closing value | FX for Dec 31 (= Nov 30 rate) | Value at year end |

These are NOT FX-normalized across time. Each represents the INR value at that specific point. This is by design — Schedule FA asks for actual values at each point, not inflation-adjusted comparisons.

### Dec 31 Closing Values

- Stock price: `StockPrice.get_close("ADBE", ~D[YYYY-12-31])` (or next trading day)
- FX rate: `FX.get_rate(~D[YYYY-12-31])` — returns Nov 30 rate per Rule 115 (previous month end)

### CSV Download

Generate from the same data as the preview table. Plain CSV, no external library:

```elixir
defp generate_csv(rows) do
  headers = [
    "Country Name", "Country Code", "Name of entity", "Address of entity",
    "ZIP Code", "Nature of entity", "Date of acquiring interest",
    "Initial value of investment", "Peak value of investment",
    "Closing Balance", "Total gross amount paid/credited",
    "Total gross proceeds from sale", "Broker Name"
  ]

  lines = [Enum.join(headers, ",")] ++ Enum.map(rows, &row_to_csv/1)
  Enum.join(lines, "\n")
end

defp csv_field(value) when is_binary(value) do
  # Replace commas with semicolons in text fields (address etc.)
  cleaned = String.replace(value, ",", ";")
  # Quote if contains special chars
  if String.contains?(cleaned, [";", "\"", "\n"]) do
    "\"#{String.replace(cleaned, "\"", "\"\"")}\""
  else
    cleaned
  end
end

defp csv_field(value), do: to_string(value)
```

Serve via LiveView `push_event` + JS download, or a dedicated controller endpoint.
Filename: `Schedule_FA_CY{year}.csv`

---

## Feature 2: Capital Gains

### Capital Gains Context Module

```elixir
defmodule StockPlan.Tax.CapitalGains do
  @doc """
  Compute capital gains for an Indian Financial Year (Apr-Mar).
  Returns list of gain/loss rows, one per sale-lot allocation.
  """
  def build(account_id, fy_start_year) do
    # FY 2024-25 → fy_start_year = 2024
    # Period: 2024-04-01 to 2025-03-31
    fy_start = Date.new!(fy_start_year, 4, 1)
    fy_end = Date.new!(fy_start_year + 1, 3, 31)

    # 1. Find all sales in the FY period
    # 2. For each sale: load sale_allocations + linked tranches
    # 3. Per allocation:
    #    - holding_period = sale_date - vest_date (days)
    #    - type = if holding_period > 730 (24 months), :LTCG, else :STCG
    #    - cost_basis_usd = (vest_fmv or vest_day_close) × qty
    #    - proceeds_usd = sale_price × qty
    #    - gain_usd = proceeds_usd - cost_basis_usd
    #    - cost_basis_inr = cost_basis_usd_per_share × qty × vest_fx_rate
    #    - proceeds_inr = sale_price × qty × sale_fx_rate
    #    - gain_inr = proceeds_inr - cost_basis_inr
    # 4. Sales without allocations: include with type = :unknown
  end
end
```

### Capital Gains Row

```elixir
%{
  sale_date: Date.t(),
  plan_type: "RSU" | "ESPP",
  grant_number: String.t(),
  vest_date: Date.t(),               # acquisition date
  quantity: Decimal.t(),             # shares sold from this lot
  sale_price: Decimal.t(),          # per share
  cost_basis_per_share: Decimal.t(), # RSU: vest_fmv. ESPP: purchase_date_fmv (NOT discounted price)
  cost_basis_source: atom(),         # :actual_fmv | :market_close | :unavailable
  holding_days: integer(),
  gain_type: :STCG | :LTCG | :unknown,
  proceeds_usd: Decimal.t(),
  cost_basis_usd: Decimal.t(),
  gain_loss_usd: Decimal.t(),
  proceeds_inr: Decimal.t(),
  cost_basis_inr: Decimal.t(),
  gain_loss_inr: Decimal.t()
}
```

### Capital Gains Summary

```elixir
%{
  stcg_usd: Decimal.t(),
  stcg_inr: Decimal.t(),
  ltcg_usd: Decimal.t(),
  ltcg_inr: Decimal.t(),
  net_gain_usd: Decimal.t(),     # stcg + ltcg only (excludes unknown)
  net_gain_inr: Decimal.t(),     # stcg + ltcg only (excludes unknown)
  unknown_count: integer()       # sales without lot allocation
}
```

### Unknown Sales (no lot allocation)

Sales without `sale_allocations` (G&L not uploaded or lot not matched):

```elixir
%{
  ...
  gain_type: :unknown,
  cost_basis_per_share: nil,     # cannot determine without lot linkage
  cost_basis_source: :unavailable,
  proceeds_usd: sale.proceeds,   # known from sale record
  cost_basis_usd: nil,
  gain_loss_usd: nil,            # cannot compute
  gain_loss_inr: nil,
  warning: "Lot details unavailable — upload G&L Expanded for this FY"
}
```

**Rule:** Unknown rows are excluded from STCG/LTCG totals. Only `unknown_count` is tracked. UI shows warning banner if `unknown_count > 0`.

### Holding Period Calculation

Use exact 2-year calendar comparison (not day count — avoids leap year issues):

```elixir
defp classify_gain(acquire_date, sale_date) do
  threshold = Date.shift(acquire_date, year: 2)
  if Date.compare(sale_date, threshold) == :gt, do: :LTCG, else: :STCG
end
```

- RSU: acquire_date = vest_date
- ESPP: acquire_date = purchase_date
- ESOP: acquire_date = exercise_date

---

## LiveView: Tax Centre Page

### Route
```elixir
live "/tax", TaxCentreLive
```

### Mount
```elixir
def mount(_params, _session, socket) do
  current_year = Date.utc_today().year
  # Default: current calendar year for FA, current FY for CG
  current_fy = if Date.utc_today().month >= 4, do: current_year, else: current_year - 1

  {:ok,
   socket
   |> assign(:page_title, "Tax Centre")
   |> assign(:active_tab, "schedule_fa")
   |> assign(:fa_year, current_year)
   |> assign(:cg_fy, current_fy)
   |> assign(:fa_data, nil)
   |> assign(:cg_data, nil)
   |> assign(:cg_summary, nil)}
end
```

### Events
- `"switch_tab"` — toggle between Schedule FA and Capital Gains
- `"select_fa_year"` — change calendar year, recompute FA data
- `"select_cg_fy"` — change FY, recompute CG data
- `"download_fa_csv"` — trigger CSV download

### Template Layout

```
┌──────────────────────────────────────────────────────┐
│  Tax Centre                                           │
│                                                       │
│  ┃ Schedule FA ┃  Capital Gains                       │
│                                                       │
│  Calendar Year: [2025 ▼]          [Download CSV]      │
│                                                       │
│  ┌────────────────────────────────────────────────┐   │
│  │ # Grant  Acquired  Qty  Initial  Peak  Closing │   │
│  │ 1 RU..   15-Nov-22  9   ₹2.8L   ₹4.5L  ₹2.3L │   │
│  │ 2 RU..   15-Feb-23  5   ₹1.5L   ₹2.5L  ₹1.3L │   │
│  └────────────────────────────────────────────────┘   │
│                                                       │
│  --- OR (Capital Gains tab) ---                       │
│                                                       │
│  FY: [2024-25 ▼]                                      │
│                                                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │ STCG     │ │ LTCG     │ │ Net      │              │
│  │ ₹1.2L    │ │ ₹3.4L    │ │ ₹4.6L    │              │
│  └──────────┘ └──────────┘ └──────────┘              │
│                                                       │
│  ┌────────────────────────────────────────────────┐   │
│  │ Sale Date Grant Vest Date Qty Price Cost Gain  │   │
│  │ 15-Mar-25 RU..  15-Nov-22  5  $250  $347 STCG │   │
│  └────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

## Files

- `lib/stock_plan/tax/schedule_fa.ex` — Schedule FA context
- `lib/stock_plan/tax/capital_gains.ex` — Capital Gains context
- `lib/stock_plan_web/live/tax_centre_live.ex` — LiveView
