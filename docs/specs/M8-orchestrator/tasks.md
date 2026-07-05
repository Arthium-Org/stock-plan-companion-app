# Tasks: M8 — Ingestion Orchestrator

## Development Approach: TDD

## Prerequisites

- M3-M7 all complete
- Existing `lib/stock_plan/ingestions.ex` stub to be replaced

---

## Task 1: Benefit History Ingestion

**TDD: Write tests first.**

- [ ] 1.1 **RED**: Write `test/stock_plan/ingestions_test.exs`
  - `ingest_benefit_history(account, valid_file)` → `{:ok, summary}` with ingestion_id, bronze counts, silver summary
  - `ingest_benefit_history(account, "/nonexistent")` → `{:error, :file_not_found}`
  - Previous BH archived when new one uploaded
  - Ingestion record created with correct fields (category, file_hash, status)
  - Bronze rows written
  - Silver rebuilt (origins, tranches, sales exist)
- [ ] 1.2 **GREEN**: Implement `ingest_benefit_history/2` in `lib/stock_plan/ingestions.ex`
- [ ] 1.3 Run tests — PASS

## Task 2: G&L Ingestion

- [ ] 2.1 **RED**: Write G&L ingestion tests
  - `ingest_gl(account, gl_file)` → `{:ok, summary}`
  - G&L without prior BH → `{:error, :no_benefit_history}`
  - Multiple G&L files coexist (no archiving)
  - Silver enriched with G&L data after ingest
- [ ] 2.2 **GREEN**: Implement `ingest_gl/2`
- [ ] 2.3 Run tests — PASS

## Task 3: Duplicate Detection

- [ ] 3.1 **RED**: Write duplicate tests
  - Upload same BH file twice → `{:error, :duplicate_file}`
  - Upload same G&L file twice → `{:error, :duplicate_file}`
  - Different files with different hashes → both succeed
- [ ] 3.2 **GREEN**: Implement `check_duplicate/2`
- [ ] 3.3 Run tests — PASS

## Task 4: Rebuild

- [ ] 4.1 **RED**: Write rebuild tests
  - `rebuild(account)` with existing data → `{:ok, summary}`
  - `rebuild("nonexistent")` → `{:error, :no_benefit_history}`
- [ ] 4.2 **GREEN**: Implement `rebuild/1`
- [ ] 4.3 Run tests — PASS

## Task 5: Full Pipeline Integration

- [ ] 5.1 Write integration test
  - `ingest_benefit_history` with SampleUser-1
  - `ingest_gl` with 3 G&L files
  - Verify full Silver state (origins, tranches, sales, allocations, FX, stock prices)
  - `rebuild` produces same result
- [ ] 5.2 Run tests — PASS

## Task 6: Verification

- [ ] 6.1 `mix format --check-formatted`
- [ ] 6.2 `mix compile --warnings-as-errors`
- [ ] 6.3 `mix test` — all pass

---

## Definition of Done

- [ ] `ingest_benefit_history/2` runs full pipeline in one call
- [ ] `ingest_gl/2` runs G&L pipeline with BH validation
- [ ] `rebuild/1` rebuilds Silver from Bronze
- [ ] Duplicate detection works
- [ ] Previous BH archived on new upload
- [ ] Parse errors don't create orphan ingestion records
- [ ] All tests pass
