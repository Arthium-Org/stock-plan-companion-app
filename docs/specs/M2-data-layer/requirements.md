# Requirements Document: M2 — Data Layer

## Introduction

The Data Layer module creates the persistence foundation for Stock Plan Manager: seven database tables implementing the medallion architecture (Bronze: ingestions + raw rows; Silver: origins, tranches, exercises, sales, sale_allocations). It also provides a SafeDecimal custom type, an ID generator, and context module stubs. The schema is structured around financial instrument lifecycles — RSU grants vest into lots, ESPP allotments ARE lots, ESOP grants vest into rights that are exercised into lots — with a shared sales/allocation system for tax-aware sell tracking.

## Glossary

- **SafeDecimal**: Custom Ecto type that stores Decimal values as TEXT in SQLite
- **Origin**: The parent allocation — an RSU grant, ESOP grant, or ESPP purchase/allotment
- **Tranche**: A scheduled vest row (child of origin). For RSU: becomes a sellable lot when vested. For ESOP: becomes an exercisable right when vested.
- **Exercise**: ESOP-only. Converts a vested tranche right into owned shares (a sellable lot).
- **Sale**: A sell execution — user-triggered, applies to all plan types
- **Sale_Allocation**: Links one sale to one or more source lots. Enables FIFO/specific-lot tax calculations.
- **Lot**: A block of sellable shares. Created by: RSU vest (tranche), ESPP allotment (origin), or ESOP exercise.
- **metadata_json**: JSON TEXT field for plan-type-specific details that don't warrant their own columns
- **ID_Generator**: Helper producing 16-character lowercase hex strings
- **Context_Module**: Module in `lib/stock_plan/` that owns all Repo calls for a domain

## Requirements

### Requirement 1: SafeDecimal Custom Ecto Type

**User Story:** As a developer, I want a custom Ecto type that stores Decimal values as TEXT in SQLite, so that I never lose precision on financial calculations.

#### Acceptance Criteria

1. THE SafeDecimal SHALL be defined at `lib/stock_plan/types/safe_decimal.ex` implementing `Ecto.Type`
2. WHEN `type/0` is called, THE SafeDecimal SHALL return `:string`
3. WHEN `cast/1` receives a string, Decimal, integer, float, or nil, THE SafeDecimal SHALL return `{:ok, %Decimal{}}` or `{:ok, nil}`
4. WHEN `cast/1` receives a float, THE SafeDecimal SHALL convert via `Float.to_string/1` to avoid IEEE 754 precision loss
5. WHEN `cast/1` receives an invalid value, THE SafeDecimal SHALL return `:error`
6. WHEN `dump/1` receives a `%Decimal{}`, THE SafeDecimal SHALL return `{:ok, string}`
7. WHEN `load/1` receives a string, THE SafeDecimal SHALL return `{:ok, %Decimal{}}`
8. FOR ANY valid Decimal value, dump followed by load SHALL return the original value with no precision loss

### Requirement 2: ID Generation

**User Story:** As a developer, I want a consistent ID helper, so that all tables use the same format.

#### Acceptance Criteria

1. THE ID_Generator SHALL be at `lib/stock_plan/id.ex`
2. WHEN `generate/0` is called, THE ID_Generator SHALL return a 16-character lowercase hex string
3. THE ID_Generator SHALL use `:crypto.strong_rand_bytes(8)` as entropy source
4. FOR ALL generated IDs, THE result SHALL match `^[0-9a-f]{16}$`

### Requirement 3: Ingestions Table and Schema

**User Story:** As a developer, I want an ingestions table that tracks file uploads, so that the system knows which upload is currently active.

#### Acceptance Criteria

1. THE migration SHALL create table `stock_plan_ingestions` with columns: `ingestion_id` (TEXT PK), `account_id` (TEXT NOT NULL), `broker` (TEXT NOT NULL), `source_type` (TEXT NOT NULL), `file_name` (TEXT NOT NULL), `file_hash` (TEXT NOT NULL), `status` (TEXT NOT NULL)
2. THE migration SHALL use `timestamps(type: :utc_datetime_usec)`
3. THE migration SHALL create indexes on `account_id` and `status`
4. THE Schema SHALL validate `status` ∈ `["ACTIVE", "ARCHIVED"]`
5. THE Schema SHALL validate `broker` ∈ `["ETRADE"]`
6. THE Schema SHALL validate `source_type` ∈ `["XLSX", "PDF"]`

### Requirement 4: Bronze Raw Table and Schema

**User Story:** As a developer, I want an append-only bronze table for raw row preservation and audit.

#### Acceptance Criteria

1. THE migration SHALL create table `stock_plan_bronze_raw` with columns: `id` (TEXT PK), `ingestion_id` (TEXT NOT NULL FK → ingestions, on_delete: :restrict), `sheet_name` (TEXT NOT NULL), `record_type` (TEXT NOT NULL), `row_index` (INTEGER NOT NULL), `raw_row_json` (TEXT NOT NULL), `row_hash` (TEXT NOT NULL)
2. THE migration SHALL use `timestamps(type: :utc_datetime_usec)`
3. THE migration SHALL create index on `ingestion_id` and unique index on `{ingestion_id, row_hash}`
4. THE Schema SHALL NOT validate `sheet_name` or `record_type` — parser responsibility

### Requirement 5: Origins Table and Schema

**User Story:** As a developer, I want an origins table that stores RSU grants, ESOP grants, and ESPP allotments with shared fields and type-specific metadata, so that all plan types have a common parent record.

#### Acceptance Criteria

1. THE migration SHALL create table `stock_plan_origins` with columns: `id` (TEXT PK), `ingestion_id` (TEXT NOT NULL FK → ingestions, on_delete: :restrict), `account_id` (TEXT NOT NULL), `symbol` (TEXT NOT NULL), `plan_type` (TEXT NOT NULL), `grant_number` (TEXT, nullable), `origin_date` (:date NOT NULL), `total_quantity` (TEXT, nullable SafeDecimal), `origin_fmv` (TEXT SafeDecimal), `origin_fx_rate` (TEXT SafeDecimal), `currency` (TEXT NOT NULL DEFAULT 'USD'), `status` (TEXT), `metadata_json` (TEXT)
2. THE migration SHALL use `timestamps(type: :utc_datetime_usec)`
3. THE migration SHALL create indexes on `ingestion_id`, `account_id`, and `plan_type`
4. THE migration SHALL create a unique index on `{ingestion_id, grant_number}` where grant_number is not null (prevents duplicate grant imports)
5. THE Schema SHALL validate `plan_type` ∈ `["RSU", "ESPP", "ESOP"]`
6. THE Schema SHALL validate `currency` ∈ `["USD"]`
7. THE Schema SHALL use SafeDecimal for `total_quantity`, `origin_fmv`, `origin_fx_rate`
8. THE Schema SHALL use `:date` for `origin_date`
9. THE Schema SHALL treat `total_quantity` as optional — RSU/ESOP must populate it (enforced in Silver builder M5), ESPP leaves it nil (quantities live on tranches)
10. FOR ESPP origins, `grant_number` SHALL be computed as the first 16 chars of SHA256 hash of `"ESPP:{symbol}:{origin_date}"` — provides stable dedup key across re-uploads

### Requirement 6: Tranches Table and Schema

**User Story:** As a developer, I want a tranches table for vest schedule rows (RSU and ESOP), so that each vest event is tracked individually with its own FMV, FX rate, and tax data.

#### Acceptance Criteria

1. THE migration SHALL create table `stock_plan_tranches` with columns: `id` (TEXT PK), `origin_id` (TEXT NOT NULL FK → origins, on_delete: :restrict), `ingestion_id` (TEXT NOT NULL FK → ingestions, on_delete: :restrict), `vest_date` (:date NOT NULL), `vest_quantity` (TEXT NOT NULL SafeDecimal), `vest_fmv` (TEXT SafeDecimal, nullable), `vest_fx_rate` (TEXT SafeDecimal, nullable), `tax_withheld_qty` (TEXT SafeDecimal, nullable), `net_quantity` (TEXT SafeDecimal, nullable), `status` (TEXT NOT NULL), `metadata_json` (TEXT)
2. THE migration SHALL use `timestamps(type: :utc_datetime_usec)`
3. THE migration SHALL create indexes on `origin_id`, `ingestion_id`, and `vest_date`
4. THE migration SHALL NOT create a unique index on tranches — split vests, corrections, and multiple ESPP purchases on same date are valid. Dedup handled by Silver builder (M5).
5. THE Schema SHALL validate `status` ∈ `["UNVESTED", "VESTED", "FORFEITED", "CANCELLED", "EXPIRED"]`
5. THE Schema SHALL use SafeDecimal for all quantity/fmv/fx fields
6. THE Schema SHALL use `:date` for `vest_date`
7. WHEN a tranche is UNVESTED, `vest_fmv` and `vest_fx_rate` SHALL be null
8. WHEN a tranche is VESTED (RSU), `net_quantity` SHALL equal `vest_quantity - tax_withheld_qty`

**Quantity Invariants (enforced in app logic, not DB):**
- `tax_withheld_qty` <= `vest_quantity`
- `net_quantity` = `vest_quantity` - `tax_withheld_qty`
- Available (unsold) quantity = `net_quantity` - sum of linked `sale_allocations.quantity`. **Derived at query time, never stored.**

### Requirement 7: Exercises Table and Schema

**User Story:** As a developer, I want an exercises table for ESOP exercise events, so that the conversion of vested rights into owned shares is tracked with cost basis.

#### Acceptance Criteria

1. THE migration SHALL create table `stock_plan_exercises` with columns: `id` (TEXT PK), `tranche_id` (TEXT NOT NULL FK → tranches, on_delete: :restrict), `ingestion_id` (TEXT NOT NULL FK → ingestions, on_delete: :restrict), `exercise_date` (:date NOT NULL), `exercise_quantity` (TEXT NOT NULL SafeDecimal), `exercise_fmv` (TEXT SafeDecimal), `exercise_fx_rate` (TEXT SafeDecimal), `exercise_price` (TEXT NOT NULL SafeDecimal), `tax_withheld_qty` (TEXT SafeDecimal), `net_quantity` (TEXT SafeDecimal), `metadata_json` (TEXT)
2. THE migration SHALL use `timestamps(type: :utc_datetime_usec)`
3. THE migration SHALL create indexes on `tranche_id` and `ingestion_id`
4. THE Schema SHALL use SafeDecimal for all quantity/price/fmv/fx fields
5. THE Schema SHALL use `:date` for `exercise_date`

**Quantity Invariants (enforced in app logic, not DB):**
- `tax_withheld_qty` <= `exercise_quantity`
- `net_quantity` = `exercise_quantity` - `tax_withheld_qty`
- Available (unsold) quantity = `net_quantity` - sum of linked `sale_allocations.quantity`. **Derived at query time, never stored.**

### Requirement 8: Sales Table and Schema

**User Story:** As a developer, I want a sales table for sell executions across all plan types, so that every sell transaction is recorded.

#### Acceptance Criteria

1. THE migration SHALL create table `stock_plan_sales` with columns: `id` (TEXT PK), `ingestion_id` (TEXT NOT NULL FK → ingestions, on_delete: :restrict), `account_id` (TEXT NOT NULL), `symbol` (TEXT NOT NULL), `sale_date` (:date NOT NULL), `total_quantity` (TEXT NOT NULL SafeDecimal), `sale_price` (TEXT NOT NULL SafeDecimal), `sale_fx_rate` (TEXT SafeDecimal), `proceeds` (TEXT SafeDecimal), `metadata_json` (TEXT)
2. THE migration SHALL use `timestamps(type: :utc_datetime_usec)`
3. THE migration SHALL create indexes on `ingestion_id`, `account_id`, and `sale_date`
4. THE Schema SHALL use SafeDecimal for all quantity/price/fx/proceeds fields
5. THE Schema SHALL use `:date` for `sale_date`

### Requirement 9: Sale Allocations Table and Schema

**User Story:** As a developer, I want a sale_allocations table that links each sale to its source lots, so that capital gains can be computed per-lot with correct holding periods.

#### Acceptance Criteria

1. THE migration SHALL create table `stock_plan_sale_allocations` with columns: `id` (TEXT PK), `sale_id` (TEXT NOT NULL FK → sales, on_delete: :restrict), `tranche_id` (TEXT NOT NULL FK → tranches, on_delete: :restrict), `exercise_id` (TEXT FK → exercises, on_delete: :restrict, nullable), `quantity` (TEXT NOT NULL SafeDecimal)
2. THE migration SHALL use `timestamps(type: :utc_datetime_usec)`
3. THE migration SHALL create indexes on `sale_id`, `tranche_id`, and `exercise_id`
4. THE Schema SHALL require `id`, `sale_id`, `tranche_id`, `quantity`. `exercise_id` is optional.
5. THE Schema SHALL use SafeDecimal for `quantity`
6. THE Schema SHALL NOT store any derived/computed values — all analytics computed live in Gold/Tax layer

**No polymorphic FKs.** All references are real DB-enforced foreign keys:
- RSU/ESPP: `tranche_id` populated, `exercise_id` nil
- ESOP: both `tranche_id` and `exercise_id` populated

**Derived fields (NOT stored, computed in Gold/Tax layer):** `cost_basis`, `capital_gain`, `gain_type` (STCG/LTCG), `holding_days`, `total_proceeds`. Deterministic from source lot data + sale price — always recomputable.

### Requirement 10: Context Module Stubs

**User Story:** As a developer, I want context module stubs so that future modules have a clear place to add queries.

#### Acceptance Criteria

1. `StockPlan.Ingestions` SHALL be at `lib/stock_plan/ingestions.ex`
2. `StockPlan.Origins` SHALL be at `lib/stock_plan/origins.ex`
3. `StockPlan.Tranches` SHALL be at `lib/stock_plan/tranches.ex`
4. `StockPlan.Exercises` SHALL be at `lib/stock_plan/exercises.ex`
5. `StockPlan.Sales` SHALL be at `lib/stock_plan/sales.ex`
6. ALL stubs SHALL compile with zero application warnings

### Requirement 11: SQLite Foreign Key Enforcement

**User Story:** As a developer, I want FK constraints enforced at the database level.

#### Acceptance Criteria

1. THE Repo config SHALL enable `PRAGMA foreign_keys = ON` via `after_connect`
2. WHEN an insert violates a FK constraint, THE database SHALL reject the write
3. ALL FKs SHALL use `on_delete: :restrict` — accidental parent deletion fails loudly

### Requirement 12: Migration Conventions

#### Acceptance Criteria

1. Migrations generated via `mix ecto.gen.migration` (never hand-created)
2. Tables created in dependency order: ingestions → bronze_raw → origins → tranches → exercises → sales → sale_allocations
3. All tables use `timestamps(type: :utc_datetime_usec)`
4. All PKs are TEXT (`:string`) with `primary_key: true`
5. `mix ecto.migrate` applies all without errors
6. `mix ecto.rollback` (×7) rolls all back cleanly
