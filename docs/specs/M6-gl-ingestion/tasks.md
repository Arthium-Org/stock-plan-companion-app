# Tasks: M6 — G&L Expanded Ingestion

## Development Approach: TDD

Write tests first → RED → implement → GREEN.

## Prerequisites

- M2: Schemas (bronze_raw, origins, tranches, sales, sale_allocations)
- M3: BronzeRow struct, parser pattern
- M4: Bronze Writer
- M5: Silver Builder (Benefit History processing)
- Sample G&L files in `docs/Sample-Data/SampleUser - 1/`

---

## Task 0: Schema Migration — Add Category to Ingestions

Add `category` field to distinguish Benefit History from G&L ingestions.

- [ ] 0.1 Run `mix ecto.gen.migration add_category_to_ingestions`
- [ ] 0.2 Add `category` column: `:string`, nullable (backfill existing as `"BENEFIT_HISTORY"`)
- [ ] 0.3 Update `StockPlan.Schema.Ingestion` — add field, update changeset
- [ ] 0.4 Update `source_type` validation to include `"XLSX"` for both categories
- [ ] 0.5 Run `mix ecto.migrate` — applies cleanly
- [ ] 0.6 Update existing tests — add category to fixture attrs
- [ ] 0.7 Run `mix test` — all existing tests pass

---

## Task 1: G&L Parser

Parse G&L_Expanded XLSX into BronzeRow structs.

**TDD: Write tests first.**

- [ ] 1.1 **RED**: Write `test/stock_plan/ingestion/gl_parser_test.exs`
  - Parse G&L file → returns `{:ok, rows, warnings}`
  - All rows have `sheet_name: "G&L_Expanded"`, `record_type: "Sell"`
  - Summary rows skipped
  - Vest Date FMV NaiveDateTime converted to decimal string in raw_row_json
  - Row count matches expected (83 sells in 2025 file)
  - row_hash is 64-char hex, no duplicates
  - parent_index is nil for all rows (flat, no parent-child)
  - Non-existent file → `{:error, :file_not_found}`
- [ ] 1.2 Run tests — confirm FAIL
- [ ] 1.3 **GREEN**: Create `lib/stock_plan/ingestion/gl_parser.ex`
- [ ] 1.4 Implement Excel date-serial NaiveDateTime → decimal conversion
- [ ] 1.5 Run tests — PASS
- [ ] 1.6 Run `mix test` — full suite passes

---

## Task 2: G&L Bronze Write Integration

Verify G&L rows write to bronze_raw through existing M4 Bronze Writer.

**TDD: Write tests first.**

- [ ] 2.1 **RED**: Write G&L bronze integration tests
  - Parse G&L → write to bronze → verify rows in DB with sheet_name "G&L_Expanded"
  - G&L Bronze rows coexist with Benefit History Bronze rows
  - Different ingestion_ids for Benefit History and G&L
  - Re-write same G&L file → 0 inserted, N skipped (dedup)
- [ ] 2.2 Run tests — confirm FAIL (need ingestion with category)
- [ ] 2.3 **GREEN**: Ensure parser + writer work together
- [ ] 2.4 Run tests — PASS

---

## Task 3: Update Silver Builder — Multi-Ingestion Support

Change Silver Builder from `build(ingestion_id)` to `build(account_id)`.

**TDD: Write tests first.**

- [ ] 3.1 **RED**: Write tests for new `build/1` signature
  - `build(account_id)` with only Benefit History → same result as before
  - `build("nonexistent")` → `{:error, :no_benefit_history}`
  - `build(account_id)` with 0 Benefit History ingestions → `{:error, :no_benefit_history}`, Silver NOT deleted
  - Existing M5 tests updated to use `build(account_id)`
- [ ] 3.2 Run tests — confirm FAIL (signature changed)
- [ ] 3.3 **GREEN**: Refactor Silver Builder
  - Find all ACTIVE ingestions for account
  - Identify Benefit History ingestion (by category)
  - Load Bronze rows from Benefit History ingestion → Phase 1
  - Phase 2 stub (no G&L processing yet)
- [ ] 3.4 Run tests — PASS (existing functionality preserved)

---

## Task 4: Silver Builder Phase 2 — G&L Enrichment

Add G&L processing to Silver Builder rebuild.

**TDD: Write tests first.**

- [ ] 4.1 **RED**: Write G&L enrichment tests
  - Ingest Benefit History + G&L → rebuild → RSU tranches have vest_fmv
  - Ingest Benefit History + G&L → rebuild → sales have sale_price
  - Ingest Benefit History + G&L → rebuild → RSU sale_allocations created
  - Ingest Benefit History only → rebuild → vest_fmv nil, sale_price nil, no RSU allocs (still works)
  - Rebuild twice → idempotent (same counts)
  - Multi-year G&L (2023 + 2024 + 2025) → all enrichments applied
  - Unmatched G&L rows → warnings
  - ESPP G&L rows → sale prices enriched, NO new allocations
  - Overwrite protection: vest_fmv already set → G&L does NOT overwrite
  - Overwrite protection: sale_price already set → G&L does NOT overwrite
  - Duplicate allocation prevention: same (sale_id, tranche_id) → skip
- [ ] 4.2 Run tests — confirm FAIL
- [ ] 4.3 **GREEN**: Implement Phase 2 in Silver Builder
  - Load G&L Bronze rows from all ACTIVE G&L ingestions
  - Parse each row's raw_row_json
  - Match RSU by grant_number → origin, vest_date → tranche
  - Match ESPP by grant_date → origin, purchase_date → tranche
  - Update vest_fmv, sale_price, create allocations
- [ ] 4.4 Run tests — PASS

---

## Task 5: Sale Matching + Multi-Lot Handling

Handle sale matching by Order Number and multi-lot sell orders.

- [ ] 5.1 **RED**: Write sale matching + multi-lot tests
  - Match sale by Order Number (stored in metadata_json)
  - Two G&L rows with same Order Number → one sale, two allocations
  - Two sells on same date, different quantities → two separate sales
  - Sale total_quantity = sum of allocation quantities (invariant)
  - Fallback matching by (origin_id, sale_date, quantity) when no Order Number
- [ ] 5.2 **GREEN**: Implement Order Number matching and grouping
- [ ] 5.3 Run tests — PASS

---

## Task 6: Full Pipeline Integration Test

End-to-end: Benefit History + G&L → Bronze → Silver → verify enrichment.

- [ ] 6.1 Write integration test with SampleUser-1 data:
  - Ingest Benefit History (sample-Etrade-BenefitHistory.xlsx)
  - Ingest G&L 2023, 2024, 2025
  - Rebuild Silver
  - Verify: RSU tranches enriched with vest_fmv
  - Verify: Sales enriched with sale_price + proceeds
  - Verify: RSU sale_allocations created
  - Verify: ESPP sales updated
  - Verify: Rebuild idempotent
  - Print summary
- [ ] 6.2 Run `mix test` — all pass

---

## Task 7: Verification

- [ ] 7.1 Run `mix format --check-formatted` — pass
- [ ] 7.2 Run `mix compile --warnings-as-errors` — zero warnings
- [ ] 7.3 Run `mix test` — all tests pass

---

## Definition of Done

- [ ] `mix format --check-formatted` passes
- [ ] `mix compile --warnings-as-errors` zero warnings
- [ ] `mix test` — all M1-M6 tests green
- [ ] G&L data flows through Bronze (raw audit trail preserved)
- [ ] Silver Builder processes Benefit History + G&L during rebuild
- [ ] RSU tranches enriched with vest_fmv from G&L
- [ ] Sales enriched with sale_price + proceeds from G&L
- [ ] RSU sale_allocations created from G&L lot linkage
- [ ] System works without G&L (Benefit History only)
- [ ] Rebuild is idempotent with both data sources
- [ ] Git clean

---

## Notes

- **Breaking change**: Silver Builder `build(ingestion_id)` → `build(account_id)`. All existing M5 tests must be updated.
- **Migration**: New `category` column on ingestions. Nullable for backcompat, but new ingestions should always set it.
- **G&L parser is simpler than M3**: Single sheet, flat rows, only "Sell" type. No parent-child linking.
- **Excel date-serial**: Converted at parse time, stored as corrected decimal in Bronze JSON. Silver Builder reads the already-corrected value.
- **Key risk**: G&L grant numbers must match Benefit History grant numbers exactly. Any mismatch = warning (not error).
