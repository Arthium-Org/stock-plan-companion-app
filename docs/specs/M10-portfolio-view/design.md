# Design Document: M10 — Portfolio View (Revised)

> **See also:** [System Invariants](../../core/invariants.md) — especially #4 (portfolio composition), #5 (cost basis fallback), #7 (never invent financial truth)

## Overview

M10 is a read-only LiveView page showing current holdings from the **Holdings (ByBenefitType) ingestion only**. No BH-derived data. Holdings data enriches tranches with sellable_qty, cost_basis_broker, and tax_status via Silver Builder Phase 5. Portfolio reads these enriched tranches.

### Architecture

```
Holdings XLSX (ByBenefitType_expanded)
    |
    v
Bronze → Silver Phase 5 → tranches enriched with:
                             sellable_qty, cost_basis_broker, tax_status
    |
    v
Portfolio.build(account_id)
    → SELECT tranches WHERE sellable_qty > 0 OR status = UNVESTED
    → Join origins for grant_number, plan_type, symbol
    |
    v
PortfolioLive
    mount:
      → Portfolio.build(account_id)
      → StockPrice.current_price(symbol)
      → FX.current_rate()
    assigns:
      @holdings       — list of holding rows (from Holdings-enriched tranches)
      @summary        — totals (current value + potential value)
      @current_price  — live stock price
      @current_fx     — current FX rate
      @currency       — "USD" | "INR"
      @group_by       — "type" | "status"
      @filters        — %{vested: true, unvested: true, pnl: nil}
      @sort           — {field, :asc | :desc}
```

## Components

### 1. Portfolio Context (`lib/stock_plan/portfolio.ex`) — Rewrite

Reads from Holdings-enriched tranches only. No sale_allocation math.

```elixir
defmodule StockPlan.Portfolio do
  @doc """
  Build portfolio from Holdings-enriched tranches.
  Returns [] if no Holdings data has been ingested.

  Composition:
    VESTED  → from Holdings (sellable_qty > 0)
    UNVESTED → from Benefit History vest schedule
  """
  def build(account_id) do
    # Check: does an ACTIVE Holdings ingestion exist? If not, return [].
    #
    # Query tranches joined with origins for ACTIVE ingestion
    # WHERE:
    #   sellable_qty > 0 (vested, has shares to sell per broker)
    #   OR status = "UNVESTED" (future vests from BH vest schedule)
    #
    # Exclude: sellable_qty = 0 (fully sold per broker)
    #
    # For each tranche:
    #   VESTED: quantity = sellable_qty (from Holdings)
    #   UNVESTED: quantity = vest_quantity (from BH vest schedule)
    #
    # Cost basis (pure fallback, no reconciliation):
    #   cost_basis_broker > vest_fmv > vest_day_close > nil
  end
end
```

**Holding row struct:**
```elixir
%{
  origin_id: "...",
  plan_type: "RSU",
  grant_number: "RU422478",
  symbol: "ADBE",
  origin_date: ~D[2025-01-24],
  tranche_id: "...",
  vest_date: ~D[2025-04-15],
  status: "VESTED",
  quantity: Decimal | nil,           # sellable_qty (vested) or vest_quantity (unvested)
  cost_basis_per_share: Decimal | nil,
  cost_basis_source: :broker | :actual_fmv | :market_close | :unavailable,
  vest_fx_rate: Decimal | nil,
  origin_fx_rate: Decimal | nil
}
```

### 2. Cost Basis per Tranche

```elixir
defp tranche_cost_basis(origin, tranche) do
  cond do
    # Priority 1: Holdings broker-calculated cost basis
    tranche.cost_basis_broker ->
      {to_decimal(tranche.cost_basis_broker), :broker}

    # Priority 2: G&L actual FMV
    tranche.vest_fmv ->
      {to_decimal(tranche.vest_fmv), :actual_fmv}

    # Priority 3: Yahoo market close (approximate)
    tranche.vest_day_close ->
      {to_decimal(tranche.vest_day_close), :market_close}

    # ESPP: buy_price from metadata
    origin.plan_type == "ESPP" ->
      meta = tranche.metadata_json && Jason.decode!(tranche.metadata_json)
      price = meta && meta["buy_price"]
      if price, do: {Decimal.new(price), :broker}, else: {nil, :unavailable}

    true ->
      {nil, :unavailable}
  end
end
```

### 3. Summary Computation

```elixir
def compute_summary(holdings, current_price) do
  price = current_price && Decimal.new(current_price)

  vested = Enum.filter(holdings, & &1.status == "VESTED")
  unvested = Enum.filter(holdings, & &1.status == "UNVESTED")

  current_value = sum_value(vested, price)
  potential_value = sum_value(unvested, price)

  %{
    current_value: current_value,
    potential_value: potential_value,
    total_value: Decimal.add(current_value, potential_value),
    vested_shares: sum_qty(vested),
    unvested_count: length(unvested),
    by_plan_type: group_summary_by_plan(holdings, price)
  }
end
```

### 4. Template Layout

```
┌──────────────────────────────────────────────────────────────┐
│  Portfolio                                    [USD] [INR]    │
├──────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Total Value   │  │   Current    │  │  Potential    │       │
│  │  $45,213      │  │   $12,540    │  │  $32,673     │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
│  ADBE  $252.71  ┃  RSU: $8,200 + $28,000                    │
│                  ┃  ESPP: $4,340 + $4,673                    │
├──────────────────────────────────────────────────────────────┤
│  Group: [By Type] [By Status]                                │
│  Filter: [✓ Vested] [✓ Unvested] [Profit] [Loss]            │
├──────────────────────────────────────────────────────────────┤
│  ▾ RSU                                                       │
│    ▾ RU422478                                                │
│      2025-04-15 │ VESTED │  7 shr │ $350.7 │ LT │ $1,769│+$200│
│      2025-07-15 │ VESTED │  8 shr │ $365.6*│ ST │ $2,022│-$50 │
│      2026-01-15 │ UNVEST │ 12 shr │  —     │    │ $3,033│  —  │
│  ▾ ESPP                                                      │
│    ▾ 2024-06-30                                              │
│      2024-06-30 │ VESTED │  5 shr │ $420.2 │ LT │ $1,263│+$50 │
├──────────────────────────────────────────────────────────────┤
│  * Market Adjusted Close (actual FMV unavailable)            │
│  FX: SBI TT Buying Rate (2020+), RBI Reference Rate (prior) │
└──────────────────────────────────────────────────────────────┘

Empty state (no Holdings):
┌──────────────────────────────────────────────────────────────┐
│  Portfolio                                    [USD] [INR]    │
│                                                              │
│     No holdings data. Upload your ByBenefitType file         │
│     to view portfolio.  [Upload →]                           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 5. Display Values (computed in LiveView template)

| Value | Computation |
|---|---|
| Current Account Value | sum(sellable_qty x current_price) for vested |
| Potential Benefit Value | sum(vest_quantity x current_price) for unvested |
| Per-row Value | qty x current_price |
| Per-row Unrealized P&L | (current_price - cost_basis) x qty (vested only) |
| INR values | USD value x appropriate FX rate |

### 6. Key Differences from Previous Design

| Aspect | Previous (BH-derived) | New (Holdings-sourced) |
|---|---|---|
| Vested qty | net_qty - sum(sale_allocations) | sellable_qty from Holdings |
| Cost basis | vest_fmv > vest_day_close | cost_basis_broker > vest_fmv > vest_day_close |
| Empty state | "No holdings found" | "Upload Holdings file" |
| Data dependency | BH + G&L required | Holdings required; BH for unvested schedule |
| Sold detection | Sale allocation math | Broker reports 0 sellable = not shown |
| Tax status | Not available | Not stored in Silver (date-sensitive, US-only). Computed in Tax Centre. |

### 7. Unvested Tranches

Unvested tranches come from Benefits History vest schedule (not Holdings). Holdings only reports what's currently held/sellable. The vest schedule from BH provides future vest dates and quantities.

- If BH ingested: unvested tranches shown with vest_date and quantity
- If BH not ingested: only Holdings-derived vested rows shown (no future schedule)

## Implementation Notes

- `Portfolio.build` is a rewrite — replaces the current BH-derived implementation
- No sale_allocation queries needed — Holdings is the source of truth for sellable qty
- Tax status column is new — from Holdings Sellable Shares rows
- cost_basis_source adds `:broker` as highest priority
- Grouping/filtering/sorting logic in LiveView stays the same (UI behavior unchanged)
- Template adds Tax Status column + "Holdings as of" timestamp
- **Cost basis invariant:** Pure fallback chain, never reconcile broker vs vest_fmv. They may differ (wash sales, ESPP qualification adjustments) and broker is authoritative.

## Snapshot Timestamp

```elixir
# In mount, fetch Holdings ingestion date:
holdings_ingestion = Ingestions.get_active_holdings(account_id)
holdings_as_of = holdings_ingestion && holdings_ingestion.inserted_at

# Display in template:
# "Holdings as of: 5 May 2026"
```

Shows users this is a point-in-time snapshot. Prompts re-upload when stale.
