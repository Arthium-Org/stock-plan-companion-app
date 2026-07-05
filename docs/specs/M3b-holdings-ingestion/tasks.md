# Tasks: M3b — Holdings (ByBenefitType) Ingestion

## Prerequisites

- M3 (parser pattern), M4 (Bronze Writer), M5 (Silver Builder), M8 (Orchestrator)
- Sample data: SampleUser-2 (RSU only), SampleUser-3 (ESPP + RSU)

---

## Task 1: Holdings Parser

- [ ] 1.1 Create `lib/stock_plan/ingestion/holdings_parser.ex`
- [ ] 1.2 Parse ESPP sheet — Purchase rows (25 columns), skip Totals
- [ ] 1.3 Parse Restricted Stock sheet — Grant, Vest Schedule, Sellable Shares, Tax Withholding rows (63 columns), skip Totals
- [ ] 1.4 Parent-child linking: Grant Number + Vest Period for RS children
- [ ] 1.5 Output BronzeRow structs: `sheet_name: "Holdings_ESPP"` and `sheet_name: "Holdings_RSU"`
- [ ] 1.6 Deterministic JSON serialization + SHA256 row_hash
- [ ] 1.7 Write tests: `test/stock_plan/ingestion/holdings_parser_test.exs`
  - ESPP: correct row count, fields parsed (Symbol, Purchase Date, Sellable Qty, Cost Basis)
  - RSU: correct row count per record type (Grant, Vest Schedule, Sellable Shares, Tax Withholding)
  - RSU parent-child linking via parent_index
  - Totals rows skipped
  - Both SampleUser-2 (RSU only) and SampleUser-3 (ESPP + RSU) parse correctly
- [ ] 1.8 Run tests — PASS

## Task 2: Migration — New Tranche Fields

- [ ] 2.1 Generate migration: `mix ecto.gen.migration add_holdings_fields_to_tranches`
- [ ] 2.2 Add `sellable_qty` (TEXT, nullable) — SafeDecimal
- [ ] 2.3 Add `cost_basis_broker` (TEXT, nullable) — SafeDecimal
- [ ] 2.4 Add `tax_status` (TEXT, nullable) — "Long Term" / "Short Term" / "Due at Vest"
- [ ] 2.5 Update `StockPlan.Schema.Tranche` schema with new fields
- [ ] 2.6 Run migration — PASS
- [ ] 2.7 Run existing tests — no regressions

## Task 3: Bronze Writer Integration

- [ ] 3.1 Verify existing Bronze Writer handles Holdings BronzeRows (category: "HOLDINGS")
- [ ] 3.2 Confirm dedup via row_hash works for Holdings rows
- [ ] 3.3 Write test: parse Holdings XLSX → Bronze Writer → rows in DB
- [ ] 3.4 Run tests — PASS

## Task 4: Silver Builder Phase 5 — Holdings Enrichment

- [ ] 4.1 Add Phase 5 to `silver_builder.ex`: `enrich_from_holdings/1`
- [ ] 4.2 ESPP matching: find tranche by (symbol, grant_date as origin enrollment, purchase_date as vest_date)
- [ ] 4.3 ESPP update: sellable_qty, cost_basis_broker from Holdings row
- [ ] 4.4 ESPP metadata: blocked_qty, blocked_type → metadata_json
- [ ] 4.5 RSU matching: find origin by grant_number, find tranche by vest_date
- [ ] 4.6 RSU update from Vest Schedule: released_qty, tax details
- [ ] 4.7 RSU update from Sellable Shares: sellable_qty, cost_basis_broker, tax_status
- [ ] 4.8 RSU metadata: blocked, blocked_type, release_date → metadata_json
- [ ] 4.9 RSU Grant row: update origin status
- [ ] 4.10 Overwrite semantics: Holdings values replace previous values (not fill-only)
- [ ] 4.11 Write tests: `test/stock_plan/ingestion/silver_builder_holdings_test.exs`
  - ESPP tranche updated with sellable_qty and cost_basis_broker
  - RSU tranche updated with sellable_qty, cost_basis_broker, tax_status
  - Unmatched Holdings rows: logged warning, no crash
  - Multiple Holdings uploads: latest overwrites previous
  - Holdings without prior BH data: no crash (warn only)
- [ ] 4.12 Run tests — PASS

## Task 5: Orchestrator — Holdings Pipeline

- [ ] 5.1 Add `ingest_holdings(account_id, file_path)` to `StockPlan.Ingestions`
- [ ] 5.2 Create ingestion with category "HOLDINGS", status "ACTIVE"
- [ ] 5.3 Parse → Bronze → Silver rebuild (all 5 phases)
- [ ] 5.4 Holdings does NOT archive BH or G&L ingestions
- [ ] 5.5 File hash duplicate detection
- [ ] 5.6 Update `rebuild/1` to include Phase 5
- [ ] 5.7 Write tests: end-to-end Holdings pipeline
- [ ] 5.8 Run tests — PASS

## Task 6: Upload UI — Holdings Upload Area

- [ ] 6.1 Add third upload area to `upload_live.ex`: "Holdings (ByBenefitType)"
- [ ] 6.2 Wire to `ingest_holdings/2` pipeline
- [ ] 6.3 Show processing status + summary (rows parsed, tranches updated)
- [ ] 6.4 Manual test in browser: upload SampleUser-2 Holdings file
- [ ] 6.5 Manual test in browser: upload SampleUser-3 Holdings file

## Task 7: Verification

- [ ] 7.1 `mix format --check-formatted`
- [ ] 7.2 `mix compile --warnings-as-errors`
- [ ] 7.3 `mix test` — all pass
- [ ] 7.4 Manual: upload BH → upload Holdings → verify tranches enriched
- [ ] 7.5 Manual: upload Holdings without BH → no crash, warnings logged
- [ ] 7.6 Manual: re-upload same Holdings file → duplicate warning

---

## Definition of Done

- [ ] Holdings XLSX parsed (ESPP + RSU sheets)
- [ ] Bronze rows stored with category "HOLDINGS"
- [ ] Tranches enriched: sellable_qty, cost_basis_broker, tax_status
- [ ] Holdings overwrite semantics (not fill-only)
- [ ] Orchestrator: `ingest_holdings/2` works end-to-end
- [ ] Upload UI: third upload area for Holdings
- [ ] All tests pass, no regressions
