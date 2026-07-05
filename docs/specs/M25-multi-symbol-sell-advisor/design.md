# Design: M25 — Multi-Symbol Sell Advisor

## Module layout

```
lib/stock_plan/tax/
├── sell_advisor.ex          # v1 — UNTOUCHED. Single-symbol exact-search + greedy fallback.
├── sell_advisor_v2.ex       # v2 — UNTOUCHED. Single-symbol 2-stage offset + greedy fill.
└── sell_advisor_multi.ex    # NEW. Multi-symbol holistic. Greedy fill-by-value.
```

The new module is a peer of v1/v2, not a subclass or replacement. It owns its own `advise/3` entry and its own internal optimizer. Where v1's utility helpers are symbol-agnostic and useful (tax classification, FY baseline loading, decimal helpers), they are called directly — but not modified.

## Engine dispatch

```
StockPlanWeb.SellAdvisorLive.run_advice/2
  │
  ├── symbol = "ALL"  ──►  SellAdvisorMulti.advise(account_id, target, opts)
  │
  └── symbol = "<TICKER>"  ──►  SellAdvisorV2.advise(account_id, target, symbol: ticker, ...)
```

The LiveView holds `@symbol` as `nil | "ALL" | "<TICKER>"`. The dropdown emits the literal string `"ALL"`; mount maps it to engine selection.

## SellAdvisorMulti — algorithm sketch

```
advise(account_id, target, opts):
  validate(target)                                       # must be {:usd, _} or {:inr, _}
  prices = load_prices(held_symbols)                     # %{sym => Decimal}
  fx     = current_fx()
  lots   = load_sellable_lots(account_id, nil)           # v1 helper, all-symbols path
  lots   = enrich_each_lot(lots, prices, fx)             # NEW — uses prices[lot.symbol]
  lots   = classify_each_lot(lots, today)                # reuse v1 classification

  fy_baseline = SellAdvisor.load_fy_baseline(account_id, today)
  target_value = to_target_unit(target, fx)              # convert :usd ↔ :inr if needed

  # Stage 1 — offset existing FY gains with loss lots
  {stage1_entries, committed_ids, committed_keys} =
    run_stage1_multi(lots, fy_baseline, prices, fx)

  # Stage 2 — fill remaining value gap
  filled_value = sum_value(stage1_entries, prices)
  remaining    = Decimal.sub(target_value, filled_value)

  stage2_entries =
    if Decimal.gt?(remaining, 0):
      fill_by_value(lots_excluding(committed_ids), remaining,
                    fy_baseline, prices, fx, committed_keys)
    else: []

  basket = build_multi_basket(stage1_entries ++ stage2_entries, target, fy_baseline)
  {:ok, %{version: "multi", baskets: [basket], ...}}
```

## Stage 2 — fill_by_value

Greedy with marginal evaluation, parallel structure to v2's `do_fill_v2/N` but keyed on value not shares.

```
fill_by_value(uncommitted, remaining_value, baseline, prices, fx, committed_keys):
  basket = []
  remaining = remaining_value
  while remaining > 0 and uncommitted != []:
    best = pick_best_lot(uncommitted, basket, baseline, prices, fx, committed_keys)
    qty  = qty_to_take_from(best, remaining, prices)        # may be partial
    entry = build_entry(best, qty, prices, fx)
    basket = basket ++ [entry]
    remaining = Decimal.sub(remaining, value_of(entry, prices))
    uncommitted = remove_or_decrement(uncommitted, best, qty)
  basket
```

### pick_best_lot scoring

For each candidate lot, compute its **marginal contribution score**:

```
tax_score   = marginal_tax_charge(lot, basket, baseline, fx)
order_score = if {lot.symbol, lot.plan_type} in basket_keys(basket): 0 else: ORDER_PENALTY
total_score = tax_score + order_score
```

`ORDER_PENALTY` matches v2's existing `plan_penalty` magnitude. Lower score = better lot. Ties broken by `vest_date` ascending (FIFO).

The cohesion key change vs v2 is exactly:
- v2: `basket_keys = MapSet<plan_type>`
- multi: `basket_keys = MapSet<{symbol, plan_type}>`

Same shape; different equivalence class. This is the only structural change in the cohesion logic.

### qty_to_take_from

```
qty_to_take_from(lot, remaining_value, prices):
  price = prices[lot.symbol]
  max_qty = lot.sellable_qty
  needed = Decimal.div(remaining_value, price) |> Decimal.round(0, :ceiling)
  Decimal.min(max_qty, needed)
```

If `needed > max_qty`, take the whole lot and move on. If `needed < max_qty`, take a partial slice (whole shares, ceiling round).

## Stage 1 — offset existing gains

Mirrors v2's `run_stage1` but the `committed_keys` MapSet now holds `{symbol, plan_type}` tuples instead of plain `plan_type`. Loss lot selection itself is unchanged — it doesn't care about symbol.

## Output shape

```elixir
%{
  version: "multi",
  baskets: [
    %{
      name: "Multi-Symbol Holistic",
      entries: [
        # Each entry: lot + qty_to_sell + per-lot tax fields. Symbol on every entry's lot.
        %{lot: %{symbol: "ADBE", plan_type: "RSU", vest_date: ~D[2024-01-15], ...},
          qty_to_sell: Decimal.new("12"),
          proceeds_inr: ..., cost_basis_inr: ..., gain_loss_inr: ..., gain_type: :STCG, ...},
        ...
      ],
      by_symbol_plan_type: %{
        {"ADBE", "RSU"}  => %{entries: [...], qty: ..., proceeds_inr: ..., gain_loss_inr: ...},
        {"CRM",  "RSU"}  => %{entries: [...], qty: ..., proceeds_inr: ..., gain_loss_inr: ...}
      },
      by_plan_type: %{
        "RSU"  => %{stcg_inr: ..., ltcg_inr: ...},
        "ESPP" => %{...}
      },
      tax_summary: %{stcg_inr: ..., ltcg_inr: ..., charges: ..., net_proceeds_inr: ...},
      order_count: 2,
      total_proceeds_inr: ...,
      total_qty: ...   # NOT semantically meaningful across symbols but kept for display
    }
  ],
  current_prices: %{"ADBE" => Decimal.new("260.88"), "CRM" => Decimal.new("...")},
  current_fx: Decimal.new("94.80"),
  target: {:inr, Decimal.new("500000")},
  target_value: Decimal.new("500000"),
  fy_baseline: %{...},
  warnings: []
}
```

## LiveView changes

`StockPlanWeb.SellAdvisorLive`:

1. **Mount** — when `length(held_symbols) >= 2`, default `@symbol = "ALL"`.
2. **Selector** — dropdown shows `<option value="ALL">All symbols</option>` first, then each held symbol. Hidden when `length(held_symbols) == 1`.
3. **Target input** — when `@symbol == "ALL"`, disable the "Shares" radio button and only allow USD / INR.
4. **Dispatcher** — `run_advice/2` switches on `@symbol`:
   - `"ALL"` → `SellAdvisorMulti.advise(...)`
   - other → `SellAdvisorV2.advise(..., symbol: @symbol)`
5. **Render basket** — when result `version == "multi"`, iterate `by_symbol_plan_type` and render one block per `{symbol, plan_type}` pair. Each block shows: header "Place this order on E*Trade — Symbol Plan_type", entries table, sub-total. When `version == "v2"`, existing render path is unchanged.
6. **CSV download** — dispatch to `SellAdvisorMulti.basket_to_csv/3` for multi results.

## Stage-1 / Stage-2 overshoot

If Stage 1 alone produces basket value ≥ target value (loss lots covered the target), Stage 2 is skipped. Warning emitted: `"Tax harvest alone covered the target — no additional lots needed"`.

## Test data

SU5 (`docs/Sample-Data/SampleUser - 5/`) is the canonical multi-symbol fixture. Tests should cover ADBE + CRM combinations against this data.

## Non-goals reminder

- No `:harvest` mode for multi (yet).
- No exact-search optimizer for multi (yet) — greedy only.
- No fancy mixed-currency support — one FX rate, one target unit.
