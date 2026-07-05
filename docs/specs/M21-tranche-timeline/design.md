# Design: M21 — Tranche Timeline Builder

## Architecture

```
TrancheTimeline.build(account_id)
  │
  ├── Load BH Silver: origins, tranches, sales (origin-level events)
  ├── Load G&L: sale_allocations (tranche-level sells)
  ├── Load Holdings Silver: current sellable_qty per tranche
  │
  ├── Validate: V1 (qty match), V2 (G&L coverage), V3 (no gaps)
  │
  └── For each tranche: build event list → derive held_qty at any date

ScheduleFA.build(account_id, cy)
  │
  ├── TrancheTimeline.build(account_id)
  ├── Validate V2 for requested CY
  └── Query timeline: held_qty at CY start, end, sells during CY
```

## Data Structure

### TrancheTimeline

```elixir
%{
  tranche_id: String,
  origin_id: String,
  grant_number: String,
  plan_type: "RSU" | "ESPP",
  vest_date: Date,
  net_quantity: Decimal,        # shares released (after tax)
  cost_basis: Decimal,          # vest_fmv (RSU) or purchase_fmv (ESPP)
  vest_fx_rate: Decimal,
  
  # Chronological sell events
  # Primary: G&L allocations for both RSU and ESPP (has price)
  # Fallback: BH quantity match for ESPP only (has date, no price)
  sells: [
    %{date: Date, quantity: Decimal, price: Decimal | nil, order_number: String | nil,
      source: :gl | :bh,
      confidence: :verified | :inferred}
      # :verified = from G&L (has price, lot-level)
      # :inferred = from BH quantity match (date only, no price, best-effort)
  ],
  
  # Current state from Holdings (nil if no Holdings uploaded, 0 if confirmed sold)
  holdings_qty: Decimal | nil,  # sellable_qty from Holdings
  
  # Derived
  total_sold: Decimal,          # sum of sells
  held_from_timeline: Decimal   # net_quantity - total_sold (should match holdings_qty)
}
```

### Validation Result

```elixir
%{
  valid: boolean,
  errors: [%{code: atom, message: String}],
  warnings: [%{code: atom, message: String}],
  
  # G&L coverage info
  gl_date_range: {Date, Date} | nil,
  bh_sell_dates: [Date],
  uncovered_sell_dates: [Date]
}
```

## Timeline Builder Module

```elixir
defmodule StockPlan.Tax.TrancheTimeline do
  @doc """
  Build tranche timelines for an account.
  Returns {timelines, validation_result}.
  """
  def build(account_id) do
    # Load all data
    tranches = load_tranches(account_id)       # BH Silver
    allocations = load_allocations(account_id)  # G&L sale_allocations
    holdings = load_holdings(account_id)        # Holdings Silver
    bh_sales = load_bh_sales(account_id)        # BH sales (origin-level)
    
    # Build timelines
    timelines = build_timelines(tranches, allocations, holdings)
    
    # Validate
    validation = validate(timelines, bh_sales, allocations)
    
    {timelines, validation}
  end
  
  @doc """
  Query: what was held during a calendar year?
  Returns list of tranche states for the CY.
  """
  def held_during_cy(timelines, calendar_year) do
    cy_start = Date.new!(calendar_year, 1, 1)
    cy_end = Date.new!(calendar_year, 12, 31)
    
    timelines
    |> Enum.filter(fn t -> Date.compare(t.vest_date, cy_end) != :gt end)
    |> Enum.map(fn t ->
      sold_before_cy = sum_sells_before(t.sells, cy_start)
      sold_during_cy = sum_sells_between(t.sells, cy_start, cy_end)
      held_at_start = Decimal.sub(t.net_quantity, sold_before_cy)
      held_at_end = Decimal.sub(held_at_start, sold_during_cy)
      
      %{
        timeline: t,
        held_at_start: held_at_start,
        held_at_end: held_at_end,
        sold_during_cy: sold_during_cy,
        held_during_cy: Decimal.gt?(held_at_start, Decimal.new(0)) or
                        Decimal.gt?(sold_during_cy, Decimal.new(0))
      }
    end)
    |> Enum.filter(& &1.held_during_cy)
  end
end
```

## Validation Logic

### V1: Holdings vs Timeline Quantity Match

Compare Holdings snapshot against timeline-derived state (NOT BH directly):

```elixir
defp validate_v1(timelines) do
  # Only validate tranches that have Holdings data
  with_holdings = Enum.filter(timelines, & &1.held_from_holdings != nil)
  
  Enum.flat_map(with_holdings, fn t ->
    # held_from_timeline = net_quantity - total_sold (from G&L/BH sell events)
    diff = Decimal.sub(t.held_from_timeline, t.held_from_holdings) |> Decimal.abs()
    
    if Decimal.gt?(diff, Decimal.new(1)) do
      [%{
        code: :qty_mismatch,
        message: "#{t.grant_number} vest #{t.vest_date}: timeline=#{t.held_from_timeline}, holdings=#{t.held_from_holdings}"
      }]
    else
      []
    end
  end)
end
```

### V2: G&L Coverage for CY

```elixir
defp validate_v2_for_cy(bh_sales, allocations, calendar_year) do
  cy_start = Date.new!(calendar_year, 1, 1)
  cy_end = Date.new!(calendar_year, 12, 31)
  
  # BH sell dates in this CY
  sell_dates_in_cy = bh_sales
    |> Enum.filter(fn s ->
      Date.compare(s.sale_date, cy_start) != :lt and
      Date.compare(s.sale_date, cy_end) != :gt
    end)
    |> Enum.map(& &1.sale_date)
  
  # RSU sell dates only — ESPP uses BH events (already tranche-level)
  rsu_sell_dates_in_cy = bh_sales
    |> Enum.filter(fn s -> s.plan_type == "RSU" end)
    |> Enum.filter(fn s ->
      Date.compare(s.sale_date, cy_start) != :lt and
      Date.compare(s.sale_date, cy_end) != :gt
    end)
    |> Enum.map(& &1.sale_date)
    |> Enum.uniq()
  
  if rsu_sell_dates_in_cy == [] do
    :ok  # No RSU sells in CY — G&L not needed
  else
    # Per-date check: each BH sell date must have a matching G&L allocation
    gl_allocation_dates = allocations
      |> Enum.map(& &1.sale_date)
      |> Enum.filter(& &1 != nil)
      |> MapSet.new()
    
    missing_dates = Enum.reject(rsu_sell_dates_in_cy, fn d ->
      MapSet.member?(gl_allocation_dates, d)
    end)
    
    if missing_dates == [] do
      :ok
    else
      dates_str = Enum.map(missing_dates, &Date.to_iso8601/1) |> Enum.join(", ")
      {:error, "G&L data missing for RSU sell dates: #{dates_str}. Upload G&L for #{calendar_year}."}
    end
  end
end
```

## Schedule FA Integration

`ScheduleFA.build` delegates to TrancheTimeline:

```elixir
def build(account_id, calendar_year) do
  {timelines, validation} = TrancheTimeline.build(account_id)
  
  # Check V2 for this specific CY
  case TrancheTimeline.validate_cy_coverage(validation, calendar_year) do
    :ok ->
      cy_holdings = TrancheTimeline.held_during_cy(timelines, calendar_year)
      rows = build_fa_rows(cy_holdings, calendar_year)
      {:ok, rows, validation.warnings}
    
    {:error, msg} ->
      {:error, msg}
  end
end
```

## BH Sold Validation

Per-origin reconciliation to detect fully-sold tranches without Holdings.

### Algorithm

```
apply_bh_sold_validation(timelines, bh_sales_by_origin, holdings_index)

  For each origin:
    total_released = SUM(tranche.net_quantity)
    gl_sold        = SUM(tranche.total_sold)  # from G&L/BH-matched sells
    bh_sold        = SUM(BH sale qty for origin)
    
    IF Holdings uploaded:
      total_held = SUM(holdings_qty || 0)
      remaining  = total_released - total_held - gl_sold
    ELSE (no Holdings):
      remaining  = total_released - gl_sold
    
    # Validate BH covers remaining
    IF bh_sold == total_released:
      → Fully sold origin
    ELIF bh_sold > total_released:
      → Emit warning (data error)
    ELIF bh_sold < total_released AND no Holdings:
      → Cannot determine — skip (holdings_needed)
    
    # Mark tranches as sold
    IF fully sold OR (Holdings uploaded AND BH covers remaining):
      For tranches with no sells AND (holdings_qty == nil OR not in Holdings):
        Set holdings_qty = Decimal.new(0)
        # Holdings override in held_during_cy will exclude from FA
```

### ESPP quantity matching (in build_sells)

```
For ESPP tranches without allocations:
  Search BH sales for this origin where sale.total_quantity == tranche.net_quantity
  If found: create sell entry with BH sale date (source: :bh)
  Take first match only (Enum.take(1))
```

### Key: no synthetic sell dates for RSU

RSU BH sales are origin-level — cannot assign per-tranche dates.
Instead: set `holdings_qty = 0` and rely on the Holdings override in `held_during_cy`:

```elixir
# In held_during_cy: Holdings override
if t.holdings_qty != nil and Decimal.equal?(t.holdings_qty, Decimal.new(0)) and
     Enum.empty?(t.sells) do
  {Decimal.new(0), Decimal.new(0), Decimal.new(0)}  # excluded from FA
end
```

## Timeline Summary

Per-symbol reconciliation for diagnostics and UI.

```elixir
def summary(timelines, bh_sales) do
  # Group by symbol
  by_symbol = Enum.group_by(timelines, & &1.symbol)
  bh_by_symbol = Enum.group_by(bh_sales, & &1.symbol) # needs symbol on bh_sales

  Map.new(by_symbol, fn {symbol, ts} ->
    total_released = sum(ts, :net_quantity)
    total_gl_sold  = sum(ts, :total_sold)
    holdings_held  = ts |> Enum.map(& &1.holdings_qty) |> Enum.reject(&is_nil/1) |> sum()
    has_holdings   = Enum.any?(ts, & &1.holdings_qty != nil)

    bh_sales_for_symbol = Map.get(bh_by_symbol, symbol, [])
    total_bh_sold = sum(bh_sales_for_symbol, :total_quantity)

    status = cond do
      Decimal.equal?(total_bh_sold, total_released) -> :reconciled
      has_holdings -> :reconciled  # Holdings provides ground truth
      Decimal.gt?(total_bh_sold, total_released) -> :error
      true -> :holdings_needed
    end

    {symbol, %{
      total_released: total_released,
      total_bh_sold: total_bh_sold,
      total_gl_sold: total_gl_sold,
      holdings_held: holdings_held,
      has_holdings: has_holdings,
      vested_unsold_bh: Decimal.sub(total_released, total_bh_sold),
      status: status
    }}
  end)
end
```

## Timeline View UI

Reusable component with two rendering modes.

### Component architecture

```
lib/stock_plan_web/
  components/
    timeline_view.ex          ← shared function component
  live/
    history_live.ex           ← hosts detail mode (first tab under /history)
    upload_live.ex            ← embeds summary mode post-upload
```

### Summary mode (upload page)

Rendered after all files processed. Inputs: `summary` map from `TrancheTimeline.summary/2`.

```
┌──────────────────────────────────────────┐
│ Data Summary                        ADBE │
│──────────────────────────────────────────│
│ Released: 146 shares (23 grants)         │
│ Sold:     106 shares (G&L: 82, BH: 24)  │
│ Held:      40 shares (Holdings: 40)      │
│ Status:   ✅ Reconciled                  │
│──────────────────────────────────────────│
│ Feature Readiness                        │
│ Portfolio      ✅  Schedule FA  ⚠        │
│ Capital Gains  ✅  Sell Advisor ✅       │
│──────────────────────────────────────────│
│ ⚠ Upload Holdings for accurate FA       │
│ [View full timeline →]                   │
└──────────────────────────────────────────┘
```

### Detail mode (History page)

Full per-grant drill-down. Inputs: `timelines` list from `TrancheTimeline.build/1`.

```
┌──────────────────────────────────────────────────────┐
│ Timeline                          Filter: All | RSU | ESPP │
│──────────────────────────────────────────────────────│
│ ▸ RU345463 (RSU) — 13 tranches, 6 sold, 7 held      │
│ ▾ RU305033 (RSU) — 3 tranches, 3 sold, 0 held       │
│   ├ vest 2019-01-24: 14 shares                       │
│   │  └ sold 2025-02-18: 14 @ $388.07 (G&L)          │
│   ├ vest 2020-01-24: 13 shares                       │
│   │  └ sold 2025-02-18: 13 @ $388.07 (G&L)          │
│   └ vest 2021-01-24: 13 shares                       │
│      └ sold 2025-06-17: 13 @ $405.20 (G&L)          │
│ ▸ ESPP 4a2ca... — 4 purchases, 4 sold, 0 held       │
│   ⚠ Sell dates inferred from Benefit History         │
└──────────────────────────────────────────────────────┘
```

### Structured validation output

All nudges/warnings use a standard format for consistent UI rendering:

```elixir
%{
  severity: :error | :warning | :info,
  code: :gl_missing | :holdings_needed | :qty_mismatch | :espp_best_effort,
  reason: "G&L data missing for RSU sell dates: 2024-03-15, 2024-06-20",
  impact: "Schedule FA and Capital Gains cannot be computed for CY 2024",
  action: "Download G&L Expanded for 2024 from E*Trade and upload"
}
```

## Files

- `lib/stock_plan/tax/tranche_timeline.ex` — Timeline Builder + Validator + Summary
- `lib/stock_plan/tax/schedule_fa.ex` — Updated to use Timeline
- `lib/stock_plan_web/components/timeline_view.ex` — Shared timeline UI component
- `lib/stock_plan_web/live/history_live.ex` — History page (timeline detail mode)
- `lib/stock_plan_web/live/upload_live.ex` — Upload page (timeline summary post-upload)
- `lib/stock_plan_web/live/tax_centre_live.ex` — Show validation errors/warnings
