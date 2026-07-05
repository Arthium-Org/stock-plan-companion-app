# Test Plan: M14 — Tax Centre (Phase 1)

---

## TP-1: Schedule FA Context (Automated)

**File:** `test/stock_plan/tax/schedule_fa_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Build FA for year with holdings | Returns non-empty list of FA rows |
| TP-1.2 | Row has required fields | date_acquired, initial_value_inr, peak_value_inr, closing_value_inr |
| TP-1.3 | Lot held all year | Included with full qty |
| TP-1.4 | Lot sold mid-year | Included with qty held before sale |
| TP-1.5 | Lot sold before Jan 1 | Excluded (not held during year) |
| TP-1.6 | Lot vested mid-year | Included from vest date onwards |
| TP-1.7 | Lot vested after Dec 31 | Excluded (not yet vested) |
| TP-1.8 | INR values use correct FX | vest_fx_rate for initial, dec31_fx for closing |
| TP-1.9 | Empty account | Returns [] |
| TP-1.10 | No BH data | Returns [] |

## TP-2: Capital Gains Context (Automated)

**File:** `test/stock_plan/tax/capital_gains_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Build CG for FY with sales | Returns {rows, summary} |
| TP-2.2 | STCG classification | Holding ≤ 24 months → :STCG |
| TP-2.3 | LTCG classification | Holding > 24 months → :LTCG |
| TP-2.4 | Holding period exact | Uses month comparison, not 730 days |
| TP-2.5 | Gain calculation USD | proceeds - cost_basis correct |
| TP-2.6 | Gain calculation INR | Uses vest_fx_rate and sale_fx_rate |
| TP-2.7 | Loss (negative gain) | Correctly computed as negative |
| TP-2.8 | Sale without allocation | Included with gain_type = :unknown |
| TP-2.9 | Summary totals | STCG + LTCG + unknown = net |
| TP-2.10 | FY boundary | Sale on Mar 31 included, Apr 1 excluded |
| TP-2.11 | No sales in FY | Returns {[], zero_summary} |
| TP-2.12 | Missing vest_fmv | Uses vest_day_close, source = :market_close |

## TP-3: Tax Centre LiveView (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | GET /tax | 200, page loads with tabs |
| TP-3.2 | Default tab | Schedule FA active |
| TP-3.3 | Switch to Capital Gains | Tab changes, CG data loads |
| TP-3.4 | Year selector (FA) | Dropdown works, data refreshes |
| TP-3.5 | FY selector (CG) | Dropdown works, data refreshes |

## TP-4: Schedule FA Display (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | Preview table | Rows with correct columns |
| TP-4.2 | INR values | Formatted with ₹ and commas |
| TP-4.3 | Year with no holdings | "No foreign assets for this year" |
| TP-4.4 | Multiple plan types | RSU + ESPP lots shown |

## TP-5: Capital Gains Display (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Summary cards | STCG, LTCG, Net with correct values |
| TP-5.2 | Detail table | Per-lot rows with all columns |
| TP-5.3 | STCG/LTCG labels | Correct classification per row |
| TP-5.4 | Unknown lot | Warning row for unallocated sales |
| TP-5.5 | FY with no sales | "No capital gains for this FY" |
| TP-5.6 | Currency toggle | USD ↔ INR works |

## TP-6: CSV Download (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Click download | File downloads |
| TP-6.2 | File name | `Schedule_FA_{year}.csv` |
| TP-6.3 | Open in Excel | Columns align, INR values correct |
| TP-6.4 | Empty year | File with headers only |

## TP-7: Multi-User (Manual Browser)

| Test ID | User | Assertion |
|---|---|---|
| TP-7.1 | User 1 (BH + G&L 2023-2025) | CG for FY 2024-25 shows gains |
| TP-7.2 | User 1 | Schedule FA for 2024 shows lots |
| TP-7.3 | User 3 (BH, no G&L) | CG empty or "Lot unknown" warnings |
| TP-7.4 | No BH uploaded | Both tabs show empty state |

---

## Test Approach

- TP-1, TP-2: Automated (DataCase) — use SampleUser-1 data (has G&L)
- TP-3 through TP-7: Manual browser testing
- Test with User 1 (most complete sell data) as primary

## Test Count: ~35 (12 automated, ~23 manual)
