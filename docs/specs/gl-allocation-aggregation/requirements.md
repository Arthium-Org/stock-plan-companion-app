# Requirements: G&L Allocation Aggregation

## Problem

The current Silver builder processes G&L Bronze rows one at a time and deduplicates
`sale_allocation` records using the key `(sale_id, tranche_id, quantity, sale_price, order_number)`.

**Note:** The M24 fix removed the blanket `delete_all` that was dropping all prior allocations
for a tranche on each G&L rebuild. That fix restored rows where quantities differ (e.g. qty=4
and qty=2 in the same order). This spec addresses a distinct remaining gap: rows where
`(quantity, price, order)` are identical — the qty-based dedup key still collapses them into one.

E*Trade splits a single vest-date tranche into **wash-sale sub-lots** — multiple G&L rows
with identical `(grant_number, vest_date, order_number, proceeds_per_share)` but different
`Wash Sale Adjustment Amount Per Share` and `Date Acquired (Wash Sale Toggle = On)`.
Each sub-lot represents different actual shares. The dedup key cannot distinguish them,
so the second (and further) sub-lot rows are silently dropped.

**Confirmed impact across sample data:**

| User | Grant | Vest date | Order | G&L rows | G&L total qty | BH qty | Recorded qty | Lost shares |
|---|---|---|---|---|---|---|---|---|
| User 1 | RU343763 | 01/24/2025 | 93462327 | qty=2, qty=2 @ 388.075 | 4 | 4 | 2 | 2 |
| User 2 | RU383740 | 04/15/2025 | 94231427 | qty=4, qty=4, qty=1 @ 372.3 | 9 | 9 | 5 | 4 |

For Indian tax, wash sale adjustments are irrelevant. But the shares are real — both rows
must be counted.

---

## Requirement 1: No silent row drop at insert — aggregate first

Every Bronze G&L Sell row in the surviving set (after Req 3 cross-file dedup) must
contribute to the Silver allocation. Wash-sale sub-lots represent different shares.
The correct model is: aggregate all rows sharing the same plan-type group key first,
then write one Silver allocation per group. No row is dropped; dedup operates on the
aggregated result.

---

## Requirement 2: Aggregate by (symbol, tranche, order, price)

After cross-file dedup (Req 3), aggregate the **surviving Bronze row set** using a
plan-type-specific grouping key:

**RSU / ESOP (`Plan Type = "RS"`):**
```
(symbol, "RS", grant_number, vest_date, sale_date, order_number, proceeds_per_share)
```

**ESPP (`Plan Type = "ESPP"`):**
```
(symbol, "ESPP", grant_date, purchase_date, sale_date, order_number, proceeds_per_share)
```

- ESPP G&L rows have `Grant Number = "--"` — not usable as a key. Use `Grant Date` instead,
  which is what `find_espp_origin(account_id, grant_date)` requires.
- `purchase_date` (not vest_date) identifies the ESPP tranche.
- `proceeds_per_share` is included because E*Trade can assign slightly different per-share
  prices to sub-lots within the same order+tranche (rounding of fractional-share fills).

All Bronze rows matching the same key are summed: `aggregated_qty = SUM(quantity)`.
Each group produces **one** `sale_allocation` record with `quantity = aggregated_qty`.

---

## Requirement 3: Cross-file dedup — latest ingestion wins per (symbol, sale_date)

A user may upload multiple G&L files with overlapping date ranges. For any given
`(symbol, sale_date)` combination, only rows from the **most recently uploaded** ingestion
that covers that combo are used. Rows for the same `(symbol, sale_date)` from older
ingestions are discarded.

**"Latest" is determined by `ingestion.inserted_at` (UTC timestamp), not by ingestion_id.**
`ingestion_id` is `crypto.strong_rand_bytes(8) |> Base.encode16` — random hex, not
monotonic. Lexicographic comparison of ingestion_id does not identify the later upload.
Use `DateTime.compare(a.inserted_at, b.inserted_at)` to pick the newest.

**Behavior change vs M6/M8:** M6 Property 4 ("G&L files are order-independent") and M8
("multiple ACTIVE G&L ingestions coexist") still hold for non-overlapping date ranges.
This spec adds: for overlapping `(symbol, sale_date)` entries across files, only the latest
upload's rows contribute to Silver. This is a deliberate override for overlapping data only.

**Rationale:** This handles:
- Re-upload of the same file (idempotent: same data, same result)
- Amended G&L (corrected quantities or prices replace prior file's entries for those dates)
- Overlapping date-range files (e.g., FY 2024-25 and CY 2025 both covering Jan–Mar 2025)

The override unit is `(symbol, sale_date)` — not the whole file. A newer file for 2025 does
not override entries for 2024 if the newer file does not contain any 2024 sell dates for
that symbol.

---

## Requirement 4: BH quantity reconciliation (invariant)

For each `(origin, sale_date)`, the sum of `sale_allocation.quantity` across all
`sale_allocation` records linked to that sale must equal the BH sell quantity within a
tolerance of 2 shares (to account for tax-withheld rounding across lots).

**On violation:** emit a **warning** (not a hard failure) logged during the Silver build
and surfaced in the upload page's ingestion summary. Hard-fail would block Silver build
for an otherwise valid ingestion; a warning flags the discrepancy for the user to investigate
without preventing the rest of the data from being usable.

This invariant replaces the old within-file dedup as the correctness signal for G&L ingestion.

---

## Requirement 5: ESPP order numbers always present

Verified across all sample G&L files (Users 1–5, 9 files): every ESPP G&L row has a
non-null order number. No special null-order handling required.

---

## Requirement 6: No schema changes

`sale_allocation` schema is unchanged. The aggregation happens in the Silver builder
pipeline, not in the schema. One `sale_allocation` record per aggregated group.

---

## Out of scope

- Wash sale adjustment storage — Indian tax does not require it; not stored anywhere
- Changes to Capital Gains or Schedule FA queries — both already sum across multiple
  allocations per tranche correctly (verified)
- Stock options (no G&L rows in sample data)
