# Test Plan: M21 — Tranche Timeline Builder

---

## TP-1: Timeline Construction (Automated)

**File:** `test/stock_plan/tax/tranche_timeline_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Tranche with no sells | total_sold = 0, held_from_timeline = net_quantity |
| TP-1.2 | Tranche with 1 sell | total_sold = sell qty, held_from_timeline correct |
| TP-1.3 | Tranche with multiple sells | total_sold = sum, held_from_timeline correct |
| TP-1.4 | Holdings qty matches timeline | No V1 warning |
| TP-1.5 | ESPP tranche with G&L | Sells from G&L allocations (source: :gl) |
| TP-1.6 | ESPP tranche without G&L | Sells from BH quantity match (source: :bh) |
| TP-1.7 | RSU tranche timeline | Sells from G&L allocations only (source: :gl) |
| TP-1.8 | Invariant: total_sold <= net_quantity | For all tranches |

## TP-2: Validation V1 — Holdings vs Timeline (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | held_from_timeline matches holdings_qty | No warning |
| TP-2.2 | Timeline vs Holdings differs by > 1 | Warning: qty_mismatch |
| TP-2.3 | Timeline vs Holdings differs by ≤ 1 | No warning (tolerance) |
| TP-2.4 | No Holdings uploaded | V1 skipped (no comparison possible) |
| TP-2.5 | Fully sold tranche (holdings_qty=0, no sells) | No warning (expected) |

## TP-3: Validation V2 — G&L Coverage (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | No sells in CY | :ok (G&L not needed) |
| TP-3.2 | Sells in CY, G&L covers | :ok |
| TP-3.3 | Sells in CY, no G&L | {:error, "Upload G&L..."} |
| TP-3.4 | Sells in CY, G&L partial (gap) | {:error, missing dates} |

## TP-4: Validation V3 — No Gaps (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | All BH sales within G&L range have allocations | No warning |
| TP-4.2 | Some BH sales in range lack allocations | Warning |

## TP-5: CY Query (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Tranche held all year | held_at_start > 0, held_at_end > 0 |
| TP-5.2 | Tranche sold mid-year | held_at_start > 0, held_at_end = 0, sold > 0 |
| TP-5.3 | Tranche partially sold mid-year | held_at_end < held_at_start |
| TP-5.4 | Tranche sold before CY | Excluded (not held during CY) |
| TP-5.5 | Tranche vested mid-CY | Included from vest_date |
| TP-5.6 | Tranche vested after CY end | Excluded |

## TP-6: Schedule FA Integration (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | FA with timeline | Correct held quantities (not net_quantity) |
| TP-6.2 | FA excludes sold lots | Lots sold before CY not in output |
| TP-6.3 | FA shows partial-year lots | Sold mid-CY with closing = 0 |
| TP-6.4 | V2 error blocks FA | Returns {:error, message} |
| TP-6.5 | V1 warning passes FA | Returns {:ok, rows, warnings} |
| TP-6.6 | No FA row with both closing=0 AND sale_proceeds=0 | Invalid rows excluded |
| TP-6.7 | Every FA tranche in Holdings or G&L/BH | No orphan FA rows |

## TP-7: BH Sold Validation (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | Old RSU tranches (no G&L, no Holdings entry) | holdings_qty = 0 via BH validation |
| TP-7.2 | Old ESPP tranches matched by quantity | Sell date from BH, source: :bh |
| TP-7.3 | Tranches sold before CY excluded from FA | Not in held_during_cy |
| TP-7.4 | Per-origin invariant: held + sold = released | For all origins |
| TP-7.5 | No orphans (vested before 2025) | All accounted for |
| TP-7.6 | Holdings override: holdings_qty=0 + no sells | Excluded from FA |
| TP-7.7 | FA row count < total tranches | Old sold excluded |
| TP-7.8 | No pre-2017 tranches in CY 2024 FA | Very old sold excluded |
| TP-7.9 | Without Holdings: bh_sold == total_released → all sold | Fully sold origin detected |

## TP-8: Multi-User (Manual Browser)

| Test ID | User | Assertion |
|---|---|---|
| TP-8.1 | User 1 (all sold, no Holdings) | FA correct — old sold tranches excluded |
| TP-8.2 | User 3 (Holdings + G&L 2025-26) | FA correct for CY 2025 |
| TP-8.3 | User 4 (Holdings + G&L, old grants) | Old sold tranches excluded from FA |
| TP-8.4 | User 4 | ESPP closing values present (Holdings match works) |

---

## Test Approach

- TP-1 through TP-7: Automated (DataCase)
- TP-8: Manual browser testing
- Users: 1 (all sold, no Holdings), 3 (mixed), 4 (old grants, regression)

## Test Count: ~35 (30 automated, 5 manual)
