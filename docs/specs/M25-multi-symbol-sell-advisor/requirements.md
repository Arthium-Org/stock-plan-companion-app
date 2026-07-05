# Requirements: M25 — Multi-Symbol Sell Advisor

## Introduction

The current Sell Advisor (`StockPlan.Tax.SellAdvisor` v1 / `SellAdvisorV2` v2) is a single-symbol engine. It loads sellable lots for one symbol, uses one current price, resolves the user's target as a share count, and runs a two-stage tax-aware lot selection.

M22 made the *display* layer (Portfolio, Tax Centre) multi-symbol-aware, but stopped at the advisor by design. The advisor still expects a single symbol to be selected before it can run.

When a user holds shares in more than one symbol, the natural question is **"what should I sell to raise ₹X, given my whole portfolio?"** — not "which symbol's window am I in?" Today they have to flip between symbol-scoped advisor runs and mentally combine the results. The optimizer can't see across symbols, so the answer it returns may be tax-suboptimal compared to a holistic mix.

M25 adds a **separate, holistic engine** that considers all sellable lots across all symbols and returns one basket. The existing v1/v2 engine is preserved untouched for single-symbol use. The LiveView routes to the right engine based on user data and selection.

---

## Requirement 1: Preserve the existing single-symbol engine

`lib/stock_plan/tax/sell_advisor.ex` (v1) and `lib/stock_plan/tax/sell_advisor_v2.ex` (v2) must not be modified by M25. They continue to back single-symbol runs and any future single-symbol algorithm work.

**Rationale:** v2 is battle-tested against real user data, all existing single-symbol behaviour and tests must remain stable, and routing dispatches the right engine — no algorithm regression risk.

---

## Requirement 2: New holistic engine — `StockPlan.Tax.SellAdvisorMulti`

A new module that:

- Loads sellable lots across all symbols the user holds.
- Accepts a price map `%{symbol => Decimal}` and current FX rate.
- Accepts a target in `{:usd, amount}` or `{:inr, amount}` (value-based).
- Does **not** accept `{:shares, n}` — share counts are not portfolio-wide meaningful (10 ADBE ≠ 10 CRM).
- Does **not** accept `:harvest` in v1; can be added in a later iteration if needed.
- Returns a basket with entries grouped by `{symbol, plan_type}` plus an aggregate tax view.

The engine reuses helper utilities from v1 where they are already symbol-agnostic (e.g. `evaluate_tax`, `compute_charges`, `load_fy_baseline`, `ensure_decimal`, `validate_price_fx`). It does not call v2's `advise/3`.

---

## Requirement 3: Order-count cohesion bias

A brokerage order is per `{symbol, plan_type}` — you cannot combine ADBE-RSU lots and CRM-RSU lots into one order, and you cannot combine RSU lots and ESPP lots of the same symbol into one order either.

The fill optimizer prefers solutions with **fewer distinct `{symbol, plan_type}` tuples** in the basket, all else equal. This generalizes the existing v2 plan-type penalty to a tuple key. The weight matches v2's existing penalty (no special "symbol heavier than plan-type" weighting — both are equally "one more order").

---

## Requirement 4: Fill-by-value (not fill-by-shares) for Stage 2

Today v2 converts a `:usd` or `:inr` target into a share count using a single price, then fills greedily until the share count is reached. Multi-symbol has no single price → no single share count.

The new engine accumulates **basket value** as `Σ qty × prices[lot.symbol]` (in INR or USD per the target unit), and stops when basket value ≥ target value. Overshoot rules mirror v2: prefer the smallest overshoot subject to the cohesion and tax-optimality constraints.

---

## Requirement 5: Tax math unchanged

Indian capital-gains setoff aggregates STCG and LTCG buckets across all instruments — symbol does not affect setoff rules. The tax math (`evaluate_tax`, `compute_charges`, FY baseline aggregation, `aggregate_by_type`) keeps `plan_type` as its only key. `{symbol, plan_type}` keying is for the **operational/display layer** only (orders + UI grouping).

---

## Requirement 6: Engine dispatch from LiveView

`StockPlanWeb.SellAdvisorLive` chooses an engine based on user holdings + symbol selection:

| User holdings | Symbol selector value | Engine called |
|---|---|---|
| 1 held symbol | (selector hidden, auto-selected) | `SellAdvisorV2` |
| ≥2 held symbols | specific symbol picked | `SellAdvisorV2` (scoped to that symbol) |
| ≥2 held symbols | "All symbols" picked | `SellAdvisorMulti` |

The selector defaults to "All symbols" when ≥2 are held. It is hidden when 1 is held. The `:shares` target input is disabled when "All symbols" is active (Requirement 2).

---

## Requirement 7: Output structure

`SellAdvisorMulti.advise/3` returns `{:ok, result}` where:

```
result.version = "multi"
result.baskets = [basket]                    # one basket
result.current_prices = %{symbol => Decimal}
result.current_fx = Decimal
result.target = {:usd, amount} | {:inr, amount}
result.target_value = Decimal                # in target's unit
result.fy_baseline = %{...}                  # same shape as v2
result.warnings = [string]

basket.entries = [%{lot: ..., qty_to_sell: ..., ...}]   # symbol on every lot
basket.by_symbol_plan_type = %{{symbol, plan_type} => %{...}}    # per-order breakdown
basket.by_plan_type = %{plan_type => %{...}}                     # tax-side aggregate (symbol-agnostic)
basket.tax_summary = %{...}                                       # same shape as v2
basket.order_count = integer                                      # length of by_symbol_plan_type
```

---

## Requirement 8: CSV export

`SellAdvisorMulti.basket_to_csv/3` produces CSV with the same columns as v1's `basket_to_csv`, plus a `Symbol` column. Rows are sorted by `(symbol, plan_type, vest_date)` so each contiguous block corresponds to one brokerage order.

---

## Out of scope (for M25)

- Tax-loss harvest mode (`:harvest`) for the multi engine. Single-symbol v2 still supports it.
- Exact-search (`enumerate_combinations`) in the multi engine. Stage-2 is greedy fill-by-value only.
- Multi-currency: target unit is INR or USD; engine uses one FX rate for conversion. No support for multi-currency mixed lots.
- Schwab / Fidelity broker variation in order-count rules. ETRADE rules apply.
