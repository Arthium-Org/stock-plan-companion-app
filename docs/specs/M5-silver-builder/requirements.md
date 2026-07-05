# Requirements Document: M5 — Silver Builder

## Introduction

The Silver Builder transforms Bronze rows into Silver records (origins, tranches, sales, sale_allocations). It reads raw JSON from `stock_plan_bronze_raw`, parses and normalizes field values (strip `$`/`%`, parse dates), interprets the financial semantics per plan type, and writes structured records to Silver tables. This is a full DELETE + INSERT rebuild — all existing Silver data for the account is deleted, then rebuilt from the ACTIVE ingestion's Bronze rows.

## Glossary

- **Silver_Builder**: Module that transforms Bronze → Silver. Entry point: `build(ingestion_id)`
- **Rebuild**: DELETE all Silver rows for the account, then re-create from Bronze. Idempotent.
- **Parent_Row**: Bronze row with record_type Grant/Purchase — becomes an origin (or origin + tranche for ESPP)
- **Event_Row**: Bronze row with record_type Event — becomes tranche update, sale, or is skipped
- **VestSchedule_Row**: Bronze row with record_type "Vest Schedule" — becomes UNVESTED tranche
- **Value_Normalizer**: Internal helper that strips `$`, `%`, `,` and parses dates from raw strings

## Requirements

### Requirement 1: Rebuild Semantics

**User Story:** As a developer, I want Silver to be rebuilt from scratch on each ingestion, so that the data always reflects the latest Bronze state.

#### Acceptance Criteria

1. WHEN `build(ingestion_id)` is called, THE Silver_Builder SHALL delete all existing Silver rows (origins, tranches, exercises, sales, sale_allocations) for the account
2. THE deletion order SHALL respect FK constraints: sale_allocations → sales → exercises → tranches → origins
3. AFTER deletion, THE Silver_Builder SHALL re-create Silver records from Bronze rows of the given ingestion
4. THE operation SHALL be idempotent — calling build twice produces the same Silver state
5. THE ingestion MUST be ACTIVE — archived ingestions are rejected

### Requirement 2: Value Normalization

**User Story:** As a developer, I want raw broker values cleaned and typed, so that Silver fields are consistent and queryable.

#### Acceptance Criteria

1. THE Silver_Builder SHALL strip `$` prefix from price/FMV values (e.g., `"$386.88"` → `"386.88"`)
2. THE Silver_Builder SHALL strip `%` suffix from percentage values (e.g., `"15%"` → `"15"`)
3. THE Silver_Builder SHALL strip `,` from numeric values (e.g., `"1,234.56"` → `"1234.56"`)
4. THE Silver_Builder SHALL parse dates in `DD-MMM-YYYY` format (e.g., `"24-JAN-2024"` → `~D[2024-01-24]`)
5. THE Silver_Builder SHALL parse dates in `MM/DD/YYYY` format (e.g., `"01/15/2025"` → `~D[2025-01-15]`)
6. THE Silver_Builder SHALL treat empty strings and `"0"` quantity as nil where appropriate
7. THE Silver_Builder SHALL handle missing/nil values gracefully (nullable fields stay nil)

### Requirement 3: RSU Processing

**User Story:** As a developer, I want RSU grants and vesting events transformed into origins + tranches, so that the portfolio shows accurate RSU holdings.

#### Acceptance Criteria

1. EACH RSU Grant parent row SHALL create one `stock_plan_origins` record with `plan_type: "RSU"`
2. THE origin SHALL extract: symbol, grant_date, grant_number, total_quantity (Granted Qty), status
3. EACH "Vest Schedule" child row SHALL create one UNVESTED tranche with vest_date. If vest_quantity is empty, leave as nil (do NOT derive from total/periods — equal split is not guaranteed).
4. EACH "Shares vested" event SHALL find or create the corresponding tranche by vest_date and set vest_quantity and status=VESTED
5. EACH "Shares released" event on the same date as a vest SHALL set `net_quantity` on the tranche (released = post-tax sellable shares)
6. THE tranche `tax_withheld_qty` SHALL be computed as `vest_quantity - net_quantity`
7. THE tranche `vest_fmv` SHALL be nil from Benefit History (not available — future: from G&L_Expanded or stock price API)
8. EACH "Shares sold" event SHALL create a `stock_plan_sales` record with sale_date and total_quantity (sale_price nil)
9. RSU sales SHALL NOT create sale_allocations — lot linkage indeterminate from Benefit History
10. "Shares granted" events SHALL be skipped (redundant to Grant parent row)

### Requirement 4: ESPP Processing

**User Story:** As a developer, I want ESPP purchases transformed into origins (enrollments) + tranches (purchases), so that the portfolio shows accurate ESPP holdings.

#### Acceptance Criteria

1. ESPP Purchase parent rows SHALL be grouped by Grant Date (enrollment period)
2. EACH unique Grant Date SHALL create one `stock_plan_origins` record with `plan_type: "ESPP"`
3. THE ESPP origin SHALL have: origin_date = Grant Date, origin_fmv = Grant Date FMV (lock-in price), grant_number = hash of `"ESPP:{symbol}:{grant_date}"`
4. EACH Purchase parent row SHALL create one VESTED tranche under its enrollment origin
5. THE ESPP tranche SHALL have: vest_date = Purchase Date, vest_quantity = Purchased Qty, vest_fmv = Purchase Date FMV, tax_withheld_qty = Tax Collection Shares, net_quantity = Net Shares
6. THE ESPP tranche metadata_json SHALL contain: `buy_price` (Purchase Price), `discount_percent`
7. "PURCHASE" event children SHALL be skipped (redundant to parent Purchase row)
8. "SELL" event children SHALL create `stock_plan_sales` with sale_date and total_quantity
9. EACH ESPP sale SHALL create a `stock_plan_sale_allocations` linking to the purchase tranche (via parent_index matching)

### Requirement 5: ESOP Processing (if Options sheet exists)

**User Story:** As a developer, I want ESOP grants processed into origins + tranches, so that option holdings are tracked.

#### Acceptance Criteria

1. EACH Options Grant parent row SHALL create one `stock_plan_origins` record with `plan_type: "ESOP"`
2. THE ESOP origin metadata_json SHALL contain: `strike_price` (Exercise Price), `option_type` (Type: NQ/ISO)
3. EACH "Vest Schedule" child row SHALL create one UNVESTED tranche
4. "Shares vested" events SHALL update corresponding tranche to VESTED
5. "Shares exercised" events SHALL create `stock_plan_exercises` records linked to the tranche
6. "Shares granted" events SHALL be skipped (redundant to Grant parent row)
7. IF no Options sheet exists in Bronze, THE Silver_Builder SHALL skip ESOP processing without error

### Requirement 6: Sale Allocation Strategy

**User Story:** As a developer, I want sales linked to lots only when the linkage is deterministic from the source data.

#### Acceptance Criteria

1. FOR RSU sales from Benefit History, THE Silver_Builder SHALL create the sale but NOT create any sale_allocation — lot linkage is indeterminate (user could have sold from any vested lot). Allocations come from G&L_Expanded spreadsheet (future ingestion source).
2. FOR ESPP sales, THE Silver_Builder SHALL link to the parent Purchase tranche (parent_index tells us which purchase the sell belongs to) — this linkage IS deterministic.
3. FOR ESOP sales, THE Silver_Builder SHALL NOT create allocations from Benefit History (same reason as RSU — lot linkage indeterminate).
4. THE Silver_Builder SHALL NOT use FIFO or any assumed matching strategy.
5. Sales without allocations are a valid state — allocation data arrives from G&L_Expanded or manual entry.

### Requirement 7: Return Value

**User Story:** As a developer, I want build results returned as a summary, so that the UI can display what was created.

#### Acceptance Criteria

1. THE Silver_Builder SHALL return `{:ok, summary}` where summary contains counts: origins, tranches, sales, allocations created
2. THE Silver_Builder SHALL return `{:error, reason}` on failure
3. THE summary SHALL include any warnings (e.g., unmatched sales, unparseable dates)
