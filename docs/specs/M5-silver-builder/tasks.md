# Tasks: M5 — Silver Builder

## Development Approach: TDD

Write tests first → RED → implement → GREEN.

## Prerequisites

- M2: Silver table schemas (origins, tranches, exercises, sales, sale_allocations)
- M3: XlsxParser (for integration test fixtures)
- M4: BronzeWriter (Bronze rows in DB for real data tests)

---

## Task 1: Value Normalizer

Parse and clean raw broker values. Pure functions, no DB.

**TDD: Write tests first.**

- [ ] 1.1 **RED**: Write `test/stock_plan/ingestion/value_normalizer_test.exs`
  - clean_number: `"$386.88"` → `"386.88"`, `"15%"` → `"15"`, `"1,234"` → `"1234"`, `""` → nil, nil → nil
  - parse_date: `"24-JAN-2024"` → `~D[2024-01-24]`, `"01/15/2025"` → `~D[2025-01-15]`, `""` → nil, nil → nil
  - Edge cases: `"0"` → nil for quantities, `"NA"` → nil, numbers without symbols pass through
- [ ] 1.2 **GREEN**: Create `lib/stock_plan/ingestion/value_normalizer.ex`
- [ ] 1.3 Run tests — PASS

## Task 2: Silver Delete (Rebuild Cleanup)

Implement deletion of existing Silver rows for an account.

**TDD: Write tests first.**

- [ ] 2.1 **RED**: Write delete tests in `test/stock_plan/ingestion/silver_builder_test.exs`
  - Insert test data across all Silver tables, call delete, verify empty
  - Verify deletion order respects FK constraints
  - Verify Bronze rows are NOT deleted
- [ ] 2.2 **GREEN**: Implement `delete_silver_for_account/1` in SilverBuilder
- [ ] 2.3 Run tests — PASS

## Task 3: RSU Processing

Transform RSU Bronze rows into Silver records.

**TDD: Write tests first.**

- [ ] 3.1 **RED**: Write RSU processing tests
  - Grant parent → creates origin with correct fields
  - Vest Schedule children → creates UNVESTED tranches
  - "Shares vested" + "Shares released" event pair → tranche updated to VESTED with vest_qty, net_qty, tax
  - "Shares sold" event → creates sale (sale_price nil, origin_id set) with NO allocation
  - "Shares granted" event → skipped
  - Multiple grants processed independently
- [ ] 3.2 **GREEN**: Implement RSU processor
- [ ] 3.3 Run tests — PASS

## Task 4: ESPP Processing

Transform ESPP Bronze rows into Silver records.

**TDD: Write tests first.**

- [ ] 4.1 **RED**: Write ESPP processing tests
  - Purchases grouped by Grant Date → one origin per enrollment
  - Each Purchase → VESTED tranche with buy_price in metadata
  - ESPP origin has hash grant_number
  - "PURCHASE" events skipped
  - "SELL" events → sales + allocations linked to parent purchase tranche
  - Multiple enrollments produce separate origins
- [ ] 4.2 **GREEN**: Implement ESPP processor
- [ ] 4.3 Run tests — PASS

## Task 5: ESOP Processing (Stub)

Transform Options Bronze rows into Silver records. Minimal — no real sample data.

- [ ] 5.1 **RED**: Write ESOP processing tests
  - Grant parent → origin with strike_price/option_type in metadata
  - Vest Schedule → UNVESTED tranches
  - "Shares vested" → tranche updated
  - "Shares exercised" → exercise record created
  - Missing Options sheet → no error
- [ ] 5.2 **GREEN**: Implement ESOP processor
- [ ] 5.3 Run tests — PASS

## Task 6: Full Build Orchestration

Wire everything together: validate → delete → process all sheets → return summary.

- [ ] 6.1 **RED**: Write orchestration tests
  - build/1 with non-existent ingestion → error
  - build/1 with archived ingestion → error
  - build/1 returns summary with correct counts
  - build/1 twice produces identical Silver state (idempotent)
- [ ] 6.2 **GREEN**: Implement `build/1` public function
- [ ] 6.3 Run tests — PASS

## Task 7: Integration Test with Real Sample Data

Parse SampleUser-2 XLSX → write Bronze → build Silver → verify.

- [ ] 7.1 Write integration test:
  - Full pipeline: parse → bronze → silver build
  - Verify 13 RSU origins created (matching 13 Grant rows)
  - Verify ESPP origins created (grouped by enrollment)
  - Verify tranches exist for each origin
  - Verify VESTED tranches have net_quantity set
  - Verify sales created from SELL events
  - Verify sale_allocations link sales to tranches
  - Verify rebuild produces same counts
- [ ] 7.2 Run `mix test` — all pass

## Task 8: Verification

- [ ] 8.1 Run `mix format --check-formatted` — pass
- [ ] 8.2 Run `mix compile --warnings-as-errors` — zero warnings
- [ ] 8.3 Run `mix test` — all tests pass

---

## Definition of Done

- [ ] `mix format --check-formatted` passes
- [ ] `mix compile --warnings-as-errors` zero warnings
- [ ] `mix test` — all M1-M5 tests green
- [ ] SampleUser-2 data: Bronze → Silver pipeline produces correct origins, tranches, sales
- [ ] RSU vest/release pairing works (net_quantity, tax_withheld computed)
- [ ] ESPP enrollment grouping works (one origin per Grant Date)
- [ ] Rebuild is idempotent
- [ ] Values normalized ($, %, dates parsed)
- [ ] Git clean

---

## Notes

- **Implementation priority**: Task 1 (normalizer) first — used by everything else. Then Tasks 2-5 in any order. Task 6 wires them together. Task 7 validates with real data.
- **FX rates**: All nil in Phase 1. Leave origin_fx_rate, vest_fx_rate, sale_fx_rate as nil.
- **Sale price**: Always nil from Benefit History. Sale records still created for tracking.
- **ESOP**: Minimal testing — no real Options data in samples. Implement the structure, test with mocks.
- **Biggest risk**: RSU vest/release event pairing. Real data shows they always appear as pairs on the same date. If a vest has no matching release (or vice versa), add warning.
