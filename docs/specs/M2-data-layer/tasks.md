# Tasks: M2 — Data Layer (Revised)

## Development Approach: TDD

Each task follows Red → Green → Refactor:

1. **Write tests first** — from `test-plan.md` (TP-N sections)
2. **Run tests** — confirm they FAIL (red)
3. **Implement** — minimum code to pass
4. **Run tests** — confirm they PASS (green)
5. **Refactor** — clean up if needed, re-run

Test fixtures helper (`test/support/fixtures.ex`) should be created early (Task 0) since integration tests across all tasks depend on it.

## Prerequisites

- M1: Project Scaffold — bootable Phoenix app with SQLite
- Existing M2 code (old grants/events tables) must be removed first

---

## Task 0: Remove Old M2 Implementation

Delete the prior schema that used a single `stock_plan_grants` + `stock_plan_events` design.

- [ ] 0.1 Delete old migration files: `create_stock_plan_grants`, `create_stock_plan_events`
- [ ] 0.2 Delete old schema files: `grant.ex`, `event.ex`
- [ ] 0.3 Delete old context stubs: `grants.ex`, `events.ex`
- [ ] 0.4 Delete old test files: `grant_test.exs`, `event_test.exs`
- [ ] 0.5 Keep: `safe_decimal.ex`, `id.ex`, `ingestion.ex`, `bronze_raw.ex` and their tests (unchanged)
- [ ] 0.6 Keep: `ingestions.ex` context stub (unchanged)
- [ ] 0.7 Keep: ingestions and bronze_raw migrations (unchanged)
- [ ] 0.8 Create `test/support/fixtures.ex` with `StockPlan.TestFixtures` (from test-plan.md)
- [ ] 0.9 Run `mix ecto.reset` — only ingestions + bronze_raw migrations remain
- [ ] 0.10 Run `mix compile --warnings-as-errors` — clean
- [ ] 0.11 Run `mix test` — existing SafeDecimal, ID, Ingestion, BronzeRaw tests pass

---

## Task 1: Origins Migration and Schema

Create `stock_plan_origins` — parent allocations for all plan types.

**TDD: Write tests first (TP-5), then implement.**

- [ ] 1.1 **RED**: Write `test/stock_plan/schema/origin_test.exs` per TP-5 (8 unit + 4 integration tests)
- [ ] 1.2 Run `mix test test/stock_plan/schema/origin_test.exs` — confirm all FAIL (module doesn't exist)
- [ ] 1.3 **GREEN**: Run `mix ecto.gen.migration create_stock_plan_origins`
- [ ] 1.4 Define table: `id` (PK), `ingestion_id` (FK → ingestions, restrict), `account_id`, `symbol`, `plan_type`, `grant_number` (nullable), `origin_date` (:date), `total_quantity` (:string), `origin_fmv` (:string, nullable), `origin_fx_rate` (:string, nullable), `currency` (default "USD"), `status` (nullable), `metadata_json` (nullable)
- [ ] 1.5 Add timestamps, indexes on `ingestion_id`, `account_id`, `plan_type`
- [ ] 1.5a Add unique index on `{ingestion_id, grant_number}` (prevents duplicate grant imports)
- [ ] 1.6 Run `mix ecto.migrate`
- [ ] 1.7 Create `lib/stock_plan/schema/origin.ex` with changeset
- [ ] 1.8 Run `mix test test/stock_plan/schema/origin_test.exs` — all 12 tests PASS
- [ ] 1.9 Run `mix test` — full suite passes (no regressions)

## Task 2: Tranches Migration and Schema

Create `stock_plan_tranches` — vest schedule rows.

**TDD: Write tests first (TP-6), then implement.**

- [ ] 2.1 **RED**: Write `test/stock_plan/schema/tranche_test.exs` per TP-6 (9 unit + 5 integration tests)
- [ ] 2.2 Run `mix test test/stock_plan/schema/tranche_test.exs` — confirm all FAIL
- [ ] 2.3 **GREEN**: Run `mix ecto.gen.migration create_stock_plan_tranches`
- [ ] 2.4 Define table: `id` (PK), `origin_id` (FK → origins, restrict), `ingestion_id` (FK → ingestions, restrict), `vest_date` (:date), `vest_quantity`, `vest_fmv` (nullable), `vest_fx_rate` (nullable), `tax_withheld_qty` (nullable), `net_quantity` (nullable), `status`, `metadata_json` (nullable)
- [ ] 2.5 Add timestamps, indexes on `origin_id`, `ingestion_id`, `vest_date`
- [ ] 2.5a No unique index on tranches (split vests and corrections possible). Dedup in M5.
- [ ] 2.6 Run `mix ecto.migrate`
- [ ] 2.7 Create `lib/stock_plan/schema/tranche.ex` with status validation
- [ ] 2.8 Run `mix test test/stock_plan/schema/tranche_test.exs` — all 14 tests PASS
- [ ] 2.9 Run `mix test` — full suite passes

## Task 3: Exercises Migration and Schema

Create `stock_plan_exercises` — ESOP exercise events.

**TDD: Write tests first (TP-7), then implement.**

- [ ] 3.1 **RED**: Write `test/stock_plan/schema/exercise_test.exs` per TP-7 (5 unit + 3 integration tests)
- [ ] 3.2 Run `mix test test/stock_plan/schema/exercise_test.exs` — confirm all FAIL
- [ ] 3.3 **GREEN**: Run `mix ecto.gen.migration create_stock_plan_exercises`
- [ ] 3.4 Define table: `id` (PK), `tranche_id` (FK → tranches, restrict), `ingestion_id` (FK → ingestions, restrict), `exercise_date` (:date), `exercise_quantity`, `exercise_fmv` (nullable), `exercise_fx_rate` (nullable), `exercise_price`, `tax_withheld_qty` (nullable), `net_quantity` (nullable), `metadata_json` (nullable)
- [ ] 3.5 Add timestamps, indexes on `tranche_id`, `ingestion_id`
- [ ] 3.6 Run `mix ecto.migrate`
- [ ] 3.7 Create `lib/stock_plan/schema/exercise.ex` with changeset
- [ ] 3.8 Run `mix test test/stock_plan/schema/exercise_test.exs` — all 8 tests PASS
- [ ] 3.9 Run `mix test` — full suite passes

## Task 4: Sales Migration and Schema

Create `stock_plan_sales` — sell executions.

**TDD: Write tests first (TP-8), then implement.**

- [ ] 4.1 **RED**: Write `test/stock_plan/schema/sale_test.exs` per TP-8 (5 unit + 2 integration tests)
- [ ] 4.2 Run `mix test test/stock_plan/schema/sale_test.exs` — confirm all FAIL
- [ ] 4.3 **GREEN**: Run `mix ecto.gen.migration create_stock_plan_sales`
- [ ] 4.4 Define table: `id` (PK), `ingestion_id` (FK → ingestions, restrict), `account_id`, `symbol`, `sale_date` (:date), `total_quantity`, `sale_price`, `sale_fx_rate` (nullable), `proceeds` (nullable), `metadata_json` (nullable)
- [ ] 4.5 Add timestamps, indexes on `ingestion_id`, `account_id`, `sale_date`
- [ ] 4.6 Run `mix ecto.migrate`
- [ ] 4.7 Create `lib/stock_plan/schema/sale.ex` with changeset
- [ ] 4.8 Run `mix test test/stock_plan/schema/sale_test.exs` — all 7 tests PASS
- [ ] 4.9 Run `mix test` — full suite passes

## Task 5: Sale Allocations Migration and Schema

Create `stock_plan_sale_allocations` — lot linkage for tax.

**TDD: Write tests first (TP-9), then implement.**

- [ ] 5.1 **RED**: Write `test/stock_plan/schema/sale_allocation_test.exs` per TP-9 (11 unit + 4 integration tests)
- [ ] 5.2 Run `mix test test/stock_plan/schema/sale_allocation_test.exs` — confirm all FAIL
- [ ] 5.3 **GREEN**: Run `mix ecto.gen.migration create_stock_plan_sale_allocations`
- [ ] 5.4 Define table: `id` (PK), `sale_id` (FK → sales, restrict), `tranche_id` (FK → tranches, restrict, NOT NULL), `exercise_id` (FK → exercises, restrict, nullable), `quantity` — NO derived fields
- [ ] 5.5 Add timestamps, indexes on `sale_id`, `tranche_id`, `exercise_id`
- [ ] 5.6 Run `mix ecto.migrate`
- [ ] 5.7 Create `lib/stock_plan/schema/sale_allocation.ex` — require tranche_id, optional exercise_id, no derived fields
- [ ] 5.8 Run `mix test test/stock_plan/schema/sale_allocation_test.exs` — all 15 tests PASS
- [ ] 5.9 Run `mix test` — full suite passes

## Task 6: Context Module Stubs

Create context stubs for new tables (keep existing ingestions.ex).

- [ ] 6.1 Create `lib/stock_plan/origins.ex` — `StockPlan.Origins` with Repo + Origin aliases
- [ ] 6.2 Create `lib/stock_plan/tranches.ex` — `StockPlan.Tranches`
- [ ] 6.3 Create `lib/stock_plan/exercises.ex` — `StockPlan.Exercises`
- [ ] 6.4 Create `lib/stock_plan/sales.ex` — `StockPlan.Sales`
- [ ] 6.5 Run `mix compile --warnings-as-errors` — zero warnings

## Task 7: Full Lifecycle Integration Test

Verify the entire chain works end-to-end.

**TDD: Write tests first (TP-10), then verify they pass against implemented schema.**

- [ ] 7.1 **RED**: Write `test/stock_plan/schema/lifecycle_test.exs` per TP-10 (18 integration tests)
  - TP-10.1: RSU full chain (7 steps)
  - TP-10.2: ESPP full chain (5 steps)
  - TP-10.3: ESOP full chain (8 steps)
  - TP-10.4: FK deletion order enforcement (4 tests)
- [ ] 7.2 Run `mix test test/stock_plan/schema/lifecycle_test.exs` — all 18 tests PASS (schema already exists from Tasks 1-5)
- [ ] 7.3 Run `mix test` — full suite passes (no regressions)

## Task 8: Full Verification

- [ ] 8.1 Run `mix ecto.reset` — all 7 migrations apply cleanly
- [ ] 8.2 Run `mix ecto.rollback` (×7) — all roll back cleanly
- [ ] 8.3 Run `mix ecto.migrate` — all re-apply cleanly
- [ ] 8.4 Run `mix format --check-formatted` — pass
- [ ] 8.5 Run `mix compile --warnings-as-errors` — zero warnings
- [ ] 8.6 Run `mix test` — all tests pass

---

## Definition of Done

M2 is complete when ALL of the following are true:

- [ ] `mix format --check-formatted` passes
- [ ] `mix compile --warnings-as-errors` zero application warnings
- [ ] `mix test` passes — SafeDecimal, ID, all 7 schema tests, lifecycle test
- [ ] `mix ecto.reset` applies all migrations
- [ ] `mix ecto.rollback` (×7) + `mix ecto.migrate` round-trips cleanly
- [ ] 7 tables exist: ingestions, bronze_raw, origins, tranches, exercises, sales, sale_allocations
- [ ] FK enforced — insert with bad parent raises ConstraintError
- [ ] SafeDecimal + :date + timestamps all round-trip correctly
- [ ] Full RSU/ESPP/ESOP lifecycle chains insertable (integration test)
- [ ] Context stubs compile
- [ ] Git repo clean

---

## Non-Negotiable Migration Rules

1. Never edit an existing committed migration — always create new
2. Test rollback before proceeding
3. No silent nullable columns — nullable must be intentional
4. All FKs use `on_delete: :restrict`
5. Migration must run on clean DB (`mix ecto.reset`)

---

## Notes

- **Implementation priority**: Task 0 (cleanup) first. Then tables in dependency order: origins → tranches → exercises → sales → sale_allocations.
- **Key constraint**: Sale allocations use real DB FKs (tranche_id NOT NULL, exercise_id nullable). No polymorphism.
- **Testing approach**: Unit (changeset) + integration (Repo round-trip + FK). Lifecycle test verifies full chains.
- **Risk**: SQLite FK enforcement with `after_connect` pragma — already verified in prior M2 work.
