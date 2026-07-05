# Test Plan: M14b — Schedule FSI

---

## TP-1: FSI Context (Automated)

**File:** `test/stock_plan/tax/schedule_fsi_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Build FSI for FY with CG data | Returns map with 4 heads |
| TP-1.2 | Capital Gains head | income_inr = stcg + ltcg from CG summary |
| TP-1.3 | Capital Gains breakdown | stcg_inr and ltcg_inr populated |
| TP-1.4 | Tax paid on CG | ₹0 (no US withholding) |
| TP-1.5 | Salary head | nil (not foreign income) |
| TP-1.6 | Dividends head | ₹0 (not tracked yet) |
| TP-1.7 | User-to-populate fields | tax_payable = :user_to_populate |
| TP-1.8 | FY with no CG | Capital gains = ₹0 |
| TP-1.9 | CSV generation | Valid CSV with all columns |

## TP-2: Tax Centre UI (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Third tab visible | "Schedule FSI" tab on Tax Centre |
| TP-2.2 | Default state | FY selector with current FY |
| TP-2.3 | FSI table | 4 rows (Salary, House Property, CG, Other Sources) |
| TP-2.4 | CG row | Shows STCG + LTCG breakdown |
| TP-2.5 | User-to-populate styling | Distinct from computed values |
| TP-2.6 | FY change | Data refreshes |
| TP-2.7 | Download CSV | File downloads correctly |

## TP-3: Multi-User (Manual Browser)

| Test ID | User | Assertion |
|---|---|---|
| TP-3.1 | User 3 (has G&L) | CG values match Capital Gains tab |
| TP-3.2 | User 1 (has G&L) | CG values populated |
| TP-3.3 | No data | All heads ₹0 |

---

## Test Approach

- TP-1: Automated (DataCase)
- TP-2, TP-3: Manual browser testing

## Test Count: ~15 (9 automated, 6 manual)
