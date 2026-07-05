# Tasks: M14 — Tax Centre (Phase 1)

## Prerequisites

- M5/M6: BH Silver + G&L ingestion (origins, tranches, sales, allocations)
- M7a: FX rates
- M7b: Stock prices

---

## Milestone 1: Schedule FA Context

**File:** `lib/stock_plan/tax/schedule_fa.ex`

- [ ] 1.1 Create `StockPlan.Tax.ScheduleFA` module
- [ ] 1.2 `build(account_id, calendar_year)` — returns list of FA rows
- [ ] 1.3 Query: tranches vested on or before Dec 31, joined with origins
- [ ] 1.4 Compute held_qty: net_quantity - sum(sale_allocations where sale_date ≤ Dec 31)
- [ ] 1.5 Skip lots fully sold before Jan 1
- [ ] 1.6 Initial value: cost_basis × qty × vest_fx_rate
- [ ] 1.7 Peak value: highest adjusted close during year × qty × peak_month_fx
- [ ] 1.8 Closing value: Dec 31 price × qty × Dec 31 fx
- [ ] 1.9 Handle missing vest_fmv (fallback to vest_day_close)
- [ ] 1.10 Write tests
- [ ] 1.11 `mix test` — pass

## Milestone 2: Capital Gains Context

**File:** `lib/stock_plan/tax/capital_gains.ex`

- [ ] 2.1 Create `StockPlan.Tax.CapitalGains` module
- [ ] 2.2 `build(account_id, fy_start_year)` — returns {rows, summary}
- [ ] 2.3 Query: sales in FY period (Apr 1 to Mar 31)
- [ ] 2.4 Join sale_allocations → tranches for lot-level detail
- [ ] 2.5 Per allocation: compute holding_days, STCG/LTCG classification
- [ ] 2.6 Holding period: exact 24-month comparison (not 730 days)
- [ ] 2.7 Cost basis INR: cost_basis_per_share × qty × vest_fx_rate
- [ ] 2.8 Proceeds INR: sale_price × qty × sale_fx_rate
- [ ] 2.9 Gain/loss in both USD and INR
- [ ] 2.10 Sales without allocations: include with gain_type = :unknown
- [ ] 2.11 Compute summary: total STCG, LTCG, net (USD + INR)
- [ ] 2.12 Write tests
- [ ] 2.13 `mix test` — pass

## Milestone 3: Tax Centre LiveView

**File:** `lib/stock_plan_web/live/tax_centre_live.ex`

- [ ] 3.1 Replace placeholder TaxCentreLive with real implementation
- [ ] 3.2 Mount: default to current calendar year (FA) and current FY (CG)
- [ ] 3.3 Two tabs: Schedule FA / Capital Gains
- [ ] 3.4 Year selectors (dropdown)
- [ ] 3.5 Lazy load: compute data on tab switch / year change (not on mount)

### Schedule FA Tab
- [ ] 3.6 Preview table: rows from ScheduleFA.build
- [ ] 3.7 Columns: Grant#, Type, Acquired, Qty, Initial (INR), Peak (INR), Closing (INR)
- [ ] 3.8 Download CSV button

### Capital Gains Tab
- [ ] 3.9 Summary cards: STCG, LTCG, Net (USD + INR toggle)
- [ ] 3.10 Detail table: Sale Date, Grant#, Vest Date, Qty, Sale Price, Cost Basis, Days, Type, Gain (USD/INR)
- [ ] 3.11 Sales without lot detail: show warning row
- [ ] 3.12 Currency toggle (shared with Portfolio)

## Milestone 4: CSV Download

- [ ] 4.1 Generate CSV from Schedule FA data
- [ ] 4.2 Column headers matching ITR Schedule FA format
- [ ] 4.3 Serve via LiveView download or controller endpoint
- [ ] 4.4 Filename: `Schedule_FA_{year}.csv`

## Milestone 5: Verification

- [ ] 5.1 `mix format --check-formatted`
- [ ] 5.2 `mix compile --warnings-as-errors`
- [ ] 5.3 `mix test` — all pass
- [ ] 5.4 Manual test: User 1 (has G&L 2023-2025) — capital gains for FY 2024-25
- [ ] 5.5 Manual test: User 1 — Schedule FA for 2024
- [ ] 5.6 Manual test: User 3 — no G&L, empty capital gains
- [ ] 5.7 Manual test: CSV download opens correctly in Excel
- [ ] 5.8 Manual test: INR values match expected (FX rate × USD)

---

## Definition of Done

- [ ] Schedule FA generates per-lot disclosure for a calendar year
- [ ] Capital gains computes STCG/LTCG per lot for a financial year
- [ ] LiveView with tabs, year selectors, preview tables
- [ ] CSV download for Schedule FA
- [ ] Indian tax rules: 24-month LTCG threshold, SBI TT buying rate
- [ ] Sales without lot allocation show warning (not fabricated)
- [ ] All tests pass
