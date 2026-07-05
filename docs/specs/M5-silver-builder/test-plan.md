# Test Plan: M5 — Silver Builder

## TDD Workflow

Write tests first → RED → implement → GREEN.

---

## TP-1: Value Normalizer

**File:** `test/stock_plan/ingestion/value_normalizer_test.exs`

### TP-1.1: clean_number

| Test ID | Input | Expected |
|---|---|---|
| TP-1.1.1 | `"$386.88"` | `"386.88"` |
| TP-1.1.2 | `"15%"` | `"15"` |
| TP-1.1.3 | `"1,234.56"` | `"1234.56"` |
| TP-1.1.4 | `"$1,234.56"` | `"1234.56"` |
| TP-1.1.5 | `"117.6485"` (no symbols) | `"117.6485"` |
| TP-1.1.6 | `""` | nil |
| TP-1.1.7 | nil | nil |
| TP-1.1.8 | `"0"` | nil (zero treated as empty for quantities) |
| TP-1.1.9 | `"441"` (integer string) | `"441"` |
| TP-1.1.10 | `"35.782"` (fractional) | `"35.782"` |

### TP-1.2: parse_date

| Test ID | Input | Expected |
|---|---|---|
| TP-1.2.1 | `"24-JAN-2024"` | `~D[2024-01-24]` |
| TP-1.2.2 | `"03-JUL-2017"` | `~D[2017-07-03]` |
| TP-1.2.3 | `"30-JUN-2025"` | `~D[2025-06-30]` |
| TP-1.2.4 | `"01/15/2025"` | `~D[2025-01-15]` |
| TP-1.2.5 | `"12/24/2019"` | `~D[2019-12-24]` |
| TP-1.2.6 | `""` | nil |
| TP-1.2.7 | nil | nil |
| TP-1.2.8 | `"NA"` | nil |
| TP-1.2.9 | `"invalid"` | nil |

---

## TP-2: Silver Delete

**File:** `test/stock_plan/ingestion/silver_builder_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Insert origins + tranches + sales + allocations, then delete | All Silver tables empty for account |
| TP-2.2 | Bronze rows survive deletion | Bronze row count unchanged |
| TP-2.3 | Other account's Silver rows survive | Only target account deleted |

---

## TP-3: RSU Processing

**File:** `test/stock_plan/ingestion/silver_builder_test.exs` (RSU section)

### TP-3.1: Origin Creation

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1.1 | Grant parent → origin | plan_type=RSU, symbol, grant_date, grant_number, total_quantity set |
| TP-3.1.2 | Origin has correct ingestion_id | Matches ingestion |

### TP-3.2: Tranche Creation

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.2.1 | Vest Schedule → UNVESTED tranche | vest_date set, status=UNVESTED, vest_fmv=nil |
| TP-3.2.2 | "Shares vested" + "Shares released" pair | tranche: status=VESTED, vest_quantity=vested, net_quantity=released |
| TP-3.2.3 | tax_withheld_qty computed | = vest_quantity - net_quantity |
| TP-3.2.4 | UNVESTED tranche stays if no matching event | status=UNVESTED |

### TP-3.3: Sales

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.3.1 | "Shares sold" → sale created | sale_date, total_quantity set, sale_price=nil |
| TP-3.3.2 | RSU sale has NO allocation | sale_allocations count = 0 for this sale |
| TP-3.3.3 | "Shares granted" event → skipped | No extra records |

---

## TP-4: ESPP Processing

**File:** `test/stock_plan/ingestion/silver_builder_test.exs` (ESPP section)

### TP-4.1: Origin + Tranche

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1.1 | Two Purchases same Grant Date → one origin | origin count = 1 |
| TP-4.1.2 | Two Purchases different Grant Date → two origins | origin count = 2 |
| TP-4.1.3 | ESPP origin has hash grant_number | Deterministic, 16 chars |
| TP-4.1.4 | Purchase → VESTED tranche | vest_date=Purchase Date, vest_fmv=Purchase Date FMV |
| TP-4.1.5 | Tranche has tax/net from parent | tax_withheld_qty, net_quantity correct |
| TP-4.1.6 | Tranche metadata has buy_price | metadata_json contains buy_price |

### TP-4.2: Events

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.2.1 | "PURCHASE" event → skipped | No extra records |
| TP-4.2.2 | "SELL" event → sale created | sale_date, total_quantity set |
| TP-4.2.3 | SELL allocation linked to parent's tranche | tranche_id matches |

---

## TP-5: ESOP Processing

**File:** `test/stock_plan/ingestion/silver_builder_test.exs` (ESOP section)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Grant → origin with metadata (strike_price, option_type) | Correct |
| TP-5.2 | Vest Schedule → UNVESTED tranche | status=UNVESTED |
| TP-5.3 | "Shares vested" → tranche updated to VESTED | status=VESTED |
| TP-5.4 | "Shares exercised" → exercise created | exercise_date, exercise_quantity, exercise_price |
| TP-5.5 | No Options sheet → no error | Returns ok with 0 ESOP records |

---

## TP-6: Build Orchestration

**File:** `test/stock_plan/ingestion/silver_builder_test.exs` (orchestration section)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | build/1 with non-existent ingestion | `{:error, :ingestion_not_found}` |
| TP-6.2 | build/1 with archived ingestion | `{:error, :ingestion_not_active}` |
| TP-6.3 | build/1 returns summary with counts | origins > 0, tranches > 0 |
| TP-6.4 | build/1 twice → idempotent | Same counts, same data |
| TP-6.5 | build/1 summary includes warnings list | warnings is a list |

---

## TP-7: Integration with Real Sample Data

**File:** `test/stock_plan/ingestion/silver_builder_integration_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | Full pipeline: parse → bronze → silver for SampleUser-2 | `{:ok, summary}` |
| TP-7.2 | RSU origins count | 13 (matching 13 Grant rows) |
| TP-7.3 | ESPP origins count | > 0, grouped by enrollment |
| TP-7.4 | Tranches exist for each origin | Each origin has ≥ 1 tranche |
| TP-7.5 | Some VESTED tranches have net_quantity | At least some > 0 |
| TP-7.6 | Sales created from SELL events | sales count > 0 |
| TP-7.7 | ESPP sale allocations exist (direct linkage) | ESPP allocations > 0 |
| TP-7.7b | RSU sales have NO allocations | RSU sale allocations = 0 |
| TP-7.8 | Rebuild produces same counts | Second build = same summary |
| TP-7.9 | All origin dates are valid Date structs | No nil dates |
| TP-7.10 | ESPP tranche metadata contains buy_price | Parseable from metadata_json |

---

## Test Count Summary

| Section | Tests |
|---|---|
| Value Normalizer | ~19 |
| Silver Delete | 3 |
| RSU Processing | ~8 |
| ESPP Processing | ~9 |
| ESOP Processing | 5 |
| Build Orchestration | 5 |
| Integration (real data) | ~10 |
| **Total** | **~59** |
