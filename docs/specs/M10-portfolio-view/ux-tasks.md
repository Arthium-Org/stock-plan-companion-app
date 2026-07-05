# Tasks: M10 Portfolio View — UX Rewrite

## Prerequisites

- M3b: Holdings ingestion complete (sellable_qty, cost_basis_broker on tranches)
- FX seed data loaded
- Sample data ingested (BH + Holdings)

---

## Milestone 1: Backend — Hierarchical Portfolio Data

**File:** `lib/stock_plan/portfolio.ex`

- [ ] 1.1 Restructure `build/1` to return `%{"ESPP" => [origin_groups], "RSU" => [origin_groups]}`
- [ ] 1.2 Each origin group includes: origin fields + pre-computed summaries + nested tranches
- [ ] 1.3 Extract ESPP origin-level: origin_fmv (lock-in price), discount_percent from metadata
- [ ] 1.4 Extract RSU origin-level: total_quantity, grant_number
- [ ] 1.5 Compute per-origin: total_qty, vested_qty, unvested_qty, vested_count, unvested_count
- [ ] 1.6 ESPP total_qty computed from tranche sum (origin.total_quantity is nil)
- [ ] 1.7 Sort origins by origin_date ascending within each plan_type
- [ ] 1.8 Sort tranches by vest_date ascending within each origin
- [ ] 1.9 Add `flat_holdings/1` helper that flattens hierarchical data for compute_summary
- [ ] 1.10 Update `compute_summary/2` if needed
- [ ] 1.11 `mix test` — all pass
- [ ] 1.12 `mix compile --warnings-as-errors`

## Milestone 2: Number Formatting Helpers

**File:** `lib/stock_plan_web/live/portfolio_live.ex`

- [ ] 2.1 Implement `format_number/1` — comma-separated thousands, 2 decimal places
- [ ] 2.2 Rewrite `format_currency/2` — sign before symbol (`-$1,234.56` not `$-1,234.56`)
- [ ] 2.3 Handle nil → "—", zero, no-decimal-part edge cases
- [ ] 2.4 Manual test: verify `-₹1,19,184.40` renders correctly

## Milestone 3: Header, Tabs, Filters

**File:** `lib/stock_plan_web/live/portfolio_live.ex`

- [ ] 3.1 Header: "Adobe (ADBE) $XXX.XX" prominently displayed
- [ ] 3.2 FX rate: "1 USD = ₹XX.XX" near currency toggle
- [ ] 3.3 Replace toggle buttons with DaisyUI `tabs tabs-bordered`
- [ ] 3.4 Rename assign `group_by` → `active_tab` (or keep, just change UI)
- [ ] 3.5 Filter chips: `btn-outline` for inactive instead of `btn-ghost`
- [ ] 3.6 Manual test in browser

## Milestone 4: Collapsible ESPP Hierarchy

**File:** `lib/stock_plan_web/live/portfolio_live.ex`

- [ ] 4.1 Add `@expanded_origins` assign (MapSet, default empty)
- [ ] 4.2 Add `"toggle_expand"` event handler with `phx-value-origin-id`
- [ ] 4.3 ESPP section header: "Employee Stock Purchase Plan (ESPP)" + summary
- [ ] 4.4 Level 1 rows: enrollment origin_date (NOT hash), lock-in price, qty, value, P&L
- [ ] 4.5 Level 2 rows (on expand): purchase date, cost basis (FMV), qty, sellable, market value
- [ ] 4.6 Chevron icon: ▸ collapsed / ▾ expanded
- [ ] 4.7 Empty state: "No current holdings" when no ESPP data
- [ ] 4.8 Manual test in browser: expand/collapse works

## Milestone 5: Collapsible RSU Hierarchy

**File:** `lib/stock_plan_web/live/portfolio_live.ex`

- [ ] 5.1 RSU section header: "Restricted Stock (RS)" + summary (vested/unvested counts, values)
- [ ] 5.2 Level 1 rows: grant number, date, granted qty, vested, unvested, value, potential, P&L
- [ ] 5.3 Level 2 rows (on expand): vest period #, vest date, vest qty, sellable qty, cost basis
- [ ] 5.4 Unvested values: italic, lighter text, labeled "Potential"
- [ ] 5.5 Sort: grants ascending by date, tranches ascending by vest_date
- [ ] 5.6 Empty state: "No current holdings" when no RSU data
- [ ] 5.7 Manual test in browser

## Milestone 6: By Status View + Final Polish

**File:** `lib/stock_plan_web/live/portfolio_live.ex`

- [ ] 6.1 "By Status" tab: flat table grouped by VESTED → UNVESTED (no hierarchy)
- [ ] 6.2 Ascending sort by vest_date within each status group
- [ ] 6.3 Filters work: hiding all tranches in a section → "No matching holdings"
- [ ] 6.4 Summary cards update correctly with filters
- [ ] 6.5 Mobile responsive check
- [ ] 6.6 `mix format --check-formatted`
- [ ] 6.7 `mix compile --warnings-as-errors`
- [ ] 6.8 `mix test` — all pass
- [ ] 6.9 Full browser test with SampleUser-3 data

---

## Definition of Done

- [ ] All 10 UX issues resolved
- [ ] Collapsible hierarchy for both ESPP and RSU
- [ ] Number formatting with commas and correct negative sign
- [ ] Company name + price in header
- [ ] FX rate displayed
- [ ] Tabs and bordered filter chips
- [ ] ESPP shows Grant Date not hash
- [ ] Consistent ascending sort
- [ ] Unvested styled as "Potential"
- [ ] Empty section stubs always visible
- [ ] Both "By Type" and "By Status" views work
- [ ] All tests pass
