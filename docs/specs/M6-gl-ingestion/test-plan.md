# Test Plan: M6 — G&L Expanded Ingestion

## TDD Workflow

Write tests first → RED → implement → GREEN.

---

## TP-1: G&L Parser

**File:** `test/stock_plan/ingestion/gl_parser_test.exs`

### TP-1.1: Parsing

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1.1 | Parse G&L_Expanded_2025.xlsx | `{:ok, rows, warnings}`, rows non-empty |
| TP-1.1.2 | All rows have sheet_name "G&L_Expanded" | Every row.sheet_name == "G&L_Expanded" |
| TP-1.1.3 | All rows have record_type "Sell" | Every row.record_type == "Sell" |
| TP-1.1.4 | Summary rows skipped | No row with "Summary" in JSON |
| TP-1.1.5 | Row count matches expected | 2025 file has 83 Sell rows |
| TP-1.1.6 | parent_index nil for all rows | G&L is flat, no parent-child |

### TP-1.2: Excel Date Serial Conversion

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.2.1 | Vest Date FMV in raw_row_json | Is a numeric string (e.g., "473.56"), not NaiveDateTime |
| TP-1.2.2 | Known value check | Row with Grant RU383544, VestDate 04/15/2024 → vest_date_fmv ≈ 473.565 |
| TP-1.2.3 | Zero/nil FMV | Stored as null in JSON |

### TP-1.3: Hash and JSON

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.3.1 | row_hash is 64-char hex | All match `~r/^[0-9a-f]{64}$/` |
| TP-1.3.2 | No duplicate hashes | All unique |
| TP-1.3.3 | raw_row_json is valid JSON | `Jason.decode!/1` succeeds |
| TP-1.3.4 | JSON keys include expected fields | "Grant Number", "Vest Date", "Date Sold", "Proceeds Per Share" present |

### TP-1.4: Error Cases

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.4.1 | Non-existent file | `{:error, :file_not_found}` |
| TP-1.4.2 | Invalid file | `{:error, :invalid_format}` |

---

## TP-2: G&L Bronze Integration

**File:** `test/stock_plan/ingestion/gl_bronze_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Parse G&L + write to Bronze | Rows in DB with sheet_name "G&L_Expanded" |
| TP-2.2 | G&L + Benefit History coexist in Bronze | Both sheet types queryable |
| TP-2.3 | Different ingestion_ids | G&L ingestion_id ≠ Benefit History ingestion_id |
| TP-2.4 | Re-write same G&L → dedup | 0 inserted, N skipped |
| TP-2.5 | G&L ingestion has category "GL_EXPANDED" | Correct category |

---

## TP-3: Silver Builder Multi-Ingestion

**File:** `test/stock_plan/ingestion/silver_builder_test.exs` (updated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | `build(account_id)` with Benefit History only | Same results as before |
| TP-3.2 | `build("nonexistent")` | `{:error, :no_active_ingestions}` |
| TP-3.3 | Existing M5 tests pass with new signature | No regressions |

---

## TP-4: G&L → Silver Enrichment

**File:** `test/stock_plan/ingestion/gl_silver_test.exs`

### TP-4.1: RSU Enrichment

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1.1 | G&L enriches RSU tranche vest_fmv | Tranche vest_fmv not nil after rebuild |
| TP-4.1.2 | G&L enriches sale with sale_price | Sale has sale_price + proceeds |
| TP-4.1.3 | G&L creates RSU sale_allocation | Allocation links sale → tranche |
| TP-4.1.4 | Allocation quantity from G&L | Matches G&L Quantity field |

### TP-4.2: ESPP Enrichment

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.2.1 | G&L updates ESPP sale price | Sale has sale_price from G&L |
| TP-4.2.2 | ESPP origin matched by Grant Date | Correct origin linked |

### TP-4.3: Without G&L

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.3.1 | Benefit History only → vest_fmv nil | RSU tranches have nil vest_fmv |
| TP-4.3.2 | Benefit History only → sale_price nil | RSU sales have nil sale_price |
| TP-4.3.3 | Benefit History only → no RSU allocations | 0 RSU sale_allocations |

### TP-4.4: Overwrite Protection

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.4.1 | vest_fmv already set → G&L has different value | Original value preserved, NOT overwritten |
| TP-4.4.2 | sale_price already set → G&L has different value | Original value preserved, NOT overwritten |
| TP-4.4.3 | Allocation already exists for (sale_id, tranche_id) | No duplicate created |

### TP-4.5: Edge Cases

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.5.1 | G&L with unmatched grant number | Warning, row skipped |
| TP-4.5.2 | G&L with unmatched vest date | Warning, row skipped |
| TP-4.5.3 | Rebuild twice → idempotent | Same counts both times |
| TP-4.5.4 | G&L uploaded without Benefit History | `{:error, :no_benefit_history}`, Silver NOT deleted |
| TP-4.5.5 | Same lot in 2 G&L files (duplicate) | Only 1 allocation created |

### TP-4.6: Invariants

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.6.1 | Exactly 1 ACTIVE Benefit History required | build succeeds |
| TP-4.6.2 | 0 ACTIVE Benefit History | `{:error, :no_benefit_history}` |
| TP-4.6.3 | Allocation quantity sum | For each sale: sum(allocs.qty) == sale.total_quantity |

---

## TP-5: Sale Matching + Multi-Lot Sales

**File:** `test/stock_plan/ingestion/gl_silver_test.exs` (sale matching section)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Two G&L rows with same Order Number → one sale | Sale count = 1 |
| TP-5.2 | Two allocations for that sale | Allocation count = 2 |
| TP-5.3 | Each allocation has correct tranche + quantity | Matches G&L rows |
| TP-5.4 | Sale total_quantity = sum of allocation quantities | Invariant holds |
| TP-5.5 | Two sells on same date, different quantities | Two separate sales (not merged) |
| TP-5.6 | Order Number stored in sale metadata_json | Retrievable for matching |

---

## TP-6: Full Pipeline Integration

**File:** `test/stock_plan/ingestion/gl_pipeline_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Ingest Benefit History (SampleUser-1) | Origins + tranches + sales created |
| TP-6.2 | Ingest G&L 2025 (SampleUser-1) | 83 rows in Bronze |
| TP-6.3 | Rebuild Silver | RSU tranches have vest_fmv, sales have prices, allocations exist |
| TP-6.4 | Ingest G&L 2024 | Additional 11 rows in Bronze |
| TP-6.5 | Rebuild Silver | 2024 enrichments added alongside 2025 |
| TP-6.6 | Ingest G&L 2023 | Additional 12 rows in Bronze |
| TP-6.7 | Rebuild Silver — all three years | All enrichments present |
| TP-6.8 | Rebuild again → idempotent | Same counts |
| TP-6.9 | Bronze row count unchanged by rebuild | Bronze is append-only |
| TP-6.10 | Print summary | origins, tranches (with/without fmv), sales (with/without price), allocations |

---

## Test Count Summary

| Section | Tests |
|---|---|
| G&L Parser | ~12 |
| G&L Bronze Integration | 5 |
| Silver Builder Multi-Ingestion | ~3 |
| G&L → Silver Enrichment | ~16 |
| Sale Matching + Multi-Lot | 6 |
| Full Pipeline Integration | ~10 |
| **Total** | **~52** |
