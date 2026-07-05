# Tasks: M14b — Schedule FSI

## Prerequisites

- M14: Capital Gains context (provides STCG/LTCG data)

---

## Milestone 1: Schedule FSI Context

**File:** `lib/stock_plan/tax/schedule_fsi.ex`

- [ ] 1.1 Create `StockPlan.Tax.ScheduleFSI` module
- [ ] 1.2 `build(account_id, fy_start_year)` — returns FSI data structure
- [ ] 1.3 Capital Gains head: pull from CapitalGains.build summary
- [ ] 1.4 Other heads: placeholder values (nil / user_to_populate)
- [ ] 1.5 `to_csv(fsi_data)` — generate downloadable CSV
- [ ] 1.6 Write tests
- [ ] 1.7 `mix test` — pass

## Milestone 2: Tax Centre UI — Third Tab

**File:** `lib/stock_plan_web/live/tax_centre_live.ex`

- [ ] 2.1 Add "Schedule FSI" tab to Tax Centre
- [ ] 2.2 FY selector (shared with Capital Gains)
- [ ] 2.3 FSI preview table with all 4 heads
- [ ] 2.4 Capital Gains row: show STCG/LTCG breakdown
- [ ] 2.5 "User to populate" fields styled distinctly
- [ ] 2.6 Download CSV button
- [ ] 2.7 Note about tax payable requiring tax advisor
- [ ] 2.8 Manual test in browser

## Milestone 3: Verification

- [ ] 3.1 `mix format --check-formatted`
- [ ] 3.2 `mix compile --warnings-as-errors`
- [ ] 3.3 `mix test` — all pass
- [ ] 3.4 Manual: User 3 — FSI shows CG from G&L data
- [ ] 3.5 Manual: CSV download opens correctly
- [ ] 3.6 Manual: FY selector works

## Definition of Done

- [ ] Schedule FSI generates for selected FY
- [ ] Capital Gains populated from existing CG context
- [ ] Salary/House Property correctly shown as not applicable
- [ ] Dividends: ₹0 with note
- [ ] "User to populate" for fields requiring manual input
- [ ] CSV download works
- [ ] Third tab on Tax Centre
- [ ] All tests pass
