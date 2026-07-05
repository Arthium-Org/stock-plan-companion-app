# Tasks: M25 — Multi-Symbol Sell Advisor

Order is bottom-up: engine → output → dispatch → UI → tests. Each task is one logical commit.

---

## M25.1 — Skeleton + lot loading

- [ ] Create `lib/stock_plan/tax/sell_advisor_multi.ex` with:
  - Module + moduledoc
  - `advise/3` signature returning `{:error, :not_implemented}` for now
  - Input validation: reject `{:shares, _}` and `:harvest` targets, reject if `held_symbols < 2`
- [ ] `defp load_prices(symbols)` — wraps `StockPlan.StockPrice.current_price/1` per symbol → `%{sym => Decimal}`
- [ ] Reuse `SellAdvisor.load_sellable_lots(account_id, nil)` for cross-symbol lot pull
- [ ] Initial unit test: `advise/3` rejects bad targets / single-symbol accounts

## M25.2 — Lot enrichment + classification (multi-price)

- [ ] `defp enrich_lots_multi(lots, prices, fx, today)` — for each lot, computes `current_price = prices[lot.symbol]`, `current_value_inr`, `gain_per_share_inr`, etc. Mirrors v1's `enrich_lot/4` but per-symbol-priced.
- [ ] Reuse v2's `classify_lots/2` (it's symbol-agnostic — only looks at vest_date + gain direction)
- [ ] Unit tests against SU5 lots: verify each lot's enriched price matches its symbol's price.

## M25.3 — Stage 1 — offset existing gains

- [ ] `defp run_stage1_multi(lots, fy_baseline, prices, fx)` — mirrors v2's `run_stage1/4` shape:
  - Sort loss lots in same order v2 does (STCL first, then LTCL)
  - Pick lots greedily up to offset thresholds
  - Returns `{entries, committed_ids, committed_keys}` where `committed_keys :: MapSet<{symbol, plan_type}>`
- [ ] Tests: when FY baseline has STCG ₹X, stage 1 picks STCL lots until offset; entries have correct per-lot prices.

## M25.4 — Stage 2 — fill-by-value

- [ ] `defp fill_by_value(uncommitted, remaining_value, baseline, prices, fx, committed_keys)`:
  - Greedy loop: pick best lot by marginal score, take partial or whole, decrement remaining
  - `defp pick_best_lot/6` — scores each candidate, returns lowest
  - `defp marginal_tax_charge_multi/4` — reuse v1's `compute_charges` on the projected basket
  - `defp order_penalty/2` — returns `ORDER_PENALTY` if `{lot.symbol, lot.plan_type}` not in basket keys, else 0
  - `defp qty_to_take_from/3` — see design.md
- [ ] `ORDER_PENALTY` constant matches v2's `plan_penalty` value (extract to constant if not already)
- [ ] Tests covering:
  - One-symbol fill (multi engine should match v2 within ₹1 of variance, since cohesion key collapses)
  - Two-symbol fill with target reachable from one symbol — confirm engine prefers one-symbol solution (lower order_count)
  - Two-symbol fill with target requiring both — confirm output has order_count == 2
  - Partial lot taking — confirm last lot's qty < its sellable_qty

## M25.5 — Output construction

- [ ] `defp build_multi_basket(entries, target, fy_baseline)`:
  - `by_symbol_plan_type` grouped map
  - `by_plan_type` aggregate (reuse `SellAdvisor.aggregate_by_type/1`)
  - `tax_summary` using `SellAdvisor.evaluate_tax/2`
  - `order_count = map_size(by_symbol_plan_type)`
  - Total proceeds, total qty (with caveat in moduledoc that total_qty is display-only)
- [ ] `def basket_to_csv(basket, prices, fx)` — add Symbol column, sort by `{symbol, plan_type, vest_date}`
- [ ] Tests: assert basket structure matches design.md output schema for SU5 fixtures.

## M25.6 — LiveView dispatch

- [ ] `StockPlanWeb.SellAdvisorLive` mount: when `length(held_symbols) >= 2`, default `@symbol = "ALL"`
- [ ] Dropdown: add `<option value="ALL">All symbols</option>` at top; hide selector entirely when 1 symbol
- [ ] Target radio buttons: when `@symbol == "ALL"`, disable "Shares" and force USD/INR
- [ ] `handle_event("advise", ...)` dispatches:
  - `"ALL"` → `SellAdvisorMulti.advise(...)`
  - otherwise → `SellAdvisorV2.advise(..., symbol: @symbol)`
- [ ] CSV download path routes to right module's `basket_to_csv/3`
- [ ] Render: when `result.version == "multi"`, iterate `by_symbol_plan_type` blocks; else existing render path

## M25.7 — LiveView render

- [ ] Per `{symbol, plan_type}` block layout:
  - Header: "Order: {SYMBOL} — {PLAN_TYPE} ({N lots})"
  - Entries table with columns matching v2's basket table + a Vest Date / Qty / Gain Type per row
  - Sub-total row: shares to sell, proceeds, gain/loss
- [ ] Overall basket totals (proceeds, tax, net) below the per-order blocks
- [ ] Warning rendering (e.g. "Tax harvest alone covered the target")

## M25.8 — Tests

- [ ] `test/stock_plan/tax/sell_advisor_multi_test.exs` — unit tests for the engine
- [ ] `test/stock_plan_web/live/sell_advisor_live_test.exs` — LiveView smoke + multi-symbol render test using SU5 fixtures
- [ ] Regression: existing `sell_advisor_test.exs` (v1) and v2 tests must still pass unchanged

## M25.9 — Docs

- [ ] Update `CLAUDE.md` Phase Plan section to mention multi-symbol advisor under Phase 2 if not already
- [ ] Update `docs/specs/M25-multi-symbol-sell-advisor/design.md` with any deviations discovered during implementation
