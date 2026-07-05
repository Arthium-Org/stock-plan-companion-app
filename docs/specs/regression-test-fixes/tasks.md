# Tasks — Regression Test Fixes

## Fix 1: Schedule FA graceful degradation (FA-1)

**File:** `lib/stock_plan/tax/schedule_fa.ex`

- [ ] 1.1 Read `TrancheTimeline.validate_cy_coverage/3` to confirm the exact `{:error, _}` shape (string or structured tuple).
- [ ] 1.2 Add private `format_gl_warning/2` helper that takes uncovered dates + year, returns a human-readable string.
- [ ] 1.3 In `build/2`: replace `{:error, msg} → {:error, msg}` arm with `{:error, _} → {:ok, rows, [warning | validation.warnings]}`. Still runs `build_fa_rows_from_timeline` + `aggregate_by_date` so available rows (tranches with no sale in the covered gap) are returned.
- [ ] 1.4 `mix compile --warnings-as-errors` passes.
- [ ] 1.5 Test with u3 account: `ScheduleFA.build("u3", 2024)` returns `{:ok, rows, [warning]}` where warning mentions the uncovered 2024 sale dates.

---

## Fix 2: Capital Gains — skip uncovered FY (CG-1)

**File:** `lib/stock_plan/tax/capital_gains.ex`

- [ ] 2.1 Add `warning: nil` to `zero_summary/0`.
- [ ] 2.2 After `fetch_allocations`, split sales into `covered_sales` (have at least one allocation) and `uncovered_sales`.
- [ ] 2.3 If `covered_sales == []`: return `{[], %{zero_summary() | warning: warning_string}}` without building any rows.
- [ ] 2.4 If mixed: build rows from `covered_sales` only; add `warning` to summary listing the uncovered sale dates.
- [ ] 2.5 If all covered: current behaviour; `warning: nil` added to summary (no-op for UI).
- [ ] 2.6 Update LiveView `tax_centre_live.ex` to render `@capital_gains_summary.warning` as an inline alert above the CG table when non-nil.
- [ ] 2.7 `mix compile --warnings-as-errors` passes.
- [ ] 2.8 Test with u1: `CapitalGains.build("u1", 2024)` returns `{[], summary}` where `summary.warning` lists all uncovered sale dates.
- [ ] 2.9 Test with u3: FY2024 returns `{[], summary}` with warning (no 2024 G&L); FY2025 returns rows normally with `warning: nil`.

---

## Fix 3: Sell Advisor early-exit (SA-2)

**File:** `lib/stock_plan/tax/sell_advisor_v2.ex`

- [ ] 3.1 Extract `explicit_symbol = Keyword.get(opts, :symbol)` at top of `advise/3`.
- [ ] 3.2 Call `lots_check = SellAdvisor.load_sellable_lots(account_id, explicit_symbol)` before any price fetch.
- [ ] 3.3 If `lots_check == []`, return `{:error, :no_sellable_lots}` immediately.
- [ ] 3.4 In the existing `with` body, replace the `load_sellable_lots` call with `lots_check` (already loaded — avoid double query).
- [ ] 3.5 `mix compile --warnings-as-errors` passes.
- [ ] 3.6 Test with u1: `SellAdvisorV2.advise("u1", {:shares, 10})` returns `{:error, :no_sellable_lots}`.
- [ ] 3.7 Test with u3: `SellAdvisorV2.advise("u3", {:shares, 10})` still returns `{:ok, advice}` with baskets.
- [ ] 3.8 Confirm no Yahoo price fetch is made for u1 (check logs — no `StockPrice.current_price` call when no lots).

---

---

## Fix 4: Post-implementation corrections (from Cursor feedback review)

### D.2 — CG-1 coverage check: verify `sale_price IS NOT NULL`

**File:** `lib/stock_plan/tax/capital_gains.ex`

- [x] 4.1 Coverage check must verify that at least one allocation has `a.sale_price != nil` (not just that any allocation exists). Update `covered_ids` filter to check `Enum.any?(alloc_list, fn a -> a.sale_price != nil end) || (sale != nil && sale.sale_price != nil)`.

### U.1 — FA warnings render in Tax Centre

**File:** `lib/stock_plan_web/live/tax_centre_live.ex`

- [x] 4.2 Render `@fa_warnings` loop ABOVE the FA `cond` block so warnings appear even when `@fa_data == []`.

### U.2 — FA empty state doesn't show contradictory copy

**File:** `lib/stock_plan_web/live/tax_centre_live.ex`

- [x] 4.3 Add `@fa_data == [] and @fa_warnings != []` branch in the `cond` block; render nothing (warnings already shown above).

### U.3 — Remove dead `unknown_count` warning banner

**File:** `lib/stock_plan_web/live/tax_centre_live.ex`

- [x] 4.4 Remove `unknown_count > 0` banner entirely — it was dead code after CG-1 moved to covered-only rows.

### FA-1 filter — Exclude unsalvageable sold rows in both arms

**File:** `lib/stock_plan/tax/schedule_fa.ex`

- [x] 4.5 After `aggregate_by_date(rows)` in **both** the `{:error, _msg}` arm and the `:ok` arm, filter out rows where both `closing_value_inr = 0` AND `sale_proceeds_inr = 0`. These are sold tranches where the timeline sell events have `price: nil` (G&L allocation exists but `sale_price` column is nil, e.g., multi-symbol account where only one symbol's G&L covers the sell date). They contribute no meaningful disclosure and violate the invariant "both=0 means row shouldn't exist".

---

## Fix 5: Run test suite

- [ ] 5.1 `mix test --max-cases 1` — all tests pass (except 3 pre-existing `ScheduleFATest` cross-validation failures caused by sample data gap for CY 2024, not scope of this fix).
- [ ] 5.2 Re-run regression script against all 5 users and confirm:
  - FA-1 resolved: `ScheduleFA.build("u3", 2024)` and `("u5", 2024)` return `{:ok, rows, [warning]}`.
  - CG-1 resolved: `CapitalGains.build("u1", 2024)` returns `{[], summary_with_warning}`.
  - SA-2 resolved: `SellAdvisorV2.advise("u1", {:shares, 10})` returns `{:error, :no_sellable_lots}`.
  - No regressions on u2, u3, u4 (those that were passing).
