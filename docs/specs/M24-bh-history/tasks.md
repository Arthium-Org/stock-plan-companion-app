# Tasks: M24 — Benefit History Analysis Page

## Prerequisites

- M21 tranche timeline (shipped — M24 uses Silver as-is)
- M22 multi-symbol (on same branch — M24 assumes per-symbol symbol selection)

---

## Task 1: XIRR module

**Files:** `lib/stock_plan/finance/xirr.ex`, `test/stock_plan/finance/xirr_test.exs`

- [x] 1.1 Implement `StockPlan.Finance.XIRR.xirr/2` — Newton-Raphson with bisection fallback. Returns `{:ok, float()}` or `{:error, :no_convergence}`.
- [x] 1.2 Helper `npv/2` (net present value at given rate) for the iterative solver.
- [x] 1.3 Tests: known cashflows with verifiable answers, edge cases (empty, all-outflow, all-same-date).
- [x] 1.4 `mix test` pass.

---

## Task 2: History context module

**Files:** `lib/stock_plan/history.ex`, `test/stock_plan/history_test.exs`

- [x] 2.1 `History.build/1` — loads origins, tranches, sales+allocations in 3 queries; fans out by symbol in Elixir.
- [x] 2.2 `compute_rsu_summary/4` — 7 summary fields (total_granted, total_vested, total_sold, currently_held, grant_value, vest_income, realized_proceeds) in USD + INR.
- [x] 2.3 `compute_rsu_income_by_year/2` — vest value per calendar year in USD + INR.
- [x] 2.4 `compute_rsu_tax_by_year/2` — tax_withheld_value per year in INR.
- [x] 2.5 `compute_grant_rows/4` — one row per RSU origin with grant_value, vested_qty, sold_qty, realized_proceeds, unrealized_value, return_pct.
- [x] 2.6 `compute_rsu_counterfactual/4` — actual_total vs if_held_all vs delta in USD.
- [x] 2.7 `compute_vesting_velocity/2` — shares per quarter, last 12 quarters.
- [x] 2.8 `compute_yoy_growth/1` — derived from cumulative income, adds pct_change field.
- [x] 2.9 `compute_espp_analysis/6` — full ESPP section: lots, summary, sold_lots, unsold_lots, qualifying split.
- [x] 2.10 `build_espp_lots/4` — one lot per ESPP tranche; reads buy_price from `tranche.metadata_json["buy_price"]`; computes sold_qty, held_qty, realized_pnl, pnl_pct, unrealized_pnl, total_discount, if_sold_at_purchase; includes raw `allocs` list.
- [x] 2.11 ESPP summary fields: `purchase_value = Σ(gross_shares × buy_price)`, `total_discount = Σ((vest_fmv − buy_price) × gross_shares)`.
- [x] 2.12 INR variants for ESPP summary: `purchase_value_inr`, `total_discount_inr`, `realized_pnl_inr`, `unrealized_pnl_inr`, `sell_on_purchase_inr` — pre-computed via `to_inr(usd, current_fx)`.
- [x] 2.13 `compute_espp_xirr_from_lots/3` — outflow `−(gross_shares × buy_price)` at purchase_date; one sale inflow per alloc at alloc.sale_date; held inflow at today. Uses `l.allocs` for per-alloc inflows.
- [x] 2.14 `compute_qualifying_split_from_lots/1` — qualifying/disqualifying split from lot allocs.
- [x] 2.15 `load_espp_allocs_by_tranche/1` — SQL with `COALESCE(alloc.sale_price, sale.sale_price)`; retries Yahoo via `yahoo_price_safe/2` for nil prices.
- [x] 2.16 `yahoo_price_safe/2` — `try/rescue` wrapper; emits `Logger.warning/1` on failure; returns nil.
- [x] 2.17 Empty-DB path: returns `%{symbols: [], prices: %{}, prices_fetched_at: DateTime.utc_now(), rsu: %{}, espp: %{}}`.
- [x] 2.18 Tests: per-section compute functions + full `build/1` with fixtures.

---

## Task 3: Chart components

**File:** `lib/stock_plan_web/components/charts.ex`

- [x] 3.1 `bar_chart` — single series, configurable color, currency-aware Y labels.
- [x] 3.2 `stacked_bar_chart` — multiple named series.
- [x] 3.3 `line_chart` — YoY growth (supports negative values, nil pct_change renders as gap).
- [x] 3.4 `pnl_bar_chart` — signed P&L bars: green `#10B981` / red `#F43F5E`; zero baseline; % label per bar (above for positive, below for negative); width = `slot × 0.5`.
- [x] 3.5 `cost_basis_chart` — scatter dots with connecting polyline; dashed indigo `#6366F1` reference line at current_price; SVG `<title>` in each `<circle>` for browser hover showing `"[date] — [+/−X.Y%] vs current"`.
- [x] 3.6 Global chart sizing: `@h 200`, `@mb 40` → `@ih 150`. All `viewBox="0 0 600 200"`. Grid lines `#F3F4F6`, axis labels `#9CA3AF`. Bars use `rx="3"` and `opacity="0.9"`.

---

## Task 4: Yahoo resilience in SilverBuilder

**File:** `lib/stock_plan/ingestion/silver_builder.ex`

- [x] 4.1 Wrap `StockPrice.get_close/2` calls for sale_price in `try/rescue`.
- [x] 4.2 Emit `Logger.warning/1` on Yahoo exceptions; store `nil` sale_price and proceed.
- [x] 4.3 Add `require Logger` to module.

---

## Task 5: HistoryLive

**File:** `lib/stock_plan_web/live/history_live.ex`

- [x] 5.1 Replace stub with full LiveView.
- [x] 5.2 `mount/3`: assigns `last_upload_at`, `symbols`, `active_symbol`, `active_plan`, `analysis`, `prices`, `prices_fetched_at`, `currency` (default "INR"), `qual_open` (default false).
- [x] 5.3 `handle_event("select_symbol", ...)` — switches symbol; preserves active_plan if that plan has data, otherwise defaults.
- [x] 5.4 `handle_event("select_plan", ...)` — RSU / ESPP tab switch.
- [x] 5.5 `handle_event("toggle_currency", %{"currency" => currency}, ...)` — two-button pattern (explicit currency value, not a flip).
- [x] 5.6 `handle_event("toggle_qual", ...)` — toggle qualifying/disqualifying section.
- [x] 5.7 No-data render: alert with link to `/upload` when `active_symbol == nil`.
- [x] 5.8 Page header: h1 + INR|USD two-button toggle.
- [x] 5.9 Info bar: left = symbol (dropdown if multi-symbol) + current price + ℹ️ DaisyUI tooltip (`data-tip="Price as of [datetime]"`); right = "Data last updated [datetime]" + "↑ Upload" link.
- [x] 5.10 Plan tabs: RSU | ESPP tab strip.
- [x] 5.11 RSU section (legacy — superseded by **Task 13** §G): old 7-tile + bar + tax + counterfactual + velocity + YoY layout.
- [x] 5.12 ESPP section: summary tiles (all 9, all currency-aware), lots table, sold pnl_bar_chart, unsold cost_basis_chart, sell-on-purchase analysis, qualifying/disqualifying collapsible.
- [x] 5.13 `espp_sop_analysis/2` — currency-aware private helper; reads `_inr` or `_usd` variants; computes day1_gain, extra, total_pnl, holding_better.
- [x] 5.14 `fmt_signed/2` — currency-aware signed formatter: `"+₹1,23,456"` / `"+$1234"`.
- [x] 5.15 `fmt_datetime/1`, `fmt_price/1`, `fmt_inr_num/1`, `fmt_indian_number/1` helpers.
- [x] 5.16 Internal `tile/1` component (stat tile with optional pnl color).

---

## Task 6: Tests

**Files:** `test/stock_plan/history_test.exs`, `test/stock_plan_web/live/history_live_test.exs`

- [x] 6.1 History context unit tests — compute functions with fixtures.
- [x] 6.2 XIRR correctness tests.
- [x] 6.3 LiveView mount test — empty DB shows no-data state.
- [x] 6.4 LiveView mount test — with data, all sections render.
- [x] 6.5 Currency toggle test — switching INR ↔ USD updates monetary cells.
- [x] 6.6 Symbol select test — dropdown switches per-symbol data.
- [x] 6.7 `mix test` all pass (run `--max-cases 1` to avoid SQLite contention in CI).

---

---

## Task 7: ESPP BH-only mode — sold qty without G&L

**Files:** `lib/stock_plan/ingestion/silver_builder.ex`, `lib/stock_plan/history.ex`

- [ ] 7.1 **SilverBuilder**: Add `purchase_date` to ESPP Sale `metadata_json` at BH ingestion time. `purchase_date` = the Purchase parent row's `Purchase Date` (= the tranche `vest_date` for that lot). Allows History to match sales to tranches without a schema change.
- [ ] 7.2 **History**: Change `compute_espp_analysis/6` to accept sales (remove underscore). Filter to `espp_sales` and pass to `build_espp_lots`.
- [ ] 7.3 **History**: Change `build_espp_lots/4` → `build_espp_lots/5` (add `bh_sales`). When `allocs_by_tranche[t.id]` is empty, fall back to `bh_sold_qty_for_tranche/3`.
- [ ] 7.4 **History**: Add `bh_sold_qty_for_tranche(sales, origin_id, purchase_date)` — filters sales by `origin_id` and `metadata_json["purchase_date"]`, sums `total_quantity`.
- [ ] 7.5 **History**: Add `parse_purchase_date_from_metadata/1` — parses `metadata_json` JSON; returns `Date.t()` or nil.
- [ ] 7.6 BH-only behaviour: `sold_qty` filled, `realized_pnl` nil, `held_qty` correct, `unrealized_pnl` computed. Uploading G&L later switches to alloc path automatically (no code change needed).
- [ ] 7.7 `mix compile --warnings-as-errors` and `mix test --max-cases 1` pass.

---

---

## Task 8: `net_buy_price` at ingestion

**File:** `lib/stock_plan/ingestion/silver_builder.ex`

- [x] 8.1 In the ESPP tranche insert, compute `net_buy_price = (buy_price × gross) / net` when `net > 0`; fallback to `buy_price` when `gross == net` or either value is missing.
- [x] 8.2 Persist `net_buy_price` as a string in `metadata_json` alongside existing `buy_price`.
- [x] 8.3 `mix compile --warnings-as-errors` passes.

---

## Task 9: History context — `net_buy_price` P&L and summary v2

**File:** `lib/stock_plan/history.ex`

- [x] 9.1 In `build_espp_lots/4`: read `net_buy_price` from `tranche.metadata_json["net_buy_price"]`; fallback: compute from gross/net/buy when key absent (old ingestions).
- [x] 9.2 Update `realized_pnl` formula: `(sale_price − net_buy_price) × sold_qty` (was `buy_price`).
- [x] 9.3 Update `pnl_pct` formula: `realized_pnl / (net_buy_price × sold_qty) × 100`.
- [x] 9.4 Update `unrealized_pnl` formula: `(current_price − net_buy_price) × held_qty`.
- [x] 9.5 Rename `total_discount_*` fields → `net_discount_*`; update formula to `× net_shares` (was `× gross_shares`).
- [x] 9.6 Add `realized_proceeds_usd/inr` to summary: `Σ(sale_price × sold_qty)`.
- [x] 9.7 Add `total_pnl_usd/inr` to summary: `realized_pnl + unrealized_pnl`.
- [x] 9.8 Add `total_return_pct` to summary: `total_pnl / purchase_value × 100`.
- [x] 9.9 `mix compile --warnings-as-errors` passes.

---

## Task 10: Chart updates (§C % primary, §D no polyline, §E density)

**File:** `lib/stock_plan_web/components/charts.ex`

- [x] 10.1 Extract `chart_layout/2` shared helper returning `%{svg_width, slot, label_indices, label_format, bar_bw, dot_r}`. Both `pnl_bar_chart` and `cost_basis_chart` consume it.
- [x] 10.2 `pnl_bar_chart`: Y-axis = return % (refactor `build_pnl_bars` to scale by `pnl_pct`). Y ticks as `%`. Dynamic svg width from `chart_layout`. Label thinning. Hover SVG `<title>` with proceeds, $ P&L, %.
- [x] 10.3 `cost_basis_chart` (open lots chart): dots at `net_buy_price` (not `buy_price`). Remove connecting polyline. Hover with unrealized $ and %. Dynamic svg width from `chart_layout`.
- [x] 10.4 Add solid X + Y axis lines to both charts.
- [x] 10.5 `mix compile --warnings-as-errors` passes.

---

## Task 11: HistoryLive updates (summary v2, scroll/expand, disclaimer)

**File:** `lib/stock_plan_web/live/history_live.ex`

- [x] 11.1 Add `:espp_lots_expanded` assign (default `false`).
- [x] 11.2 Add `handle_event("toggle_espp_lots_table", ...)` — flips `:espp_lots_expanded`.
- [x] 11.3 Render ESPP summary as 3 rows + return strip (replace old 9-tile flat grid). Net Received tile gets DaisyUI tooltip showing `tax_withheld` share count.
- [x] 11.4 Purchase lots table: remove Lookback column; add Buy Price header tooltip; add scroll + expand UI (`max-height` on collapsed; footer with count + expand button; collapse button when expanded).
- [x] 11.5 Wrap `pnl_bar_chart` and `cost_basis_chart` SVG in `overflow-x: auto` container; pass `svg_width` from `chart_layout` as explicit `width` attribute when > 600.
- [x] 11.6 Add ESPP tab footer disclaimer (muted text below qualifying/disqualifying).
- [x] 11.7 Update `espp_sop_analysis/2` to use `total_pnl_usd/inr` from summary (already computed) rather than recomputing from lots.
- [x] 11.8 `mix compile --warnings-as-errors` passes.

---

## Task 12: Updated tests

**Files:** `test/stock_plan/history_test.exs`, `test/stock_plan_web/live/history_live_test.exs`

- [x] 12.1 `net_buy_price` ingestion: tranche with `gross != net` stores correct value in metadata; tranche with `gross == net` stores `buy_price` as fallback.
- [x] 12.2 History lots: `realized_pnl`, `pnl_pct`, `unrealized_pnl` all use `net_buy_price` basis.
- [x] 12.3 History summary: `net_discount_usd` uses `× net_shares`; `realized_proceeds_usd` present; `total_pnl_usd` = `realized + unrealized`.
- [x] 12.4 History summary: `total_return_pct = total_pnl / purchase_value × 100`.
- [x] 12.5 LiveView ESPP tab: scroll/expand toggle — collapsed default; "Show all" expands; "Collapse" restores.
- [x] 12.6 LiveView ESPP tab: footer disclaimer text visible.
- [x] 12.7 Chart tests: `pnl_bar_chart` with `n=20` → `svg_width > 600`; label count thinned. `cost_basis_chart` with `n=20` → same.
- [x] 12.8 `mix test --max-cases 1` — M24 tests pass (8 pre-existing M22 failures unrelated to M24).

---

## Task 13: RSU tab refactor (§G income lens)

**Refs:** `cursor-feedback-on-specs.md` §G · `requirements.md` §2 · `m24-rsu-history.canvas.tsx` · `ux-design.md` RSU section

**Files:** `lib/stock_plan/history.ex`, `lib/stock_plan_web/live/history_live.ex`, `lib/stock_plan_web/components/charts.ex` (if `line_chart` extended), tests

### History context

- [x] 13.1 Refactor `compute_rsu_summary/4` — new fields per `design.md` §G.1 (drop total_sold, currently_held, realized_proceeds from summary); add `still_to_vest`, `unvested_gross_shares`, `vest_vs_grant_drift_pct`.
- [x] 13.2 Add `compute_grants_by_year/1` — `[%{{year, value_usd, value_inr}}]` from origins grouped by grant year.
- [x] 13.3 Refactor `compute_grant_rows/3` — columns: grant_promise, recognized, still_to_vest, vs_promise_pct only; remove sold_qty, realized_proceeds, unrealized_value, return_pct.
- [x] 13.4 Remove from `History.build/1` RSU output: `tax_paid_by_year`, `counterfactual`, `velocity`, `yoy`; rename `cumulative_income_by_year` → `income_by_year`.
- [x] 13.5 `still_to_vest` = `Σ vest_quantity` UNVESTED × `current_price` — nil when no price (UI-only projection).

### Charts + LiveView

- [x] 13.6 Add or extend `line_chart` component — categories + series + optional area fill; currency-aware Y labels (for RSU $ charts).
- [x] 13.7 RSU section order: summary → vest income by year line → grant table → grant FMV line → disclaimer.
- [x] 13.8 Summary: 2 rows × 7 `HintStat` tiles with DaisyUI/`title` tooltips on every label.
- [x] 13.9 Grant table: sort grant date desc; 5-row default + scroll + `toggle_rsu_grants_table` expand (mirror ESPP §B).
- [x] 13.10 Remove RSU renders: tax withheld bar, counterfactual card, velocity bar, YoY line, old cumulative bar chart.

### Tests

- [x] 13.11 Update `history_test.exs` + `history_live_test.exs` per `test-plan.md` RSU sections.
- [x] 13.12 `mix test --max-cases 1` pass.

---

## Deferred (not in M24)

- RSU post-vest sold/hold analytics (requires G&L + `sale_allocations`)
- Combined cross-symbol view (`"_combined"` aggregation)
- Per-chart insight text ("You earned ₹X in {year}, highest on record")
- Chart abbreviated Y-axis labels (₹12L, ₹1.2Cr)
- Multi-symbol stacked bar charts (infrastructure exists but LiveView doesn't use them)
