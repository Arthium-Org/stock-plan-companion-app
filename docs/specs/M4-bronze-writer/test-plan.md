# Test Plan: M4 — Bronze Writer

## TDD Workflow

Write tests first → RED → implement → GREEN.

---

## TP-1: Core Write Functionality

**File:** `test/stock_plan/ingestion/bronze_writer_test.exs`

### TP-1.1: Basic Operations

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1.1 | Write empty list | `{:ok, %{inserted: 0, skipped: 0}}` (short-circuit, no DB call) |
| TP-1.1.2 | Write 3 BronzeRow structs | `{:ok, %{inserted: 3, skipped: 0}}` |
| TP-1.1.3 | Written rows exist in DB | `Repo.aggregate(BronzeRaw, :count) == 3` |
| TP-1.1.4 | Written rows have correct ingestion_id | All rows match the given ingestion_id |
| TP-1.1.5 | Written rows have generated IDs (16-char hex) | All IDs match `~r/^[0-9a-f]{16}$/` |
| TP-1.1.6 | Written rows have timestamps | `inserted_at` and `updated_at` not nil |
| TP-1.1.7 | parent_index persisted correctly | Parent row: nil, child row: parent's row_index |

### TP-1.2: Dedup

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.2.1 | Write same rows twice (same ingestion_id) | Second call: `{:ok, %{inserted: 0, skipped: 3}}` |
| TP-1.2.2 | Total DB rows after two writes | Still 3 (not 6) |
| TP-1.2.3 | inserted + skipped = input length | Always true |
| TP-1.2.4 | Same row_hash in different ingestion | Both insert (unique is per-ingestion) |

### TP-1.3: Ingestion Validation

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.3.1 | Non-existent ingestion_id | `{:error, :ingestion_not_found}` |
| TP-1.3.2 | Archived ingestion | `{:error, :ingestion_not_active}` |
| TP-1.3.3 | Active ingestion | Proceeds with write |

---

## TP-2: End-to-End Pipeline (M3 → M4)

**File:** `test/stock_plan/ingestion/bronze_writer_test.exs` (pipeline section)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Parse sample XLSX → write to bronze | `{:ok, %{inserted: N, skipped: 0}}` where N > 0 |
| TP-2.2 | Row count in DB matches parsed count | `Repo.aggregate(BronzeRaw, :count) == length(parsed_rows)` |
| TP-2.3 | Re-write same parsed rows | `{:ok, %{inserted: 0, skipped: N}}` |
| TP-2.4 | Sample row from DB has valid raw_row_json | `Jason.decode!/1` succeeds |
| TP-2.5 | Sample row has correct sheet_name | One of expected sheets |
| TP-2.6 | Parent rows have parent_index nil in DB | All Grant/Purchase rows |
| TP-2.7 | Child rows have parent_index set in DB | All Event/VestSchedule rows |

---

## Test Count Summary

| Section | Tests |
|---|---|
| Basic operations | 7 |
| Dedup | 4 |
| Ingestion validation | 3 |
| End-to-end pipeline | 7 |
| **Total** | **~21** |
