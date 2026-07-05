# Tasks: M21 — Tranche Timeline Builder

## Prerequisites

- M5b: Holdings Silver
- M14: Capital Gains (G&L allocations)
- BH Silver (origins, tranches, sales)

---

## Milestone 1: Timeline Builder Core ✅

**File:** `lib/stock_plan/tax/tranche_timeline.ex`

- [x] 1.1 Create `StockPlan.Tax.TrancheTimeline` module
- [x] 1.2 `build(account_id)` — load tranches + allocations + holdings + BH sales
- [x] 1.3 Build per-tranche timeline: vest event + sell events (from allocations) + current state (from holdings)
- [x] 1.4 Compute total_sold, held_from_timeline per tranche
- [x] 1.5 Sell sources: G&L allocations primary for both RSU and ESPP
- [x] 1.6 ESPP fallback: BH quantity match when no G&L allocation exists (date only, no price)

## Milestone 2: Validation ✅

- [x] 2.1 V1: Holdings vs Timeline quantity match per tranche (±1 tolerance)
- [x] 2.2 V2: G&L coverage check for a requested CY (per-date, RSU only)
- [x] 2.3 V3: No gaps — unallocated BH RSU sales within G&L date range
- [x] 2.4 Return structured validation result (errors + warnings)
- [x] 2.5 Write tests for each validation
- [x] 2.6 `mix test` — pass

## Milestone 3: CY Query ✅

- [x] 3.1 `held_during_cy(timelines, calendar_year)` — returns tranche states for CY
- [x] 3.2 Compute: held_at_start, held_at_end, sold_during_cy
- [x] 3.3 Filter: exclude tranches not held during CY
- [x] 3.4 Holdings override: holdings_qty=0 + no sells → excluded (sold before G&L coverage)
- [x] 3.5 Write tests with User 3 data (has Holdings + G&L)
- [x] 3.6 Write tests with User 1 data (no Holdings, all sold)
- [x] 3.7 `mix test` — pass

## Milestone 4: Schedule FA Integration ✅

- [x] 4.1 Update `ScheduleFA.build` to use TrancheTimeline
- [x] 4.2 V2 error → return `{:error, message}` (not empty data)
- [x] 4.3 Warnings → return `{:ok, rows, warnings}`
- [x] 4.4 Peak/closing values use held_qty from timeline (not net_quantity)
- [x] 4.5 Sale proceeds from sells_during_cy
- [x] 4.6 Aggregate same-date tranches into one FA row

## Milestone 5: Validation UI ✅

- [x] 5.1 Tax Centre: show validation errors before FA data
- [x] 5.2 Error: "Upload G&L for {CY}" message
- [x] 5.3 Warnings: banner above FA table

## Milestone 6: BH Sold Validation ✅

- [x] 6.1 Per-origin reconciliation: released vs BH sold vs G&L sold
- [x] 6.2 With Holdings: set holdings_qty=0 for tranches not in Holdings (BH confirmed)
- [x] 6.3 Without Holdings: fully sold if bh_sold == total_released
- [x] 6.4 ESPP quantity match in build_sells (BH fallback)
- [x] 6.5 ESPP grant_number hash consistency (ISO date format in both BH and Holdings)
- [x] 6.6 V1 suppression for expected case (holdings_qty=0, no sells)
- [x] 6.7 Regression tests for User 4 (old sold grants)

## Milestone 7: Timeline Summary (TODO)

- [ ] 7.1 `summary(timelines, bh_sales)` — per-symbol reconciliation
- [ ] 7.2 BH summary: total_released, total_sold, vested_unsold, unvested
- [ ] 7.3 Holdings summary: vested_held (if uploaded)
- [ ] 7.4 Reconciliation status: :reconciled | :holdings_needed | :error
- [ ] 7.5 Use summary to drive BH sold validation logic

## Milestone 8: Timeline View UI (TODO)

Reusable component with two modes. Hosts in History page + embeds in Upload page.

**Component:** `lib/stock_plan_web/components/timeline_view.ex`

### Summary mode (for upload page post-upload)

- [ ] 8.1 Per-symbol reconciliation card:
  - Released (from BH), Sold (G&L + BH), Held (from Holdings or derived)
  - Status badge: :reconciled / :holdings_needed / :error
- [ ] 8.2 Feature readiness indicators (green/yellow/red per feature)
- [ ] 8.3 Actionable nudges (structured: severity + reason + impact + action)
- [ ] 8.4 ESPP disclaimer where BH-matched sells appear: "Sell dates inferred from Benefit History"

### Detail mode (for History page)

- [ ] 8.5 Per-grant collapsible timeline:
  - Vest event: date, qty, FMV, source (BH)
  - Sell events: date, qty, price, source tag (:gl / :bh)
  - Current state: held qty (from Holdings or derived)
- [ ] 8.6 Filter by plan type (RSU / ESPP), symbol, grant
- [ ] 8.7 Validation warnings inline (V1 mismatches shown per grant)
- [ ] 8.8 "What's missing" section: V2 gaps, unmatched sells

### History page

- [ ] 8.9 `lib/stock_plan_web/live/history_live.ex` — first tab: Timeline View (detail mode)
- [ ] 8.10 Route: `/history` in router
- [ ] 8.11 Nav link in layout
- [ ] 8.12 Future tabs placeholder: Transaction Log, Dividend History

### Upload page integration

- [ ] 8.13 After upload completes, show timeline summary (summary mode)
- [x] 8.14 "View full timeline" link → `/history`
- [x] 8.15 Nudges update live as user uploads more files

## Milestone 9: Verification

- [x] 8.1 `mix compile` — 0 warnings
- [x] 8.2 `mix test` — all 415 pass
- [ ] 8.3 Manual: User 1 — FA correct (no Holdings, G&L covers sells)
- [x] 8.4 Manual: User 4 — old sold tranches excluded from FA
- [ ] 8.5 Manual: User 4 — ESPP Holdings matching works (closing values present)

---

## Definition of Done

- [x] Per-tranche timeline built from Holdings + G&L + BH
- [x] V1: Holdings vs Timeline quantity validation
- [x] V2: G&L coverage required for CY with sells
- [x] V3: No gaps in G&L allocation
- [x] BH sold validation: per-origin reconciliation
- [x] Schedule FA uses timeline for accurate held_qty
- [x] Sold lots correctly excluded
- [x] Validation errors shown in UI
- [x] All tests pass

## Invariants

```
For every tranche:
  held_from_timeline = net_quantity - total_sold
  total_sold <= net_quantity
  
  If Holdings exists for this tranche:
    held_from_timeline ≈ holdings_qty (±1)

Sell sources (no mixing within a tranche):
  G&L allocations → source: :gl (primary, both RSU and ESPP)
  BH quantity match → source: :bh (fallback, ESPP only)
  BH validation → no sell entry, sets holdings_qty = 0 (RSU + ESPP)
```
