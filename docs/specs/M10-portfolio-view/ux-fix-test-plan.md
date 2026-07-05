# Test Plan: M10 Portfolio — UX Fixes (Round 2)

---

## TP-A: Tranche Sub-Table (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-A.1 | Expand RSU grant | Tranche table is indented, has distinct background |
| TP-A.2 | Tranche columns | Own header row: #, Vest Date, Vest Qty, Released, Sellable, Cost Basis |
| TP-A.3 | Column alignment | Tranche columns do NOT align with grant columns above |
| TP-A.4 | Expand ESPP enrollment | Purchase sub-table similarly nested and indented |
| TP-A.5 | Collapse | Sub-table disappears cleanly |

## TP-B1: RSU Grant Row (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-B1.1 | Grant columns visible | Grant#, Date, FMV, Granted, Vested, Sellable, Unvested, Value, Potential, P&L |
| TP-B1.2 | Sellable count | Matches sum of sellable_qty from expanded tranches |
| TP-B1.3 | Grant FMV | Shows grant FMV value (not blank) |
| TP-B1.4 | Current Value math | Value = Sellable × current price (verifiable) |
| TP-B1.5 | Fully sold grant | Sellable = 0, not shown in portfolio |

## TP-B2: RSU Tranche Row (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-B2.1 | 3 qty columns | Vest Qty, Released Qty, Sellable all visible |
| TP-B2.2 | Vested tranche | All 3 fields populated |
| TP-B2.3 | Unvested tranche | Vest Qty shown, Released = "—", Sellable = "—" |
| TP-B2.4 | Vest period number | Actual period from data (not sequential) |

## TP-B3: ESPP Lock-In Price (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-B3.1 | Enrollment row | Lock-In Price shows value (e.g., $368.48) |
| TP-B3.2 | No $ prefix | Formatted as currency, not raw "$368.48" string |

## TP-B4: Unvested Sellable (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-B4.1 | Unvested tranche | Sellable column shows "—" |
| TP-B4.2 | Vested tranche | Sellable column shows number |

## TP-B5: RSU Section Summary (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-B5.1 | Summary text | Shows share quantities: "Vested: X shares (Y sellable)" |
| TP-B5.2 | Sellable count | Matches sum across all grant sellable values |

## TP-C: Summary Card (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-C.1 | Potential Value card | Shows unvested share count + tranche count |
| TP-C.2 | Format | "X shares (N vests)" or similar |

## TP-D: Filters (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-D.1 | Default | Vested ON, Unvested ON — all rows visible |
| TP-D.2 | Unvested OFF | Only vested grants/tranches shown |
| TP-D.3 | Vested OFF | Only unvested shown, grants without unvested hidden |
| TP-D.4 | Profit filter | Only grants with profit-making vested tranches shown |
| TP-D.5 | Loss filter | Only grants with loss-making vested tranches shown |
| TP-D.6 | Loss + Unvested | Loss vested + all unvested visible |
| TP-D.7 | All filtered out | "No matching holdings" message in section |
| TP-D.8 | Summary matches | Summary values match visible data |

## TP-E: Sorting (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-E.1 | Default | Grants sorted by date ascending |
| TP-E.2 | Click Grant Date | Toggles to descending |
| TP-E.3 | Click Value | Sorts by current value |
| TP-E.4 | Click P&L | Sorts by P&L |
| TP-E.5 | Sort indicator | Arrow visible on active column |
| TP-E.6 | Tranches unaffected | Stay chronological within grant |

## TP-F: Cross-User (Manual Browser)

| Test ID | User | Assertion |
|---|---|---|
| TP-F.1 | User 3 (ESPP+RSU) | All columns correct, sub-tables nested properly |
| TP-F.2 | User 2 (RSU only) | ESPP section shows "No current holdings" |
| TP-F.3 | User 1 (all sold) | Empty portfolio with BH fallback |
| TP-F.4 | INR toggle | All values convert, commas, negative sign before ₹ |

---

## Test Approach

- All tests are manual browser testing
- Test with real sample data per user DB
- Verify with both USD and INR modes

## Test Count: ~35 manual tests
