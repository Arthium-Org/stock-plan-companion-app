# Test Plan: M3b — Holdings (ByBenefitType) Ingestion

---

## TP-1: Holdings Parser — ESPP (Unit — Automated)

**File:** `test/stock_plan/ingestion/holdings_parser_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Parse SampleUser-3 ESPP sheet | Returns BronzeRow list, sheet_name = "Holdings_ESPP" |
| TP-1.2 | Purchase row fields | Symbol, Purchase Date, Purchase Price, Purchased Qty, Net Shares, Sellable Qty, Est. Cost Basis parsed |
| TP-1.3 | Totals row | Skipped (not in output) |
| TP-1.4 | Row count | Matches expected purchase count from sample |
| TP-1.5 | Blocked fields | Blocked Qty and Blocked Type captured in raw_row_json |
| TP-1.6 | Discount/FMV fields | Discount Percent, Grant Date FMV, Purchase Date FMV present |

## TP-2: Holdings Parser — Restricted Stock (Unit — Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Parse SampleUser-2 RS sheet | Returns BronzeRow list, sheet_name = "Holdings_RSU" |
| TP-2.2 | Grant row fields | Symbol, Grant Date, Granted Qty, Vested Qty, Unvested Qty, Grant Number, Status parsed |
| TP-2.3 | Vest Schedule row fields | Vest Date, Granted Qty, Vested Qty, Released Qty, Shares Traded for taxes parsed |
| TP-2.4 | Sellable Shares row fields | Sellable Est. Market Value, Est. Cost Basis, Tax Status, Blocked, Blocked Type parsed |
| TP-2.5 | Tax Withholding row fields | Tax Description, Taxable Gain, Effective Tax Rate, Withholding Amount parsed |
| TP-2.6 | Parent-child linking | Child rows have correct parent_index pointing to Grant row |
| TP-2.7 | Multiple grants | Each grant's children linked to correct parent |
| TP-2.8 | Totals row | Skipped |
| TP-2.9 | SampleUser-3 RS sheet | Also parses correctly (different user, same format) |

## TP-3: Bronze Writer — Holdings (Unit — Automated)

**File:** `test/stock_plan/ingestion/holdings_bronze_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | Write ESPP Holdings to Bronze | Rows inserted with category "HOLDINGS" |
| TP-3.2 | Write RSU Holdings to Bronze | Rows inserted with correct sheet_name |
| TP-3.3 | Dedup via row_hash | Re-write same data = 0 new inserts |
| TP-3.4 | Ingestion record | Created with source_type "HOLDINGS" |

## TP-4: Silver Builder Phase 5 — ESPP Enrichment (Unit — Automated)

**File:** `test/stock_plan/ingestion/silver_builder_holdings_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | ESPP tranche: sellable_qty updated | Matches Holdings Sellable Qty |
| TP-4.2 | ESPP tranche: cost_basis_broker updated | Matches Holdings Est. Cost Basis |
| TP-4.3 | ESPP tranche: metadata_json | Contains blocked_qty, blocked_type from Holdings |
| TP-4.4 | ESPP unmatched row | Warning logged, no crash, no DB change |

## TP-5: Silver Builder Phase 5 — RSU Enrichment (Unit — Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | RSU tranche: sellable_qty from Sellable Shares | Correct value |
| TP-5.2 | RSU tranche: cost_basis_broker from Sellable Shares | Correct value |
| TP-5.3 | RSU tranche: tax_status from Sellable Shares | "Long Term" or "Short Term" |
| TP-5.4 | RSU tranche: metadata_json | Contains blocked, blocked_type, release_date |
| TP-5.5 | RSU origin: status updated from Grant row | Matches broker status |
| TP-5.6 | RSU grant with no vest details | Origin status updated, no tranche changes |
| TP-5.7 | RSU unmatched grant_number | Warning logged, no crash |

## TP-6: Overwrite Semantics (Unit — Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Second Holdings upload overwrites first | sellable_qty from latest upload |
| TP-6.2 | Holdings overwrites previous values | Not fill-only — replaces even non-nil |
| TP-6.3 | Rebuild includes Phase 5 | After rebuild, Holdings data re-applied |

## TP-7: Orchestrator (Integration — Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | ingest_holdings end-to-end | Parse → Bronze → Silver rebuild succeeds |
| TP-7.2 | Holdings + BH coexist | Holdings ingestion does NOT archive BH |
| TP-7.3 | Duplicate file | Same file_hash warns, no error |
| TP-7.4 | Holdings without BH | No crash — logs warning about unmatched rows |

## TP-8: Upload UI (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.1 | Third upload area visible | "Holdings (ByBenefitType)" section present |
| TP-8.2 | Upload SampleUser-2 Holdings | Success message, rows parsed |
| TP-8.3 | Upload SampleUser-3 Holdings | ESPP + RSU rows parsed |
| TP-8.4 | Processing spinner | Shows during pipeline execution |
| TP-8.5 | Upload history | Holdings uploads shown in history table |

## TP-9: Integration — End-to-End (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-9.1 | Upload BH → Upload Holdings | Tranches have sellable_qty, cost_basis_broker |
| TP-9.2 | Upload Holdings only (no BH) | No crash, unmatched warnings |
| TP-9.3 | Re-upload Holdings | Previous values overwritten with new snapshot |
| TP-9.4 | Rebuild after Holdings | Phase 5 re-applies Holdings data |

---

## Test Approach

- TP-1 through TP-7: Automated (DataCase)
- TP-8, TP-9: Manual browser testing with real sample data
- Sample data: SampleUser-2 (RSU only), SampleUser-3 (ESPP + RSU)

## Test Count: ~35 (25 automated, ~10 manual)
