# Requirements Document: M4 — Bronze Writer

## Introduction

The Bronze Writer takes BronzeRow structs produced by the XLSX Parser (M3) and writes them to the `stock_plan_bronze_raw` table. It handles ID generation, timestamp assignment, dedup via row_hash, and batch insertion within a transaction. This is the bridge between parsing (in-memory) and persistence (SQLite). Bronze is append-only — rows are never updated or deleted (except on full DB reset).

## Glossary

- **BronzeRow**: In-memory struct from M3 parser — contains sheet_name, record_type, row_index, parent_index, raw_row_json, row_hash
- **BronzeRaw**: Ecto schema for `stock_plan_bronze_raw` table (M2)
- **Ingestion_ID**: The ID of the current ingestion — all bronze rows are linked to one ingestion
- **Dedup**: Rows with the same `(ingestion_id, row_hash)` are duplicates and skipped

## Requirements

### Requirement 1: Batch Write

**User Story:** As a developer, I want to write a list of BronzeRow structs to the database in one operation, so that parsing and persistence are cleanly separated.

#### Acceptance Criteria

1. THE BronzeWriter SHALL accept a list of `%BronzeRow{}` structs and an `ingestion_id`
2. THE BronzeWriter SHALL return `{:ok, %{inserted: count, skipped: count}}` on success
3. THE BronzeWriter SHALL generate a unique `id` (via `StockPlan.ID.generate/0`) for each row
4. THE BronzeWriter SHALL set `inserted_at` and `updated_at` timestamps (via Ecto `timestamps()`)
5. THE BronzeWriter SHALL map BronzeRow fields to BronzeRaw schema fields
6. THE BronzeWriter SHALL assign the given `ingestion_id` to every row

### Requirement 2: Dedup via Row Hash

**User Story:** As a developer, I want duplicate rows within the same ingestion automatically skipped, so that re-processing the same file doesn't create duplicates.

#### Acceptance Criteria

1. WHEN a row's `(ingestion_id, row_hash)` already exists in the database, THE BronzeWriter SHALL skip it
2. THE BronzeWriter SHALL count skipped rows separately from inserted rows
3. THE BronzeWriter SHALL NOT raise on duplicate — handle gracefully
4. WHEN the same list is written twice for the same ingestion_id, THE second call SHALL insert 0 and skip all

### Requirement 3: Atomicity

**User Story:** As a developer, I want all rows written atomically, so that a partial failure doesn't leave the database in an inconsistent state.

#### Acceptance Criteria

1. THE batch insert operation SHALL be atomic — all rows written or none (SQLite single-statement atomicity via `insert_all`)
2. THE BronzeWriter SHALL return `{:error, reason}` if the operation fails
3. All rows in one `write/2` call SHALL receive identical `inserted_at` and `updated_at` timestamps (batch consistency)
4. IF row count exceeds 1000, THE BronzeWriter MAY chunk into batches (not required for MVP)

### Requirement 4: Field Mapping

**User Story:** As a developer, I want BronzeRow struct fields mapped correctly to BronzeRaw schema fields.

#### Acceptance Criteria

| BronzeRow field | BronzeRaw column | Notes |
|---|---|---|
| sheet_name | sheet_name | Direct |
| record_type | record_type | Direct |
| row_index | row_index | Direct |
| parent_index | parent_index | Direct — persisted for M5 |
| raw_row_json | raw_row_json | Direct |
| row_hash | row_hash | Direct |
| (generated) | id | `StockPlan.ID.generate/0` |
| (parameter) | ingestion_id | From function argument |
| (manual) | inserted_at, updated_at | Set manually (insert_all skips callbacks) |

**Note:** `parent_index` from BronzeRow IS persisted in BronzeRaw. M3 already computed this — discarding it would force M5 to re-derive from row ordering. Persisting it makes M5 queries trivial: `WHERE parent_index == parent.row_index`.

### Requirement 5: Ingestion Validation

**User Story:** As a developer, I want the writer to reject writes to non-existent or archived ingestions.

#### Acceptance Criteria

1. WHEN the ingestion_id does not exist, THE BronzeWriter SHALL return `{:error, :ingestion_not_found}`
2. WHEN the ingestion exists but status is not ACTIVE, THE BronzeWriter SHALL return `{:error, :ingestion_not_active}`
3. THE BronzeWriter SHALL validate BEFORE writing any rows

### Requirement 6: Interface

**User Story:** As a developer, I want a clean module interface at `StockPlan.Ingestion.BronzeWriter`.

#### Acceptance Criteria

1. THE module SHALL be at `lib/stock_plan/ingestion/bronze_writer.ex`
2. THE public function SHALL be `write(ingestion_id, bronze_rows)` where `bronze_rows` is `[%BronzeRow{}]`
3. THE return type SHALL be `{:ok, %{inserted: non_neg_integer(), skipped: non_neg_integer()}}` or `{:error, term()}`
