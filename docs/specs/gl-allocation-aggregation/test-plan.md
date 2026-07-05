# Test Plan: G&L Allocation Aggregation

## TP1 — Within-file sub-lot aggregation (core fix — SampleUser 2)

**Data:** SampleUser 2, grant RU383740, order 94231427, vest=04/15/2025.

G&L has 3 rows for this (grant, vest, order):
- qty=4, price=372.3, ws_adj=104.72
- qty=4, price=372.3, ws_adj=235.255  ← was being deduped (dropped)
- qty=1, price=372.3, ws_adj=235.26

**Expected after fix:**
- `aggregate_gl_bronze` produces one aggregated lot: qty=9, price=372.3
- Silver has exactly 1 `sale_allocation` record for (RU383740 04/15/2025 tranche, order 94231427)
- `sale_allocation.quantity = 9`
- BH says 9 → reconciliation passes ✓

**Before fix:** `sale_allocation.quantity = 5` (4 shares lost)

---

## TP1b — Within-file sub-lot aggregation (SampleUser 1)

**Data:** SampleUser 1, grant RU343763, order 93462327, vest=01/24/2025, price=388.075.

G&L has 2 rows: qty=2, qty=2 (different wash-sale adj).

**Expected:**
- One aggregated lot: qty=4, price=388.075
- `sale_allocation.quantity = 4`. BH reconciliation passes ✓

**Before fix:** qty=2 (2 shares lost)

---

## TP2 — Price-variation sub-lots (multiple aggregated lots per tranche+order)

**Data:** SampleUser 2, grant RU383740, order 94229310, vest=10/15/2024.

G&L has 2 rows:
- qty=6, price=371.998333
- qty=3, price=372.003333

**Expected:**
- Two distinct aggregated lots (different price → different group key)
- Silver has 2 `sale_allocation` records for this (tranche, order):
  - qty=6, price=371.998333
  - qty=3, price=372.003333
- Total = 9. BH says 9 → reconciliation passes ✓

---

## TP3 — Single-row lots are unchanged

**Data:** SampleUser 2, grant RU383740, order 94229310, vest=07/15/2024.

G&L has 3 rows: qty=3, qty=4, qty=2, all at price=372.

**Expected:**
- One aggregated lot: qty=9, price=372
- Silver has 1 `sale_allocation` record with qty=9 ✓

---

## TP4 — Cross-file: overlapping date range, latest wins

**Setup:** Upload G&L file A covering 2024-01-01 to 2025-03-31. Then upload G&L file B
covering 2025-01-01 to 2025-12-31. File B has a later `inserted_at` timestamp.

For sells in Jan–Mar 2025 in both files:
- `aggregate_gl_bronze` must use file B's rows (later `inserted_at`)
- File A's rows for the same `(symbol, sale_date)` in Jan–Mar 2025 are discarded

For sells in 2024 (only in file A):
- File A's rows are used (file B has no entries for those dates)

**Expected:** No double-counting; no missing 2024 entries.

---

## TP5 — Re-upload same file (idempotency)

Upload G&L file, rebuild Silver, upload same file again, rebuild Silver again.

**Expected:** `sale_allocation` records are identical after both rebuilds. The upsert
in `upsert_gl_allocation` updates quantity to the same value — no duplicate rows, no
quantity drift.

---

## TP5b — Unit test for `aggregate_gl_bronze/1`

Add to `test/stock_plan/ingestion/gl_silver_test.exs`:

1. **Sub-lot aggregation:** Two Bronze rows for same (symbol, grant, vest, order, price),
   different wash-sale adj. Expect one aggregated lot with qty = sum of both.

2. **Price variation:** Two Bronze rows for same (symbol, grant, vest, order) but different
   price. Expect two separate aggregated lots.

3. **Cross-file latest-wins:** Two ingestions, same (symbol, sale_date). Ingestion B has
   a later `inserted_at`. Expect only ingestion B's rows in surviving set.

4. **ESPP grouping:** Two Bronze rows with `Grant Number = "--"`, same
   `(grant_date, purchase_date, order, price)`, different wash-sale adj. Expect one
   aggregated lot with qty = sum; origin resolved via `find_espp_origin(grant_date)`.

---

## TP6 — Manual test: SampleUser 1 (all 3 G&L years)

```bash
mix stock_plan.manual_test 1
```

**Expected:** All Schedule FA checks pass. Capital Gains totals match G&L. Zero failures.

Previously failing due to allocation dedup dropping sub-lot shares.

---

## TP7 — Manual test: SampleUser 3

```bash
mix stock_plan.manual_test 3
```

**Expected:** All checks pass. No regressions from the aggregation refactor.

---

## TP7b — Manual test: SampleUser 2

```bash
mix stock_plan.manual_test 2
```

Requires adding user 2 to fixtures (T6). Specifically validates RU383740 vest=04/15/2025
allocation qty=9 after fix.

---

## TP8 — BH reconciliation check per (origin, sale_date)

For each `(origin_id, sale_date)` with a BH sell event, verify:

```
|SUM(sale_allocation.quantity) - BH.total_quantity| <= 2
```

This check should pass for all test users after the fix. A failure here means a G&L
row was missed or double-counted.

---

## TP9 — ESPP aggregation

**Data:** Any user with ESPP G&L rows (Users 1–5 all have them).

**Expected:**
- All ESPP rows are aggregated correctly
- No ESPP allocation quantity is under-counted
- Schedule FA ESPP proceeds match G&L proceeds ✓
