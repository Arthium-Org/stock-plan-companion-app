# Design Document: M3 — XLSX Parser

## Overview

M3 is a pure parsing module that reads E*Trade Benefit History XLSX files and produces BronzeRow structs. It has no database dependency — its output feeds into M4 (Bronze Writer). The parser handles three sheets with different column counts (23/43/31), mixed date formats, parent-child row patterns, and messy broker formatting. It preserves raw data exactly as-is in JSON — no normalization or type coercion happens here.

### Key Design Principles

1. **Pure function**: No side effects, no DB access. Input = file path, output = `{:ok, rows}` or `{:error, reason}`.
2. **Raw preservation**: Cell values stored exactly as the XLSX presents them. No stripping `$`, no date parsing. That's M5's job.
3. **Parent-child linking via index**: `parent_index` enables Silver Builder to group children with their parent without re-parsing.
4. **Fail gracefully**: Missing sheets, empty rows, unrecognized record types — skip and continue, don't crash.
5. **Deterministic**: Same file always produces the same output (row order, hashes).

### Architecture

```
XLSX File (path)
     |
     v
┌─────────────────────────────────────┐
│  StockPlan.Ingestion.XlsxParser     │
│                                     │
│  1. Open XLSX                       │
│  2. For each sheet:                 │
│     a. Read headers (row 0)         │
│     b. For each data row:           │
│        - Classify by Record Type    │
│        - Track parent_index         │
│        - Serialize as JSON          │
│        - Compute row_hash           │
│        - Emit BronzeRow struct      │
│  3. Return {:ok, all_rows}          │
└─────────────────────────────────────┘
     |
     v
[%BronzeRow{}, %BronzeRow{}, ...]
     |
     v
M4: Bronze Writer (writes to DB)
```

## Components and Interfaces

### 1. XlsxParser (`lib/stock_plan/ingestion/xlsx_parser.ex`)

**Responsibility**: Parse XLSX file into BronzeRow structs.

```elixir
defmodule StockPlan.Ingestion.XlsxParser do
  alias StockPlan.Ingestion.BronzeRow

  @sheets ["ESPP", "Restricted Stock", "Options"]

  @type warning :: %{sheet_name: String.t(), row_index: non_neg_integer(), reason: atom()}

  @spec parse(String.t()) :: {:ok, [BronzeRow.t()], [warning()]} | {:error, atom()}
  def parse(file_path) do
    # 1. Validate file exists
    # 2. Open XLSX
    # 3. For each sheet in @sheets (skip if missing)
    #    a. Extract headers (trim whitespace)
    #    b. Parse data rows
    #    c. Collect warnings (orphan children, unrecognized record types)
    # 4. Return {:ok, rows, warnings}
  end
end
```

**Behavior**:
1. Validate file exists and is readable
2. Open XLSX using library (xlsxir or similar)
3. For each expected sheet name, check if sheet exists
4. Extract first row as headers
5. For each subsequent row, classify and emit BronzeRow
6. Track current parent_index per sheet
7. Flatten all sheets into one list, ordered: ESPP → Restricted Stock → Options
8. Return `{:ok, rows}` or `{:error, reason}`

### 2. BronzeRow Struct (`lib/stock_plan/ingestion/bronze_row.ex`)

**Responsibility**: In-memory struct representing one parsed row before DB write.

```elixir
defmodule StockPlan.Ingestion.BronzeRow do
  defstruct [
    :sheet_name,
    :record_type,
    :row_index,
    :parent_index,
    :raw_row_json,
    :row_hash
  ]

  @type t :: %__MODULE__{
    sheet_name: String.t(),
    record_type: String.t(),
    row_index: non_neg_integer(),
    parent_index: non_neg_integer() | nil,
    raw_row_json: String.t(),
    row_hash: String.t()
  }
end
```

**Fields**:
- `sheet_name`: Exact sheet name (`"ESPP"`, `"Restricted Stock"`, `"Options"`)
- `record_type`: Classified type (`"Grant"`, `"Purchase"`, `"Event"`, `"Vest Schedule"`)
- `row_index`: 0-based position in sheet (excluding header row)
- `parent_index`: row_index of nearest preceding parent (nil for parent rows)
- `raw_row_json`: JSON string of `{column_header: cell_value}` pairs
- `row_hash`: SHA256 hex of raw_row_json (64-char lowercase)

### 3. Row Classification Logic

```
Record Type Value     → record_type field    → Role
─────────────────────────────────────────────────────
"Grant"              → "Grant"              → Parent (RSU, ESOP)
"Purchase"           → "Purchase"           → Parent (ESPP)
"Event"              → "Event"              → Child
"Vest Schedule"      → "Vest Schedule"      → Child
"Totals"             → (skip)              → Not emitted
nil / empty / other  → (skip)              → Not emitted
```

### 4. Parent-Child Index Tracking

```
Sheet: Restricted Stock
─────────────────────────
Row 0: Record Type = "Grant"   → parent_index = nil, current_parent = 0
Row 1: Record Type = "Event"   → parent_index = 0
Row 2: Record Type = "Event"   → parent_index = 0
Row 3: Record Type = "Vest Schedule" → parent_index = 0
Row 4: Record Type = "Grant"   → parent_index = nil, current_parent = 4
Row 5: Record Type = "Event"   → parent_index = 4
Row 6: Record Type = "Totals"  → (skip)
```

### 5. XLSX Library Choice

**Recommended: `xlsxir`** (Hex package)
- Mature, well-maintained
- Reads .xlsx files into Elixir data structures
- Supports reading specific sheets by name or index
- Returns rows as lists of cell values
- Handles empty cells as nil

Alternative: `xlsx_reader` — lighter but less feature-rich.

**Library interface we depend on:**
- Open file → get sheet names
- Read sheet by name → get rows as list of lists
- First row = headers, subsequent rows = data
- Close/cleanup after reading

### 6. JSON Serialization

For each data row, create an ordered list of `{header, value}` pairs and encode with Jason. **Key ordering must be deterministic** (sorted alphabetically) to ensure consistent row_hash across runs:

```elixir
defp row_to_json(headers, row_values) do
  headers
  |> Enum.zip(pad_or_trim(row_values, length(headers)))
  |> Enum.sort_by(fn {key, _} -> key end)
  |> Jason.encode!(maps: :strict)
end
```

**Critical:** Map key ordering in Elixir/JSON is not guaranteed. Sorting keys before encoding ensures the same row always produces the same JSON string → same row_hash. Without this, hash-based dedup breaks.

**One rule for all cell values: convert to string, except nil → null.**

- Strings stay as strings (e.g., `"$72.36"`, `"24-JAN-2025"`)
- Numbers from XLSX (floats/integers) → convert to string via `to_string/1`
- Booleans → `"true"` / `"false"`
- nil → `null` in JSON

This avoids float precision surprises in JSON encoding and ensures deterministic hashing. All values in `raw_row_json` are strings or null — no mixed types.

## Correctness Properties

### Property 1: Deterministic Output
*For any* XLSX file, parsing it twice shall produce identical BronzeRow lists (same order, same hashes).

### Property 2: Row Count Conservation
*For any* sheet, the number of emitted BronzeRows shall equal the number of data rows minus Totals rows minus empty/nil Record Type rows.

### Property 3: Parent-Child Integrity
*For any* Child_Row in the output, its `parent_index` shall reference a Parent_Row with a lower `row_index` in the same sheet.

### Property 4: Hash Determinism
*For any* BronzeRow, `row_hash == :crypto.hash(:sha256, raw_row_json) |> Base.encode16(case: :lower)`.

## Error Handling

| Error Condition | Return Value | Notes |
|---|---|---|
| File doesn't exist | `{:error, :file_not_found}` | Check before attempting open |
| File isn't valid XLSX | `{:error, :invalid_format}` | Catch library parse errors |
| Sheet missing | Skip silently | Not all users have all plan types |
| Child before any parent | Skip row, log warning | Edge case in malformed data |
| Unrecognized Record Type | Skip row, log warning | Future-proofing |
| Empty sheet (headers only) | No rows emitted for that sheet | Normal case |

## Testing Strategy

| Test Type | Coverage | Key Scenarios |
|---|---|---|
| Unit | Row classification | Each Record Type value → correct classification |
| Unit | Parent-child linking | Sequential parents/children, orphan children |
| Unit | JSON serialization | Headers + values → correct JSON, nil handling |
| Unit | Hash generation | Deterministic, correct format |
| Integration | Full parse of sample XLSX | Real file from `docs/Sample-Data/` |
| Integration | Error cases | Missing file, invalid file, missing sheets |

## Implementation Notes

- Add `xlsxir` (or chosen library) to `mix.exs` dependencies.
- The parser is stateless — no GenServer, no process. Just a module with functions.
- `parent_index` tracking is per-sheet (resets when moving to next sheet).
- Row index is 0-based from first data row (header row is not counted).
- The sample XLSX files in `docs/Sample-Data/` should be used as integration test fixtures.
- Large files: xlsxir can handle thousands of rows. No streaming needed for single-user volumes.
- The BronzeRow struct is NOT an Ecto schema — it's a plain struct for in-memory use. M4 maps it to the BronzeRaw Ecto schema for DB insert.
