# Design: M15 — Sell Advisor

> **See also:** [Algorithm Design](algorithm-design.md) for detailed algorithm, worked examples, and edge cases

## Architecture

```
SellAdvisor.advise(account_id, target)
  │
  ├── Load sellable lots from Holdings Silver
  ├── Enrich: gain_type, gain_per_share_inr, tax_cost
  ├── Load FY baseline from CapitalGains
  ├── Load current_price + current_fx
  │
  ├── Basket 1: Exact Target
  │     Sort by tax efficiency + offset preservation
  │     Fill exactly to target (partial lot OK)
  │     Evaluate tax via offset cascade
  │
  ├── Basket 2: Cost Optimized
  │     Enumerate whole-lot combos near target
  │     Rank by (tax + charges) / proceeds
  │     Pick best combo
  │
  └── Dedup + return baskets
```

## Context Module

```elixir
defmodule StockPlan.Tax.SellAdvisor do
  @doc """
  Generate sell recommendations for a target.
  Returns {:ok, [basket]} or {:error, reason}.
  """
  def advise(account_id, target, opts \\ [])
  
  # target: {:shares, Decimal} | {:usd, Decimal} | {:inr, Decimal}
end
```

## Data Flow

```
Holdings Silver (sellable_qty > 0)
  → enrich with gain_type, gain_inr, tax_cost
  → filter out nil cost_basis
  
CapitalGains.build(current_fy)
  → FY baseline: realized STCG, STCL, LTCG, LTCL

Current price: StockPrice.current_price("ADBE")
Current FX: FX.current_rate()

  → Basket 1: greedy fill (Algorithm §10.1)
  → Basket 2: whole-lot optimization (Algorithm §10.2)
  → TaxEvaluator on each basket
  → Dedup if identical
  → Return
```

## Tax Evaluation (Offset Cascade)

Reused from equity tax harvest TaxEvaluator. See Algorithm Design §3.

```elixir
defp evaluate_tax(basket_entries, fy_baseline) do
  # Aggregate basket gains/losses by type
  {st_gain, st_loss, lt_gain, lt_loss} = aggregate_by_type(basket_entries)
  
  # Combine with FY baseline
  net_st = (fy_baseline.realized_st_gain + st_gain) - (fy_baseline.realized_st_loss + st_loss)
  leftover_st_loss = max(0, -net_st)
  
  net_lt = (fy_baseline.realized_lt_gain + lt_gain) - (fy_baseline.realized_lt_loss + lt_loss)
  adj_net_lt = net_lt - leftover_st_loss  # STCL cross-offsets LTCG
  
  st_tax = max(0, net_st) * 0.312
  lt_tax = max(0, adj_net_lt) * 0.13
  
  %{st_tax: st_tax, lt_tax: lt_tax, total_tax: st_tax + lt_tax}
end
```

## Transaction Charges

```elixir
defp compute_charges(basket_entries) do
  has_espp = Enum.any?(basket_entries, & &1.lot.plan_type == "ESPP")
  has_rsu = Enum.any?(basket_entries, & &1.lot.plan_type == "RSU")
  
  order_count = (if has_espp, do: 1, else: 0) + (if has_rsu, do: 1, else: 0)
  
  wire_fee = Decimal.new("25")  # $25 per transfer
  brokerage = Decimal.mult(Decimal.new("0"), order_count)  # TBD per order
  
  %{wire_fee: wire_fee, brokerage: brokerage, order_count: order_count,
    total_charges_usd: Decimal.add(wire_fee, brokerage)}
end
```

## LiveView

### Route
```elixir
live "/sell", SellAdvisorLive
```

### Template Layout

```
┌──────────────────────────────────────────────────────┐
│  Sell Advisor                                         │
│                                                       │
│  ADBE $252.71  |  1 USD = ₹94.80                     │
│                                                       │
│  I want to sell:                                      │
│  (●) Shares  ( ) USD amount  ( ) INR amount           │
│  [  10  ]  shares                    [Advise]         │
│                                                       │
│  FY 2025-26: STCG ₹0  |  LTCG ₹0                    │
│                                                       │
├──────────────────────────────────────────────────────┤
│                                                       │
│  ┌─ Basket 1: Exact Target ───────────────────────┐  │
│  │ 10 shares | Proceeds: ₹2.1L | Tax: ₹0          │  │
│  │ Net: ₹2.1L | 2 orders | Charges: $25           │  │
│  │ LTCL used: ₹4,745 offsets LTCG ₹4,673          │  │
│  │ [▸ View lots]                  [Download CSV]    │  │
│  └──────────────────────────────────────────────────┘  │
│                                                       │
│  ┌─ Basket 2: Cost Optimized ─────────────────────┐  │
│  │ 11 shares (+1) | Proceeds: ₹2.3L | Tax: ₹0     │  │
│  │ Net: ₹2.3L | 2 orders | Charges: $25           │  │
│  │ ℹ Sells 1 extra share to avoid partial lot      │  │
│  │ [▸ View lots]                  [Download CSV]    │  │
│  └──────────────────────────────────────────────────┘  │
│                                                       │
│  ⚠ Estimates only. Consult your tax advisor.          │
└──────────────────────────────────────────────────────┘
```

## Files

- `lib/stock_plan/tax/sell_advisor.ex` — context module
- `lib/stock_plan_web/live/sell_advisor_live.ex` — LiveView
- Route: `/sell`
- Nav: "Sell Advisor" link in root layout
