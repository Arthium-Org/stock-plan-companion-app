# Test Plan: M3 — XLSX Parser

## TDD Workflow

Write tests first → RED → implement → GREEN → refactor.

---

## TP-1: BronzeRow Struct

**File:** `test/stock_plan/ingestion/bronze_row_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Create struct with all fields | All fields accessible |
| TP-1.2 | Default struct | All fields are nil |

---

## TP-2: Row Hash

**File:** `test/stock_plan/ingestion/xlsx_parser_test.exs` (hash section)

| Test ID | Input | Assertion |
|---|---|---|
| TP-2.1 | `compute_hash("{"A":"1"}")` twice | Same result both times |
| TP-2.2 | Any input | Result is 64-char lowercase hex string |
| TP-2.3 | Two different inputs | Different hashes |

---

## TP-3: Row Classification

**File:** `test/stock_plan/ingestion/xlsx_parser_test.exs` (classification section)

| Test ID | Record Type Value | Expected |
|---|---|---|
| TP-3.1 | `"Grant"` | `{:parent, "Grant"}` |
| TP-3.2 | `"Purchase"` | `{:parent, "Purchase"}` |
| TP-3.3 | `"Event"` | `{:child, "Event"}` |
| TP-3.4 | `"Vest Schedule"` | `{:child, "Vest Schedule"}` |
| TP-3.5 | `"Totals"` | `:skip` |
| TP-3.6 | `nil` | `:skip` |
| TP-3.7 | `""` | `:skip` |
| TP-3.8 | `"Something Else"` | `:skip` |

---

## TP-4: JSON Serialization

**File:** `test/stock_plan/ingestion/xlsx_parser_test.exs` (json section)

| Test ID | Headers | Values | Expected JSON (decoded) |
|---|---|---|---|
| TP-4.1 | `["Symbol", "Date"]` | `["ADBE", "24-JAN-2025"]` | `%{"Symbol" => "ADBE", "Date" => "24-JAN-2025"}` |
| TP-4.2 | `["A", "B"]` | `[nil, nil]` | `%{"A" => nil, "B" => nil}` |
| TP-4.3 | `["A", "B", "C"]` | `["x", "y"]` | `%{"A" => "x", "B" => "y", "C" => nil}` (short row padded) |
| TP-4.4 | `["A", "B"]` | `["x", "y", "z"]` | `%{"A" => "x", "B" => "y"}` (extra ignored) |
| TP-4.5 | `["Price"]` | `[72.36]` | `%{"Price" => "72.36"}` or `%{"Price" => 72.36}` (number preserved) |

---

## TP-5: Parent-Child Index Tracking

**File:** `test/stock_plan/ingestion/xlsx_parser_test.exs` (linking section)

| Test ID | Row Sequence | Expected parent_index values |
|---|---|---|
| TP-5.1 | [Grant(0), Event(1), Event(2)] | [nil, 0, 0] |
| TP-5.2 | [Grant(0), Event(1), Grant(2), Event(3)] | [nil, 0, nil, 2] |
| TP-5.3 | [Grant(0), VestSched(1), Event(2), Grant(3)] | [nil, 0, 0, nil] |
| TP-5.4 | [Event(0)] (orphan — no parent yet) | row skipped |
| TP-5.5 | [Totals(0), Grant(1), Event(2)] | skip Totals → [nil, 1] (re-index) |

---

## TP-6: Single Sheet Parse

**File:** `test/stock_plan/ingestion/xlsx_parser_test.exs` (single sheet section)

Test with a constructed in-memory sheet (mock the xlsxir output):

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Sheet with 2 Grant + 3 Event rows + 1 Totals | Returns 5 BronzeRows (Totals skipped) |
| TP-6.2 | Correct sheet_name on all rows | All have expected sheet name |
| TP-6.3 | Correct record_type | Parents = "Grant", children = "Event" |
| TP-6.4 | Correct row_index | Sequential 0-based |
| TP-6.5 | Correct parent_index | Children linked to their parent |
| TP-6.6 | raw_row_json is valid JSON | `Jason.decode!/1` succeeds on each |
| TP-6.7 | row_hash is 64-char hex | Matches `~r/^[0-9a-f]{64}$/` |

---

## TP-7: Full Parser (Multi-Sheet + Errors)

**File:** `test/stock_plan/ingestion/xlsx_parser_test.exs` (full parser section)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | Non-existent file path | `{:error, :file_not_found}` |
| TP-7.2 | Invalid file (not XLSX) | `{:error, :invalid_format}` |
| TP-7.3 | Valid XLSX — returns `{:ok, rows}` | rows is a list of BronzeRow structs |
| TP-7.4 | Rows ordered: ESPP first, then Restricted Stock, then Options | Sheet order correct |
| TP-7.5 | XLSX with missing sheet | Succeeds with rows from available sheets |
| TP-7.6 | Empty file (headers only) | `{:ok, []}` |

---

## TP-8: Integration with Real Sample Data

**File:** `test/stock_plan/ingestion/xlsx_parser_integration_test.exs`

Uses actual files from `docs/Sample-Data/`.

| Test ID | File | Assertion |
|---|---|---|
| TP-8.1 | SampleUser-1 BenefitHistory.xlsx | `{:ok, rows}` where rows is non-empty |
| TP-8.2 | All rows have sheet_name ∈ `["ESPP", "Restricted Stock", "Options"]` | Correct classification |
| TP-8.3 | All rows have record_type ∈ `["Grant", "Purchase", "Event", "Vest Schedule"]` | No Totals leaked |
| TP-8.4 | All parent rows have parent_index = nil | Correct |
| TP-8.5 | All child rows have parent_index != nil | Linked |
| TP-8.6 | All row_hash values are 64-char hex | Format correct |
| TP-8.7 | No duplicate row_hash within same sheet | Dedup would work |
| TP-8.8 | SampleUser-2 BenefitHistory.xlsx | Same assertions pass |
| TP-8.9 | Count total rows parsed | Non-trivial count (sanity check) |

---

## Test Fixtures

### Small Fixture for Unit Tests

Create a minimal test XLSX or mock the library output directly:

```elixir
# Mock sheet data for unit tests (bypass xlsxir)
@restricted_stock_data [
  ["Record Type", "Symbol", "Grant Date", "Granted Qty", "Grant Number"],  # headers
  ["Grant", "ADBE", "24-JAN-2025", "100", "RU422478"],                    # parent
  ["Event", nil, "01/27/2025", "25", nil],                                 # child
  ["Event", nil, "01/27/2025", "9", nil],                                  # child
  ["Vest Schedule", nil, "07/24/2025", "25", nil],                         # child
  ["Grant", "ADBE", "15-MAR-2024", "200", "RU398001"],                    # parent
  ["Event", nil, "03/15/2024", "50", nil],                                 # child
  ["Totals", nil, nil, "300", nil]                                         # skip
]
```

### Real Files for Integration Tests

```
test/fixtures/  (symlink or copy)
  OR
docs/Sample-Data/SampleUser - 1/sample-Etrade-BenefitHistory.xlsx  (read directly)
```

Recommend reading directly from `docs/Sample-Data/` to avoid duplicating large binary files.

---

## Test Count Summary

| Test File | Unit | Integration | Total |
|---|---|---|---|
| bronze_row_test.exs | 2 | 0 | 2 |
| xlsx_parser_test.exs | ~25 | 6 | ~31 |
| xlsx_parser_integration_test.exs | 0 | ~10 | ~10 |
| **Total** | **~27** | **~16** | **~43** |
