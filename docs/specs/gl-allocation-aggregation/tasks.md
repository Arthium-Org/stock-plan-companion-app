# Tasks: G&L Allocation Aggregation

## T1 — Add `aggregate_gl_bronze/1` to `silver_builder.ex`

Add the pre-aggregation function that:
1. Fetches all Bronze G&L `record_type = "Sell"` rows across all GL ingestions for the account
2. Determines the latest ingestion per `(symbol, sale_date)` by comparing `ingestion.inserted_at` timestamps
3. Discards rows not from the latest ingestion for their `(symbol, sale_date)`
4. Groups surviving rows by plan-type-specific key:
   - RS: `(symbol, "RS", grant_number, vest_date, sale_date, order_number, proceeds_per_share)`
   - ESPP: `(symbol, "ESPP", grant_date, purchase_date, sale_date, order_number, proceeds_per_share)`
5. Sums quantities within each group; carries first non-nil `Vest Date FMV` for RS enrichment
6. Returns a list of aggregated lot maps

## T2 — Replace `create_gl_allocation/5` with `upsert_gl_allocation/5`

New function signature: `upsert_gl_allocation(sale, tranche, aggregated_qty, price, order)`.

Dedup key: `(sale_id, tranche_id, order_number, sale_price)` — quantity is not in the key.
- If existing: update quantity (handles re-upload of same or amended file)
- If not: insert new record

Remove the old quantity+price+order dedup check.

## T3 — Refactor `process_gl_phase/2` to use aggregated lots

Replace the per-row loop with:
1. Call `aggregate_gl_bronze(gl_ingestions)` → list of aggregated lots
2. For each aggregated lot, dispatch by `plan_type`:
   - RS: `find_origin_by_grant(account_id, lot.tranche_key)` then `find_tranche_by_date(origin.id, lot.tranche_date)` (tranche_date = vest_date)
   - ESPP: `find_espp_origin(account_id, lot.tranche_key)` (tranche_key = grant_date) then `find_tranche_by_date(origin.id, lot.tranche_date)` (tranche_date = purchase_date)
3. For RS: call `fill_tranche_fmv(tranche, lot.vest_fmv)` to preserve existing FMV enrichment behavior
4. Call BH sale lookup: `find_bh_sale` (RS) or `find_bh_sale_espp` (ESPP) with `lot.aggregated_quantity`
5. Call `upsert_gl_allocation` with `lot.aggregated_quantity`
6. Emit warnings for unmatched origin/tranche/sale (same as current `process_gl_row/3`)

The `process_gl_row/3` function (current per-row processor) is removed.

## T4 — Add unit tests for `aggregate_gl_bronze/1`

In `test/stock_plan/ingestion/gl_silver_test.exs` (create if absent), add unit tests for
`aggregate_gl_bronze/1` covering:
- Within-file sub-lot aggregation: two rows with same (qty, price, order) → one lot, summed qty
- Price-variation: two rows same (order) but different price → two separate lots
- Cross-file latest-wins: two ingestions with same (symbol, sale_date), verify older is dropped
- ESPP grouping: grant_date (not grant_number) used for origin lookup

These run without a full manual test cycle — fast feedback loop.

## T5 — Rebuild Silver for test users and run manual test

Use the upload UI or `Ingestions.rebuild(account_id)` in iex for the relevant accounts.
Then run:

```bash
mix stock_plan.manual_test 1
mix stock_plan.manual_test 3
```

Verify: no allocation count regressions; Schedule FA and Capital Gains checks all pass.

## T6 — Add SampleUser 2 to manual test fixtures

Add user 2 to `lib/stock_plan/manual_test/fixtures.ex` with its G&L files and
`capital_gains_fys`. Run `mix stock_plan.manual_test 2` to validate TP8 cross-user
BH reconciliation.

## T7 — Add BH reconciliation check to manual test (if not already present)

If the manual test does not already verify `SUM(allocation.quantity) ≈ BH sell quantity`
per `(origin, sale_date)`, add that check so future regressions are caught automatically.
