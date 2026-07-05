# Tasks: M3 — XLSX Parser

## Development Approach: TDD

Each task follows Red → Green → Refactor:
1. Write tests first (from test-plan.md)
2. Run tests — confirm FAIL (red)
3. Implement minimum code to pass
4. Run tests — confirm PASS (green)

## Prerequisites

- M1: Phoenix app scaffold (for mix deps)
- M2: BronzeRaw schema exists (for struct field alignment)
- Sample XLSX files in `docs/Sample-Data/`

---

## Task 0: Add XLSX Library Dependency

- [ ] 0.1 Add `{:xlsxir, "~> 1.6"}` (or latest) to `mix.exs` deps
- [ ] 0.2 Run `mix deps.get`
- [ ] 0.3 Run `mix compile --warnings-as-errors` — clean
- [ ] 0.4 Verify xlsxir can open sample XLSX: quick manual test in `iex -S mix`

---

## Task 1: BronzeRow Struct

Create the in-memory struct for parsed rows.

**TDD: Write tests first, then implement.**

- [ ] 1.1 **RED**: Write `test/stock_plan/ingestion/bronze_row_test.exs`
  - Struct can be created with all fields
  - Struct has correct default nil values
- [ ] 1.2 **GREEN**: Create `lib/stock_plan/ingestion/bronze_row.ex` with defstruct + @type
- [ ] 1.3 Run tests — PASS

---

## Task 2: Row Hash Generation

Implement deterministic SHA256 hashing of raw_row_json.

**TDD: Write tests first, then implement.**

- [ ] 2.1 **RED**: Write hash tests in `test/stock_plan/ingestion/xlsx_parser_test.exs`
  - Same input → same hash
  - Hash is 64-char lowercase hex
  - Different input → different hash
- [ ] 2.2 **GREEN**: Implement `compute_hash/1` private function in XlsxParser
- [ ] 2.3 Run tests — PASS

---

## Task 3: Row Classification

Implement Record Type → record_type mapping.

**TDD: Write tests first, then implement.**

- [ ] 3.1 **RED**: Write classification tests
  - "Grant" → `"Grant"` (parent)
  - "Purchase" → `"Purchase"` (parent)
  - "Event" → `"Event"` (child)
  - "Vest Schedule" → `"Vest Schedule"` (child)
  - "Totals" → `:skip`
  - nil → `:skip`
  - "" → `:skip`
  - "Unknown" → `:skip`
- [ ] 3.2 **GREEN**: Implement `classify_row/1` function
- [ ] 3.3 Run tests — PASS

---

## Task 4: JSON Serialization

Implement headers + row values → JSON string.

**TDD: Write tests first, then implement.**

- [ ] 4.1 **RED**: Write serialization tests
  - Headers ["A", "B"] + values ["x", "y"] → `{"A":"x","B":"y"}`
  - Nil values → `{"A":null}` in JSON
  - Row shorter than headers → missing values are null
  - Row longer than headers → extra values ignored
  - Numeric values preserved as-is (number or string depending on library output)
- [ ] 4.2 **GREEN**: Implement `row_to_json/2` function
- [ ] 4.3 Run tests — PASS

---

## Task 5: Parent-Child Index Tracking

Implement parent_index assignment during sheet parsing.

**TDD: Write tests first, then implement.**

- [ ] 5.1 **RED**: Write parent-child linking tests
  - Parent row gets parent_index = nil
  - First child after parent gets parent_index = parent's row_index
  - Multiple children share same parent_index
  - New parent resets current_parent
  - Child before any parent is skipped
- [ ] 5.2 **GREEN**: Implement `parse_sheet/2` with parent tracking state
- [ ] 5.3 Run tests — PASS

---

## Task 6: Full Parser — Single Sheet

Implement end-to-end parsing for one sheet.

**TDD: Write tests first, then implement.**

- [ ] 6.1 **RED**: Write single-sheet parse tests (use a small test fixture)
  - Parse sheet with 2 parents, 3 children each → 8 BronzeRows
  - Totals row skipped
  - Correct sheet_name, record_type, row_index on each
  - Correct parent_index linking
  - raw_row_json contains expected JSON
  - row_hash is 64-char hex
- [ ] 6.2 **GREEN**: Implement `parse_sheet/3` that combines classification + linking + serialization
- [ ] 6.3 Run tests — PASS

---

## Task 7: Full Parser — Multi-Sheet + Error Handling

Implement the public `parse/1` API with all three sheets and error cases.

**TDD: Write tests first, then implement.**

- [ ] 7.1 **RED**: Write full parser tests
  - Non-existent file → `{:error, :file_not_found}`
  - Invalid file (e.g., .txt renamed to .xlsx) → `{:error, :invalid_format}`
  - Valid XLSX with all 3 sheets → `{:ok, rows}` with correct ordering
  - XLSX with missing sheet (e.g., no Options) → succeeds with rows from other sheets
  - Empty XLSX (headers only) → `{:ok, []}`
- [ ] 7.2 **GREEN**: Implement `parse/1` public function
- [ ] 7.3 Run tests — PASS

---

## Task 8: Integration Test with Sample Data

Parse the actual sample XLSX files and verify output.

- [ ] 8.1 Write integration test using `docs/Sample-Data/SampleUser - 1/sample-Etrade-BenefitHistory.xlsx`
  - Parse succeeds with `{:ok, rows}`
  - rows is non-empty list
  - All rows have valid sheet_name ∈ expected set
  - All rows have valid record_type
  - All parent rows have parent_index = nil
  - All child rows have parent_index != nil
  - row_hash format is correct (64-char hex)
  - No duplicate row_hash values within same sheet
- [ ] 8.2 Write integration test using `docs/Sample-Data/SampleUser - 2/BenefitHistory.xlsx`
  - Same assertions as 8.1
- [ ] 8.3 Run `mix test` — full suite passes

---

## Task 9: Full Verification

- [ ] 9.1 Run `mix format --check-formatted` — pass
- [ ] 9.2 Run `mix compile --warnings-as-errors` — zero warnings
- [ ] 9.3 Run `mix test` — all tests pass (M1 + M2 + M3)

---

## Definition of Done

M3 is complete when ALL of the following are true:

- [ ] `mix format --check-formatted` passes
- [ ] `mix compile --warnings-as-errors` zero application warnings
- [ ] `mix test` passes — all parser unit tests + integration tests with real XLSX files
- [ ] Both sample XLSX files parse successfully without errors
- [ ] BronzeRow struct aligns with BronzeRaw schema fields (ready for M4 to insert)
- [ ] Parser is pure — no DB access, no side effects
- [ ] Git repo clean

---

## Notes

- **Implementation priority**: Tasks 1-5 build individual pieces. Task 6 composes them for one sheet. Task 7 adds multi-sheet + errors. Task 8 validates against real data.
- **Key constraint**: Parser must NOT normalize data — raw preservation only. No stripping `$`, no date parsing. That's M5's responsibility.
- **Testing approach**: Unit tests with small fixtures for Tasks 1-6. Integration tests with real XLSX for Tasks 7-8.
- **Risk**: xlsxir may return numeric cells as floats vs strings. Need to verify with real data and handle consistently (convert to string for JSON).
- **Library version**: Check xlsxir compatibility with OTP 28 / Elixir 1.19.
