# Test Plan: M2 — Data Layer

## TDD Workflow

For each task:
1. **Write tests first** (from this spec)
2. **Run tests** — all new tests FAIL (red)
3. **Implement** — write minimum code to pass
4. **Run tests** — all tests PASS (green)
5. **Refactor** if needed, re-run tests

Tests are organized by module. Each test has a unique ID for traceability back to requirements.

---

## TP-1: SafeDecimal Tests

**File:** `test/stock_plan/types/safe_decimal_test.exs`
**Validates:** Requirement 1

### TP-1.1: Cast — Valid Inputs

| Test ID | Input | Expected Output |
|---|---|---|
| TP-1.1.1 | `"123.45"` (string) | `{:ok, Decimal.new("123.45")}` |
| TP-1.1.2 | `"0.000000001"` (high precision) | `{:ok, Decimal.new("0.000000001")}` |
| TP-1.1.3 | `"-50.00"` (negative) | `{:ok, Decimal.new("-50.00")}` |
| TP-1.1.4 | `Decimal.new("99.99")` (Decimal struct) | `{:ok, Decimal.new("99.99")}` unchanged |
| TP-1.1.5 | `42` (integer) | `{:ok, Decimal.new(42)}` |
| TP-1.1.6 | `1.1` (float) | `{:ok, Decimal.new("1.1")}` — via string, not float |
| TP-1.1.7 | `nil` | `{:ok, nil}` |

### TP-1.2: Cast — Invalid Inputs

| Test ID | Input | Expected Output |
|---|---|---|
| TP-1.2.1 | `"abc"` | `:error` |
| TP-1.2.2 | `""` (empty string) | `:error` |
| TP-1.2.3 | `[1, 2]` (list) | `:error` |
| TP-1.2.4 | `%{a: 1}` (map) | `:error` |
| TP-1.2.5 | `{:ok, 1}` (tuple) | `:error` |

### TP-1.3: Dump

| Test ID | Input | Expected Output |
|---|---|---|
| TP-1.3.1 | `Decimal.new("123.45")` | `{:ok, "123.45"}` |
| TP-1.3.2 | `Decimal.new("0")` | `{:ok, "0"}` |
| TP-1.3.3 | `nil` | `{:ok, nil}` |
| TP-1.3.4 | `"123"` (not a Decimal) | `:error` |
| TP-1.3.5 | `42` (integer) | `:error` |

### TP-1.4: Load

| Test ID | Input | Expected Output |
|---|---|---|
| TP-1.4.1 | `"123.45"` | `{:ok, Decimal.new("123.45")}` |
| TP-1.4.2 | `"0.000000001"` | `{:ok, Decimal.new("0.000000001")}` |
| TP-1.4.3 | `nil` | `{:ok, nil}` |
| TP-1.4.4 | `"abc"` (invalid) | `:error` |
| TP-1.4.5 | `42` (not a string) | `:error` |

### TP-1.5: Round-Trip

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.5.1 | cast("72.36") → dump → load | Final equals original |
| TP-1.5.2 | cast("0.000000001") → dump → load | No precision loss |
| TP-1.5.3 | cast(1.1) → dump → load | Float precision preserved via string path |

---

## TP-2: ID Generator Tests

**File:** `test/stock_plan/id_test.exs`
**Validates:** Requirement 2

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Generate one ID | String length == 16 |
| TP-2.2 | Generate one ID | Matches `~r/^[0-9a-f]{16}$/` |
| TP-2.3 | Generate 1000 IDs | All unique (no collisions) |

---

## TP-3: Ingestion Schema Tests

**File:** `test/stock_plan/schema/ingestion_test.exs`
**Validates:** Requirement 3

### TP-3.1: Changeset Validation (Unit)

| Test ID | Input | Expected |
|---|---|---|
| TP-3.1.1 | All required fields valid | `changeset.valid? == true` |
| TP-3.1.2 | Empty attrs `%{}` | Invalid, 7 errors (all required fields) |
| TP-3.1.3 | `status: "INVALID"` | Invalid, inclusion error on :status |
| TP-3.1.4 | `status: "ACTIVE"` | Valid |
| TP-3.1.5 | `status: "ARCHIVED"` | Valid |
| TP-3.1.6 | `broker: "SCHWAB"` | Invalid, inclusion error on :broker |
| TP-3.1.7 | `source_type: "CSV"` | Invalid |
| TP-3.1.8 | `source_type: "PDF"` | Valid |

### TP-3.2: Repo Integration

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.2.1 | Insert valid ingestion, read back | All fields match, timestamps populated |
| TP-3.2.2 | Insert with duplicate ingestion_id | Raises (PK violation) |

---

## TP-4: Bronze Raw Schema Tests

**File:** `test/stock_plan/schema/bronze_raw_test.exs`
**Validates:** Requirement 4

### TP-4.1: Changeset Validation (Unit)

| Test ID | Input | Expected |
|---|---|---|
| TP-4.1.1 | All required fields valid | Valid |
| TP-4.1.2 | Empty attrs | Invalid, 7 errors |
| TP-4.1.3 | `sheet_name: "Unknown Sheet"` | Valid (no inclusion check) |
| TP-4.1.4 | `record_type: "New Type"` | Valid (no inclusion check) |

### TP-4.2: Repo Integration

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.2.1 | Insert with valid parent ingestion | Succeeds, timestamps populated |
| TP-4.2.2 | Insert with non-existent ingestion_id | Raises `Ecto.ConstraintError` (FK) |
| TP-4.2.3 | Insert duplicate row_hash for same ingestion | `{:error, changeset}` with unique constraint error |
| TP-4.2.4 | Insert same row_hash for different ingestion | Succeeds (unique is per-ingestion) |

---

## TP-5: Origin Schema Tests

**File:** `test/stock_plan/schema/origin_test.exs`
**Validates:** Requirement 5

### TP-5.1: Changeset Validation (Unit)

| Test ID | Input | Expected |
|---|---|---|
| TP-5.1.1 | Valid RSU origin (all required fields) | Valid |
| TP-5.1.2 | Valid ESPP origin (no grant_number) | Valid |
| TP-5.1.3 | Valid ESOP origin | Valid |
| TP-5.1.4 | `plan_type: "PHANTOM"` | Invalid |
| TP-5.1.5 | `currency: "EUR"` | Invalid |
| TP-5.1.6 | Missing `symbol` | Invalid |
| TP-5.1.7 | Empty attrs | Invalid, 8 errors (all required fields) |
| TP-5.1.8 | `origin_date: ~D[2025-01-24]` with SafeDecimal `total_quantity: "100"` | Valid |

### TP-5.2: Repo Integration

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.2.1 | Insert RSU origin, read back | SafeDecimal fields are `%Decimal{}`, origin_date is `%Date{}` |
| TP-5.2.2 | Insert with metadata_json for ESPP | JSON string stored and retrieved unchanged |
| TP-5.2.3 | Insert with non-existent ingestion_id | Raises `Ecto.ConstraintError` (FK) |
| TP-5.2.4 | Insert with nullable fields nil | Succeeds (origin_fmv, origin_fx_rate, status, metadata_json all nil) |
| TP-5.2.5 | Insert duplicate (same ingestion_id + grant_number) | `{:error, changeset}` unique constraint |
| TP-5.2.6 | Insert same grant_number in different ingestion | Succeeds (unique is per-ingestion) |

---

## TP-6: Tranche Schema Tests

**File:** `test/stock_plan/schema/tranche_test.exs`
**Validates:** Requirement 6

### TP-6.1: Changeset Validation (Unit)

| Test ID | Input | Expected |
|---|---|---|
| TP-6.1.1 | Valid UNVESTED tranche (vest_fmv nil) | Valid |
| TP-6.1.2 | Valid VESTED tranche (vest_fmv populated) | Valid |
| TP-6.1.3 | `status: "FORFEITED"` | Valid |
| TP-6.1.4 | `status: "CANCELLED"` | Valid |
| TP-6.1.5 | `status: "EXPIRED"` | Valid |
| TP-6.1.6 | `status: "INVALID"` | Invalid |
| TP-6.1.7 | Missing `vest_date` | Invalid |
| TP-6.1.8 | Missing `status` | Invalid |
| TP-6.1.9 | Empty attrs | Invalid, 6 errors |

### TP-6.2: Repo Integration

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.2.1 | Insert UNVESTED tranche, read back | vest_fmv is nil, vest_date is `%Date{}` |
| TP-6.2.2 | Insert VESTED tranche with all financial fields | SafeDecimal round-trip correct |
| TP-6.2.3 | Insert with non-existent origin_id | Raises `Ecto.ConstraintError` (FK) |
| TP-6.2.4 | Insert with non-existent ingestion_id | Raises `Ecto.ConstraintError` (FK) |
| TP-6.2.5 | Delete origin while tranche exists | Raises `Ecto.ConstraintError` (restrict) |
| TP-6.2.6 | Insert two tranches same origin_id + vest_date (split vests) | Both succeed — no unique constraint |
| TP-6.2.7 | Insert same vest_date for different origin | Succeeds (unique is per-origin) |

---

## TP-7: Exercise Schema Tests

**File:** `test/stock_plan/schema/exercise_test.exs`
**Validates:** Requirement 7

### TP-7.1: Changeset Validation (Unit)

| Test ID | Input | Expected |
|---|---|---|
| TP-7.1.1 | Valid exercise with all required fields | Valid |
| TP-7.1.2 | Missing `exercise_price` | Invalid |
| TP-7.1.3 | Missing `exercise_quantity` | Invalid |
| TP-7.1.4 | Optional fields nil (exercise_fmv, tax_withheld_qty, etc.) | Valid |
| TP-7.1.5 | Empty attrs | Invalid, 6 errors |

### TP-7.2: Repo Integration

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.2.1 | Insert exercise with parent chain (ingestion → origin → tranche → exercise) | Succeeds |
| TP-7.2.2 | Insert with non-existent tranche_id | Raises `Ecto.ConstraintError` (FK) |
| TP-7.2.3 | SafeDecimal fields round-trip | exercise_price, exercise_quantity load as `%Decimal{}` |

---

## TP-8: Sale Schema Tests

**File:** `test/stock_plan/schema/sale_test.exs`
**Validates:** Requirement 8

### TP-8.1: Changeset Validation (Unit)

| Test ID | Input | Expected |
|---|---|---|
| TP-8.1.1 | Valid sale with all required fields | Valid |
| TP-8.1.2 | Missing `sale_price` | Invalid |
| TP-8.1.3 | Missing `total_quantity` | Invalid |
| TP-8.1.4 | Optional fields nil (sale_fx_rate, proceeds, metadata_json) | Valid |
| TP-8.1.5 | Empty attrs | Invalid, 6 errors |

### TP-8.2: Repo Integration

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.2.1 | Insert sale, read back | sale_date is `%Date{}`, sale_price is `%Decimal{}` |
| TP-8.2.2 | Insert with non-existent ingestion_id | Raises `Ecto.ConstraintError` (FK) |

---

## TP-9: Sale Allocation Schema Tests

**File:** `test/stock_plan/schema/sale_allocation_test.exs`
**Validates:** Requirement 9

### TP-9.1: Changeset Validation (Unit)

| Test ID | Input | Expected |
|---|---|---|
| TP-9.1.1 | Valid with tranche_id, no exercise_id (RSU/ESPP) | Valid |
| TP-9.1.2 | Valid with tranche_id + exercise_id (ESOP) | Valid |
| TP-9.1.3 | exercise_id nil is valid | Valid |
| TP-9.1.4 | Missing tranche_id | Invalid |
| TP-9.1.5 | Missing quantity | Invalid |
| TP-9.1.6 | Empty attrs | Invalid, 4 errors |

### TP-9.2: Repo Integration

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-9.2.1 | Insert allocation linked to sale + tranche | Succeeds, exercise_id nil |
| TP-9.2.2 | Insert with non-existent sale_id | Raises `Ecto.ConstraintError` (FK) |
| TP-9.2.3 | Insert with non-existent tranche_id | Raises `Ecto.ConstraintError` (FK) |
| TP-9.2.4 | SafeDecimal quantity round-trip | quantity loads as `%Decimal{}` |

---

## TP-10: Lifecycle Integration Tests

**File:** `test/stock_plan/schema/lifecycle_test.exs`
**Validates:** Correctness Properties 3, 4, 5

### TP-10.1: RSU Full Chain

| Test ID | Step | Assertion |
|---|---|---|
| TP-10.1.1 | Create ingestion | Succeeds |
| TP-10.1.2 | Create RSU origin | Succeeds, linked to ingestion |
| TP-10.1.3 | Create UNVESTED tranche | Succeeds, vest_fmv nil |
| TP-10.1.4 | "Vest" — update tranche to VESTED with vest_fmv | Status = VESTED, vest_fmv populated |
| TP-10.1.5 | Create sale | Succeeds |
| TP-10.1.6 | Create sale_allocation (tranche_id: tranche.id, exercise_id: nil) | Succeeds |
| TP-10.1.7 | Verify chain integrity | All FKs valid, data retrievable |

### TP-10.2: ESPP Full Chain

| Test ID | Step | Assertion |
|---|---|---|
| TP-10.2.1 | Create ingestion | Succeeds |
| TP-10.2.2 | Create ESPP origin (enrollment: grant_date, lock_in_price, discount) | Succeeds, total_quantity nil |
| TP-10.2.3 | Create ESPP tranche (purchase: vest_date=purchase_date, qty, fmv, tax, net, buy_price in metadata) | Succeeds, status=VESTED |
| TP-10.2.4 | Create sale | Succeeds |
| TP-10.2.5 | Create sale_allocation (tranche_id: tranche.id, exercise_id: nil) | Succeeds — tranche is the lot |

### TP-10.3: ESOP Full Chain

| Test ID | Step | Assertion |
|---|---|---|
| TP-10.3.1 | Create ingestion | Succeeds |
| TP-10.3.2 | Create ESOP origin with metadata_json (strike_price, option_type) | Succeeds |
| TP-10.3.3 | Create UNVESTED tranche | Succeeds |
| TP-10.3.4 | "Vest" — update tranche to VESTED | Succeeds |
| TP-10.3.5 | Create exercise (links to tranche) | Succeeds |
| TP-10.3.6 | Create sale | Succeeds |
| TP-10.3.7 | Create sale_allocation (tranche_id: tranche.id, exercise_id: exercise.id) | Succeeds |
| TP-10.3.8 | Verify full chain: ingestion → origin → tranche → exercise → sale → allocation | All linked correctly |

### TP-10.4: FK Enforcement (Deletion Order)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-10.4.1 | Try to delete origin while tranches exist | Raises ConstraintError |
| TP-10.4.2 | Try to delete tranche while exercises exist | Raises ConstraintError |
| TP-10.4.3 | Try to delete sale while allocations exist | Raises ConstraintError |
| TP-10.4.4 | Delete in correct order: allocations → sales → exercises → tranches → origins | All succeed |

---

## TP-11: Context Stubs Compilation

**No test file** — verified by `mix compile --warnings-as-errors`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-11.1 | `StockPlan.Origins` compiles | No warnings |
| TP-11.2 | `StockPlan.Tranches` compiles | No warnings |
| TP-11.3 | `StockPlan.Exercises` compiles | No warnings |
| TP-11.4 | `StockPlan.Sales` compiles | No warnings |
| TP-11.5 | `StockPlan.Ingestions` compiles | No warnings |

---

## Test Fixture Helpers

To avoid repetition across test files, create shared test fixtures:

**File:** `test/support/fixtures.ex`

```elixir
defmodule StockPlan.TestFixtures do
  alias StockPlan.Repo
  alias StockPlan.Schema.{Ingestion, Origin, Tranche, Exercise, Sale}
  alias StockPlan.ID

  def create_ingestion(attrs \\ %{}) do
    defaults = %{
      ingestion_id: ID.generate(),
      account_id: "default",
      broker: "ETRADE",
      source_type: "XLSX",
      file_name: "BenefitHistory.xlsx",
      file_hash: "sha256_" <> ID.generate(),
      status: "ACTIVE"
    }

    %Ingestion{}
    |> Ingestion.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def create_rsu_origin(ingestion, attrs \\ %{}) do
    defaults = %{
      id: ID.generate(),
      ingestion_id: ingestion.ingestion_id,
      account_id: "default",
      symbol: "ADBE",
      plan_type: "RSU",
      grant_number: "RU" <> ID.generate() |> String.slice(0..5),
      origin_date: ~D[2025-01-24],
      total_quantity: "100",
      origin_fmv: "450.00",
      origin_fx_rate: "83.50",
      currency: "USD"
    }

    %Origin{}
    |> Origin.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def create_espp_origin(ingestion, attrs \\ %{}) do
    defaults = %{
      id: ID.generate(),
      ingestion_id: ingestion.ingestion_id,
      account_id: "default",
      symbol: "ADBE",
      plan_type: "ESPP",
      origin_date: ~D[2024-06-30],
      total_quantity: "25",
      origin_fmv: "160.00",
      origin_fx_rate: "83.00",
      currency: "USD",
      metadata_json: Jason.encode!(%{lock_in_price: "150.00", buy_price: "127.50", discount_percent: "15"})
    }

    %Origin{}
    |> Origin.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def create_esop_origin(ingestion, attrs \\ %{}) do
    defaults = %{
      id: ID.generate(),
      ingestion_id: ingestion.ingestion_id,
      account_id: "default",
      symbol: "ADBE",
      plan_type: "ESOP",
      grant_number: "EF" <> ID.generate() |> String.slice(0..5),
      origin_date: ~D[2020-03-15],
      total_quantity: "500",
      origin_fmv: "300.00",
      origin_fx_rate: "75.00",
      currency: "USD",
      metadata_json: Jason.encode!(%{strike_price: "72.36", option_type: "NQ", expiry_date: "2030-03-15"})
    }

    %Origin{}
    |> Origin.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def create_tranche(origin, ingestion, attrs \\ %{}) do
    defaults = %{
      id: ID.generate(),
      origin_id: origin.id,
      ingestion_id: ingestion.ingestion_id,
      vest_date: ~D[2026-01-24],
      vest_quantity: "25",
      status: "UNVESTED"
    }

    %Tranche{}
    |> Tranche.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def create_exercise(tranche, ingestion, attrs \\ %{}) do
    defaults = %{
      id: ID.generate(),
      tranche_id: tranche.id,
      ingestion_id: ingestion.ingestion_id,
      exercise_date: ~D[2026-06-15],
      exercise_quantity: "25",
      exercise_price: "72.36",
      exercise_fmv: "500.00",
      exercise_fx_rate: "84.00"
    }

    %Exercise{}
    |> Exercise.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def create_sale(ingestion, attrs \\ %{}) do
    defaults = %{
      id: ID.generate(),
      ingestion_id: ingestion.ingestion_id,
      account_id: "default",
      symbol: "ADBE",
      sale_date: ~D[2026-08-01],
      total_quantity: "10",
      sale_price: "520.00",
      sale_fx_rate: "84.50"
    }

    %Sale{}
    |> Sale.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
```

---

## Test Count Summary

| Test File | Unit Tests | Integration Tests | Total |
|---|---|---|---|
| safe_decimal_test.exs | 15 | 3 | 18 |
| id_test.exs | 3 | 0 | 3 |
| ingestion_test.exs | 8 | 2 | 10 |
| bronze_raw_test.exs | 4 | 4 | 8 |
| origin_test.exs | 8 | 4 | 12 |
| tranche_test.exs | 9 | 5 | 14 |
| exercise_test.exs | 5 | 3 | 8 |
| sale_test.exs | 5 | 2 | 7 |
| sale_allocation_test.exs | 7 | 3 | 10 |
| lifecycle_test.exs | 0 | 18 | 18 |
| **Total** | **~65** | **~45** | **~110** |

---

## TDD Task Execution Order

For each task in `tasks.md`:

```
1. Read test cases from this spec (TP-N section)
2. Create test file with all cases — tests will fail (module/table doesn't exist)
3. Create migration (if needed)
4. Create schema module
5. Run tests — should pass
6. Fix any failures
7. Move to next task
```

Exception: Integration tests that require parent records (FK tests) need the parent fixtures to exist first. The `TestFixtures` helper handles this — create it early (after Task 0).
