# Test Plan: M10 Portfolio View — UX Rewrite

---

## TP-1: Hierarchical Data (Unit — Automated)

**File:** `test/stock_plan/portfolio_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Build returns grouped by plan_type | Keys include "ESPP" and "RSU" |
| TP-1.2 | ESPP origin group has origin_fmv | Lock-in price populated |
| TP-1.3 | ESPP origin group has discount_percent | From metadata |
| TP-1.4 | RSU origin group has total_quantity | Granted qty from origin |
| TP-1.5 | Origin tranches sorted ascending | Oldest vest_date first |
| TP-1.6 | Origins sorted ascending by date | Oldest origin_date first |
| TP-1.7 | Pre-computed summaries correct | vested_qty, unvested_qty match tranche data |
| TP-1.8 | Empty account returns empty map | %{"ESPP" => [], "RSU" => []} |

## TP-2: Number Formatting (Unit — Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Positive USD | `$1,234.56` |
| TP-2.2 | Negative USD | `-$1,234.56` |
| TP-2.3 | Positive INR | `₹1,234.56` |
| TP-2.4 | Negative INR | `-₹1,234.56` |
| TP-2.5 | Nil value | `—` |
| TP-2.6 | Zero value | `$0.00` |
| TP-2.7 | Large number | `$1,234,567.89` |

## TP-3: Tabs (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | Default tab | "By Type" is active with underline |
| TP-3.2 | Click "By Status" | Tab switches, content changes to flat view |
| TP-3.3 | Click back "By Type" | Returns to hierarchical view |

## TP-4: Filter Chips (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | Default state | Vested + Unvested active (colored), Profit + Loss inactive (bordered outline) |
| TP-4.2 | Toggle Unvested off | Only vested rows shown, chip becomes bordered |
| TP-4.3 | All filtered out | Section shows "No matching holdings" |

## TP-5: Header (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Company info | "Adobe (ADBE) $XXX.XX" visible in header |
| TP-5.2 | FX rate | "1 USD = ₹XX.XX" visible near currency toggle |
| TP-5.3 | INR toggle | Values convert, FX rate shown |

## TP-6: ESPP Hierarchy (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | ESPP section header | "Employee Stock Purchase Plan (ESPP)" with summary stats |
| TP-6.2 | Level 1: enrollment rows | Shows Grant Date (not hash), Lock-In Price, Qty, Value, P&L |
| TP-6.3 | Collapsed by default | Only Level 1 rows visible, chevron ▸ |
| TP-6.4 | Click to expand | Purchase rows appear, chevron ▾ |
| TP-6.5 | Level 2: purchase rows | Purchase Date, Purchase FMV, Qty, Sellable, Value |
| TP-6.6 | Click to collapse | Purchase rows hidden |
| TP-6.7 | No ESPP data | Section shows "No current holdings" |

## TP-7: RSU Hierarchy (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | RSU section header | "Restricted Stock (RS)" with vested/unvested counts |
| TP-7.2 | Level 1: grant rows | Grant#, Date, Granted, Vested, Unvested, Value, Potential, P&L |
| TP-7.3 | Collapsed by default | Only grant rows visible |
| TP-7.4 | Click to expand | Tranche rows appear |
| TP-7.5 | Level 2: tranche rows | Vest #, Date, Qty, Sellable, Cost Basis |
| TP-7.6 | Unvested values | Styled italic/lighter, labeled "Potential" |
| TP-7.7 | Sort order | Grants ascending, tranches ascending |
| TP-7.8 | No RSU data | Section shows "No current holdings" |

## TP-8: Formatting (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.1 | Negative P&L in USD | Shows `-$1,234.56` not `$-1234.56` |
| TP-8.2 | Negative P&L in INR | Shows `-₹1,234.56` not `₹-1234.56` |
| TP-8.3 | Large values | Commas: `$12,190.00` not `$12190` |

## TP-9: By Status View (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-9.1 | Switch to By Status | Flat table, no hierarchy |
| TP-9.2 | Sections | VESTED → UNVESTED grouping |
| TP-9.3 | Sort | vest_date ascending within each group |

## TP-10: Edge Cases (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-10.1 | No Holdings uploaded | Empty portfolio with upload prompt |
| TP-10.2 | Only RSU, no ESPP | ESPP stub visible with "No current holdings" |
| TP-10.3 | Filter hides all in section | "No matching holdings" message |
| TP-10.4 | Mobile viewport | Layout remains usable |

---

## Test Approach

- TP-1, TP-2: Automated (ExUnit)
- TP-3 through TP-10: Manual browser testing with SampleUser-3 data (BH + Holdings uploaded)

## Test Count: ~40 (10 automated, ~30 manual)
