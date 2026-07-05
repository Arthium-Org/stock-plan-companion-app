# Tasks: M4 — Bronze Writer

## Development Approach: TDD

Write tests first → RED → implement → GREEN.

## Prerequisites

- M2: BronzeRaw schema + `(ingestion_id, row_hash)` unique index
- M3: BronzeRow struct + XlsxParser (for integration test)

---

## Task 1: Write Tests

**RED: Write all tests before implementation.**

- [ ] 1.1 Write `test/stock_plan/ingestion/bronze_writer_test.exs` per test-plan.md
  - Unit: write empty list returns {inserted: 0, skipped: 0}
  - Write list of rows inserts all with correct fields + parent_index
  - Write same rows twice — second call skips all (dedup)
  - inserted + skipped = input count
  - Ingestion not found → error
  - Archived ingestion → error
  - Written rows readable from DB with correct data + parent_index
  - Full pipeline: parse sample XLSX → write bronze → verify in DB + idempotent re-write
- [ ] 1.2 Run tests — confirm all FAIL

## Task 2: Implement BronzeWriter

**GREEN: Implement minimum code to pass.**

- [ ] 2.1 Create `lib/stock_plan/ingestion/bronze_writer.ex`
- [ ] 2.2 Implement `write/2` — validate ACTIVE ingestion, map rows, `insert_all` with `on_conflict: :nothing`
- [ ] 2.3 Short-circuit on empty input (no DB call)
- [ ] 2.4 All rows in one batch get identical `inserted_at`/`updated_at` timestamp
- [ ] 2.5 Run `mix test test/stock_plan/ingestion/bronze_writer_test.exs` — all PASS
- [ ] 2.6 Run `mix test` — full suite passes (no regressions)

## Task 3: End-to-End Pipeline Test

Verify M3 → M4 works with real sample data.

- [ ] 3.1 Write pipeline test: parse sample XLSX with M3, write with M4, verify row counts in DB
- [ ] 3.2 Verify re-running same file produces 0 inserts, N skips
- [ ] 3.3 Run `mix test` — all pass

## Task 4: Verification

- [ ] 4.1 Run `mix format --check-formatted` — pass
- [ ] 4.2 Run `mix compile --warnings-as-errors` — zero warnings
- [ ] 4.3 Run `mix test` — all tests pass

---

## Definition of Done

- [ ] `mix format --check-formatted` passes
- [ ] `mix compile --warnings-as-errors` zero warnings
- [ ] `mix test` passes — all M1-M4 tests green
- [ ] Bronze rows persisted from real sample XLSX
- [ ] Dedup verified — second write skips all
- [ ] FK verified — bad ingestion_id fails
- [ ] Git clean

---

## Notes

- **Small module**: ~40 lines of code. Most complexity is in the dedup handling.
- **Testing approach**: DataCase for DB tests. Fixtures helper for creating ingestion records.
- **No performance optimization**: Row-by-row insert in transaction is fine for single-tenant volumes.
