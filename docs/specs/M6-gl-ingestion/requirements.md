# Requirements Document: M6 — G&L Expanded Ingestion

## Introduction

The G&L Expanded Ingestion module adds support for E*Trade's Gain & Loss Expanded XLSX files. These files contain per-lot sell records with complete tax lot details — the missing piece that connects sales to specific vest lots. G&L data flows through Bronze (preserving raw audit trail) and is consumed by an extended Silver Builder during rebuild. Benefit History is the primary mandatory data source — G&L is optional enrichment. The system must display portfolio data without G&L, and enrich it when G&L is available.

## Glossary

- **G&L_Expanded**: E*Trade's per-lot sell report — one row per lot sold, with vest date, FMV, sale price, proceeds, and capital gains classification
- **Benefit_History**: The primary Benefit History XLSX (M3) — creates origins, tranches, and sales
- **G&L_Ingestion**: A separate ingestion record for each G&L file upload (own ingestion_id)
- **Enrichment**: Updating existing Silver records with additional data from G&L during Silver rebuild
- **Excel_Date_Serial**: Numeric values xlsxir misinterprets as NaiveDateTime when Excel stores a number in a date-formatted cell
- **Lot_Match**: Linking a G&L sell row to an existing origin + tranche via Grant Number + Vest Date

## Requirements

### Requirement 1: G&L XLSX Parsing

**User Story:** As a developer, I want G&L_Expanded XLSX files parsed into BronzeRow structs, so that raw G&L data is preserved in Bronze.

#### Acceptance Criteria

1. THE G&L parser SHALL read G&L_Expanded XLSX files with the 47-column format
2. THE parser SHALL read the single sheet named `"G&L_Expanded"`
3. THE parser SHALL skip "Summary" rows (Record Type = "Summary")
4. THE parser SHALL process "Sell" rows, producing BronzeRow structs
5. THE parser SHALL assign `sheet_name: "G&L_Expanded"` to all output rows
6. THE parser SHALL assign `record_type: "Sell"` to all output rows
7. THE parser SHALL reuse the same BronzeRow struct and hashing logic from M3
8. THE parser SHALL return `{:ok, rows, warnings}` matching M3 parser signature
9. THE parser SHALL handle the Excel date-serial issue: `Vest Date FMV` column may contain NaiveDateTime values that are actually decimal numbers — these must be converted and stored as the raw value in the JSON

### Requirement 2: G&L Bronze Storage

**User Story:** As a developer, I want G&L data stored in the existing `stock_plan_bronze_raw` table, so that the audit trail includes all uploaded data.

#### Acceptance Criteria

1. G&L Bronze rows SHALL be stored in `stock_plan_bronze_raw` (same table as Benefit History)
2. EACH G&L upload SHALL create its own ingestion record with a unique ingestion_id
3. THE ingestion record SHALL have `source_type: "XLSX"` and a distinct file_name/file_hash
4. G&L ingestion records SHALL NOT archive the Benefit History ingestion — both coexist as ACTIVE
5. THE Bronze Writer (M4) SHALL be reused for writing G&L rows
6. Dedup SHALL work per-ingestion (same G&L file re-uploaded = 0 new rows)

### Requirement 3: Ingestion Lifecycle — Multiple ACTIVE Ingestions

**User Story:** As a developer, I want multiple ingestions to coexist (one Benefit History + multiple G&L files per tax year), so that each data source is tracked independently.

#### Acceptance Criteria

1. THE system SHALL support multiple ACTIVE ingestions per account: one Benefit History + N G&L files
2. WHEN a new Benefit History is uploaded, THE system SHALL archive the previous Benefit History ingestion only (G&L ingestions remain ACTIVE)
3. EACH G&L file (per tax year) SHALL have its own ingestion record
4. WHEN the same G&L file is re-uploaded (same file_hash), THE system SHALL warn and skip
5. THE ingestion record SHALL store enough metadata to identify the tax year (file_name or metadata_json)

**Note:** This changes the current "exactly one ACTIVE ingestion per account" constraint. The new rule is: exactly one ACTIVE Benefit History ingestion + zero or more ACTIVE G&L ingestions per account.

### Requirement 4: Extended Silver Builder — G&L Processing

**User Story:** As a developer, I want the Silver Builder to process G&L Bronze rows after Benefit History rows, so that Silver data is enriched with lot-level details during rebuild.

#### Acceptance Criteria

1. THE Silver Builder SHALL process data in two phases:
   - Phase 1: Process Benefit History Bronze rows (existing M5 logic — creates origins, tranches, sales)
   - Phase 2: Process G&L Bronze rows (enrichment — updates tranches, creates allocations)
2. THE builder SHALL verify exactly 1 ACTIVE Benefit History ingestion exists for the account. IF 0: return `{:error, :no_benefit_history}` and DO NOT delete existing Silver. IF >1: return `{:error, :multiple_benefit_histories}`.
3. Phase 2 SHALL only run if G&L Bronze rows exist for the account. If no G&L ingestions: Phase 2 skipped silently.
4. THE Silver Builder SHALL load G&L Bronze rows from ALL ACTIVE G&L ingestions for the account
5. Benefit History Silver data SHALL be complete and valid without G&L (vest_fmv nil, sale_price nil, no RSU allocations)
6. Rebuild SHALL remain idempotent — DELETE + INSERT produces the same result
7. IF no Benefit History exists, the builder SHALL NOT delete existing Silver and SHALL NOT run Phase 2

### Requirement 5: G&L → Silver Matching (RSU)

**User Story:** As a developer, I want G&L RSU sell rows matched to existing origins and tranches, so that vest_fmv and sale allocations are accurate.

#### Acceptance Criteria

1. FOR each G&L row with `Plan Type: "RS"`, THE builder SHALL match to an origin by `Grant Number`
2. FOR each matched origin, THE builder SHALL find the tranche by `Vest Date`
3. IF the matched tranche has nil `vest_fmv`, THE builder SHALL fill it from `Vest Date FMV`. IF vest_fmv already has a value, DO NOT overwrite.
4. THE builder SHALL find or create a sale using matching key: `Order Number` (preferred, stored in metadata_json) or `(origin_id, sale_date, total_quantity)` (fallback). `(origin_id, sale_date)` alone is NOT sufficient — multiple sells on same date are common.
5. THE sale SHALL be filled with `sale_price` and `proceeds` ONLY IF currently nil — never overwrite existing values
6. THE builder SHALL create a `stock_plan_sale_allocations` record linking sale → tranche, ONLY IF allocation for `(sale_id, tranche_id)` does not already exist. Duplicate allocations must be prevented.
7. The allocation quantity SHALL come from the G&L `Quantity` field
8. IF a G&L row references a Grant Number not found in Silver, THE builder SHALL add a warning and skip the row
9. IF a G&L row references a Vest Date not found as a tranche, THE builder SHALL add a warning and skip the row
10. **Invariant:** For each sale, `sum(allocations.quantity)` should equal `sale.total_quantity`. Verified as post-build check.

### Requirement 6: G&L → Silver Matching (ESPP)

**User Story:** As a developer, I want G&L ESPP sell rows matched to existing origins and tranches, so that sale prices are enriched.

#### Acceptance Criteria

1. FOR each G&L row with `Plan Type: "ESPP"`, THE builder SHALL match to an origin by Grant Date
2. THE builder SHALL match to a tranche by Purchase Date (= tranche vest_date)
3. THE sale SHALL be filled with sale_price and proceeds ONLY IF currently nil — never overwrite
4. THE builder SHALL NOT create new ESPP allocations — M5 already creates ESPP allocations from Benefit History. G&L for ESPP is price-enrichment only.
5. IF a G&L row references a Grant Date not found as an ESPP origin, THE builder SHALL add a warning

### Requirement 7: G&L Data Not Stored in Silver

The following G&L fields are available but NOT stored — derived in Gold/Tax layer:

- Capital Gains Status (STCG/LTCG)
- Adjusted Gain/Loss, Gain/Loss
- Wash Sale adjustments (amounts, adjusted cost basis)
- Disposition Type (Qualifying/Disqualifying for ESPP)
- Ordinary Income Recognized
- Acquisition Cost, Adjusted Cost Basis

These are tax analytics that depend on rules. The raw G&L data is preserved in Bronze for future computation.

### Requirement 8: Return Value

#### Acceptance Criteria

1. G&L parsing SHALL return `{:ok, rows, warnings}` (same as M3)
2. Silver Builder G&L phase SHALL contribute to the existing build summary: updated_tranches, matched_sales, allocations_created, warnings
3. Warnings SHALL use the same structured format: `%{type, sheet, row_index, message}`
