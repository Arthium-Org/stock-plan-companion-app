# Requirements Document: M3 — XLSX Parser

## Introduction

The XLSX Parser module reads E*Trade Benefit History XLSX files and produces in-memory Bronze row structs. It is a pure function — no database access, no side effects. It reads a file path, extracts rows from three sheets (ESPP, Restricted Stock, Options), classifies each row by Record Type, preserves the raw data as JSON, and returns a list of structs ready for the Bronze Writer (M4). The parser handles the messy broker format: mixed date formats, currency strings, parent-child row linking, and empty cells.

## Glossary

- **BronzeRow**: An in-memory struct representing one raw row from the XLSX — contains sheet_name, record_type, row_index, parent_index, raw_row_json, row_hash
- **Record_Type**: Column A in each sheet — determines if a row is a parent (Grant/Purchase), child (Event/Vest Schedule), or skip (Totals)
- **Parent_Row**: A Grant or Purchase row that starts a new group. Children belong to the nearest preceding parent.
- **Child_Row**: An Event or Vest Schedule row that belongs to the nearest preceding Parent_Row.
- **parent_index**: The row_index of the parent that a child belongs to — enables parent-child linkage without parsing semantics.
- **raw_row_json**: The full row serialized as JSON with column headers as keys — preserves all original data.
- **row_hash**: SHA256 of raw_row_json — used for dedup within an ingestion.

## Requirements

### Requirement 1: File Reading

**User Story:** As a developer, I want to read an E*Trade Benefit History XLSX file from a path, so that I can extract raw data from all sheets.

#### Acceptance Criteria

1. WHEN given a valid XLSX file path, THE Parser SHALL open and read the file without errors
2. WHEN given a non-existent file path, THE Parser SHALL return `{:error, :file_not_found}`
3. WHEN given a non-XLSX file, THE Parser SHALL return `{:error, :invalid_format}`
4. THE Parser SHALL extract data from sheets named `ESPP`, `Restricted Stock`, and `Options`
5. IF a sheet is missing from the file, THE Parser SHALL skip it without error (some users may not have all plan types)
6. THE Parser SHALL not modify the source file

### Requirement 2: Row Classification

**User Story:** As a developer, I want each row classified by its Record Type, so that downstream modules know how to interpret it.

#### Acceptance Criteria

1. THE Parser SHALL read column A (`Record Type`) to classify each row
2. WHEN Record_Type is `Grant` or `Purchase`, THE Parser SHALL classify the row as a Parent_Row
3. WHEN Record_Type is `Event`, THE Parser SHALL classify the row as a Child_Row with record_type `"Event"`
4. WHEN Record_Type is `Vest Schedule`, THE Parser SHALL classify the row as a Child_Row with record_type `"Vest Schedule"`
5. WHEN Record_Type is `Totals`, THE Parser SHALL skip the row entirely (not included in output)
6. WHEN Record_Type is empty or nil, THE Parser SHALL skip the row
7. WHEN Record_Type is an unrecognized value, THE Parser SHALL skip the row and add a warning to the warnings list

### Requirement 3: Parent-Child Linking

**User Story:** As a developer, I want child rows linked to their parent, so that the Silver Builder knows which grant/purchase each event belongs to.

#### Acceptance Criteria

1. THE Parser SHALL track the row_index of the most recent Parent_Row per sheet
2. FOR EACH Child_Row, THE Parser SHALL set `parent_index` to the row_index of the nearest preceding Parent_Row
3. IF a Child_Row appears before any Parent_Row in a sheet, THE Parser SHALL skip it and add a warning to the warnings list
4. Parent_Rows SHALL have `parent_index` set to nil (they are self-referential roots)

### Requirement 4: Raw Row Serialization

**User Story:** As a developer, I want each row serialized as JSON with column headers as keys, so that Bronze preserves the exact original data.

#### Acceptance Criteria

1. THE Parser SHALL read the first row of each sheet as column headers and trim whitespace from each header
2. THE Parser SHALL serialize each data row as a JSON object where keys are column headers and values are cell contents
3. WHEN a cell is empty or nil, THE Parser SHALL represent it as `null` in the JSON
4. THE Parser SHALL NOT normalize, clean, or transform any cell values — raw data only
5. THE Parser SHALL preserve the original string representation of all cells (no type coercion)

### Requirement 5: Row Hash Generation

**User Story:** As a developer, I want a deterministic hash per row, so that duplicate rows within the same ingestion can be detected.

#### Acceptance Criteria

1. THE Parser SHALL compute `row_hash` as the SHA256 hex digest of `raw_row_json`
2. FOR THE SAME raw_row_json, THE Parser SHALL always produce the same row_hash
3. THE row_hash SHALL be a 64-character lowercase hex string
4. THE Parser SHALL sort JSON keys alphabetically before encoding to ensure deterministic output regardless of map iteration order

### Requirement 6: Output Format

**User Story:** As a developer, I want the parser to return a flat list of BronzeRow structs, so that the Bronze Writer can batch-insert them.

#### Acceptance Criteria

1. THE Parser SHALL return `{:ok, [%BronzeRow{}, ...], warnings}` on success where each warning is `%{sheet_name: String.t(), row_index: integer(), reason: atom()}`
2. EACH BronzeRow SHALL contain: `sheet_name`, `record_type`, `row_index`, `parent_index`, `raw_row_json`, `row_hash`
3. `sheet_name` SHALL be the exact sheet name from the XLSX (`"ESPP"`, `"Restricted Stock"`, `"Options"`)
4. `record_type` SHALL be one of: `"Grant"`, `"Purchase"`, `"Event"`, `"Vest Schedule"`
5. `row_index` SHALL be 0-based position within the sheet (excluding header row)
6. THE output list SHALL be ordered by sheet (ESPP first, then Restricted Stock, then Options), then by row_index within each sheet
7. THE Parser SHALL return `{:ok, [], []}` if no valid data rows are found

### Requirement 7: Robustness

**User Story:** As a developer, I want the parser to handle real-world XLSX quirks without crashing.

#### Acceptance Criteria

1. WHEN a sheet has only a header row and no data, THE Parser SHALL return no rows for that sheet
2. WHEN a row has fewer columns than headers, THE Parser SHALL pad missing values with nil
3. WHEN a row has more columns than headers, THE Parser SHALL ignore extra columns
4. THE Parser SHALL handle sheets with thousands of rows without memory issues
5. THE Parser SHALL not crash on any valid XLSX file — errors are returned, not raised
