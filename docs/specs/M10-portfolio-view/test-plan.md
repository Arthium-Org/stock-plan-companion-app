# Test Plan: M10 — Portfolio View (Revised)

---

## TP-1: Portfolio Context — Holdings Source (Unit — Automated)

**File:** `test/stock_plan/portfolio_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Build with Holdings-enriched RSU tranches | Returns holding rows with sellable_qty as quantity |
| TP-1.2 | Vested RSU: cost_basis from cost_basis_broker | Source = :broker (priority 1) |
| TP-1.3 | Vested RSU: fallback to vest_fmv | Source = :actual_fmv (priority 2) |
| TP-1.4 | Vested RSU: fallback to vest_day_close | Source = :market_close (priority 3) |
| TP-1.5 | Vested RSU: no cost basis available | Source = :unavailable, cost_basis = nil |
| TP-1.6 | ESPP: cost_basis from cost_basis_broker | Broker-reported cost basis |
| TP-1.7 | Tranche with sellable_qty = 0 | Excluded (fully sold per broker) |
| TP-1.8 | Unvested tranche (from BH) | Included with vest_quantity, no cost_basis |
| TP-1.9 | No Holdings data ingested | Returns [] |
| TP-1.10 | Tax status populated | "Long Term" or "Short Term" from Holdings |

## TP-2: Summary Computation (Unit — Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Current Value | sum(sellable_qty x price) for vested |
| TP-2.2 | Potential Value | sum(vest_quantity x price) for unvested |
| TP-2.3 | Total = Current + Potential | Correct |
| TP-2.4 | Breakdown by plan_type | RSU + ESPP subtotals correct |
| TP-2.5 | No Holdings data | All values = 0 |

## TP-3: Route (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | GET /portfolio (with data) | 200, contains "Portfolio" |
| TP-3.2 | GET /portfolio (no data) | 200, contains upload prompt |

## TP-4: Holdings Table (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | Page loads with Holdings data | Summary cards + table visible |
| TP-4.2 | RSU tranches: sellable qty | Matches Holdings XLSX |
| TP-4.3 | RSU tranches: broker cost basis | Matches Holdings XLSX |
| TP-4.4 | RSU tranches: tax status column | Shows Long Term / Short Term |
| TP-4.5 | ESPP tranches displayed | sellable_qty and cost basis from Holdings |
| TP-4.6 | Unvested rows: no P&L | Potential value shown, P&L = "—" |
| TP-4.7 | P&L color coding | Green/red for vested rows |
| TP-4.8 | FMV source indicator | * for market close fallback only |
| TP-4.9 | No Holdings data | Empty state: "Upload your ByBenefitType file" |

## TP-5: Grouping (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Default: Group by Type | ESPP -> RSU sections |
| TP-5.2 | Group by Status | Vested -> Unvested sections |
| TP-5.3 | Toggle between modes | Table re-groups |

## TP-6: Filters (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Default: Vested ON, Unvested ON | Both shown |
| TP-6.2 | Turn off Unvested | Only vested rows |
| TP-6.3 | Profit only filter | Only P&L > 0 rows |
| TP-6.4 | Loss only filter | Only P&L < 0 rows |
| TP-6.5 | Summary updates with filter | Totals match visible rows |

## TP-7: Sorting (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | Default: vest date desc | Newest first |
| TP-7.2 | Click Value column | Sorted by value |
| TP-7.3 | Click again | Toggles asc/desc |

## TP-8: Currency Toggle (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.1 | Default USD | Values in USD |
| TP-8.2 | Toggle INR | Values converted |
| TP-8.3 | Summary updates | INR totals |

---

## Test Approach

- TP-1, TP-2, TP-3: Automated (DataCase + ConnCase)
- TP-4 through TP-8: Manual browser testing with real ingested data
- Data: upload BH first (for unvested schedule), then Holdings (for vested sellable)

## Test Count: ~30 (15 automated, ~15 manual)
