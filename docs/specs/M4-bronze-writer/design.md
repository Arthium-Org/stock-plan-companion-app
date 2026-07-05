# Design Document: M4 — Bronze Writer

## Overview

M4 is a thin persistence layer that takes BronzeRow structs from M3 and inserts them into `stock_plan_bronze_raw` using `Repo.insert_all` with `on_conflict: :nothing` for native dedup. It generates IDs, maps all fields including `parent_index`, validates the ingestion is ACTIVE, and returns insert/skip counts.

### Key Design Principles

1. **Preserve M3 intelligence**: `parent_index` is persisted — M5 doesn't need to re-derive parent-child relationships.
2. **Native dedup**: `insert_all` with `on_conflict: :nothing` — no manual changeset error inspection.
3. **Validate before write**: Check ingestion exists and is ACTIVE before inserting any rows.
4. **Short-circuit on empty**: No transaction for empty input.

### Architecture

```
[%BronzeRow{}, ...]  +  ingestion_id
          |
          v
┌──────────────────────────────────┐
│  StockPlan.Ingestion.BronzeWriter │
│                                  │
│  1. Validate ingestion ACTIVE    │
│  2. Short-circuit if empty       │
│  3. Map rows to DB attrs         │
│  4. insert_all (on_conflict:     │
│     :nothing for dedup)          │
│  5. Return {:ok, counts}         │
└──────────────────────────────────┘
          |
          v
stock_plan_bronze_raw (DB)
```

## Components and Interfaces

### BronzeWriter (`lib/stock_plan/ingestion/bronze_writer.ex`)

```elixir
defmodule StockPlan.Ingestion.BronzeWriter do
  alias StockPlan.Repo
  alias StockPlan.Schema.{BronzeRaw, Ingestion}
  alias StockPlan.Ingestion.BronzeRow
  alias StockPlan.ID

  @spec write(String.t(), [BronzeRow.t()]) ::
          {:ok, %{inserted: non_neg_integer(), skipped: non_neg_integer()}}
          | {:error, atom()}
  def write(_ingestion_id, []), do: {:ok, %{inserted: 0, skipped: 0}}

  def write(ingestion_id, bronze_rows) do
    with {:ok, _ing} <- validate_active_ingestion(ingestion_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      rows =
        Enum.map(bronze_rows, fn row ->
          %{
            id: ID.generate(),
            ingestion_id: ingestion_id,
            sheet_name: row.sheet_name,
            record_type: row.record_type,
            row_index: row.row_index,
            parent_index: row.parent_index,
            raw_row_json: row.raw_row_json,
            row_hash: row.row_hash,
            inserted_at: now,
            updated_at: now
          }
        end)

      {inserted, _} =
        Repo.insert_all(BronzeRaw, rows,
          on_conflict: :nothing,
          conflict_target: [:ingestion_id, :row_hash]
        )

      skipped = length(bronze_rows) - inserted
      {:ok, %{inserted: inserted, skipped: skipped}}
    end
  end

  defp validate_active_ingestion(ingestion_id) do
    case Repo.get(Ingestion, ingestion_id) do
      nil -> {:error, :ingestion_not_found}
      %{status: "ACTIVE"} = ing -> {:ok, ing}
      _ -> {:error, :ingestion_not_active}
    end
  end
end
```

### Field Mapping

| BronzeRow field | BronzeRaw column | Source |
|---|---|---|
| sheet_name | sheet_name | Direct |
| record_type | record_type | Direct |
| row_index | row_index | Direct |
| parent_index | parent_index | Direct — **persisted, not discarded** |
| raw_row_json | raw_row_json | Direct |
| row_hash | row_hash | Direct |
| — | id | Generated via `ID.generate/0` |
| — | ingestion_id | Function parameter |
| — | inserted_at | `DateTime.utc_now()` |
| — | updated_at | `DateTime.utc_now()` |

### Why parent_index Is Persisted

M3 already paid the cost to correctly identify parent-child linkage via `Record Type` scanning. Discarding it would force M5 to re-derive the same information from row ordering — fragile and unnecessary. With `parent_index` in Bronze:

```
M5 query: children = rows WHERE parent_index == parent.row_index AND sheet_name == parent.sheet_name
```

## Correctness Properties

### Property 1: Count Conservation
`inserted + skipped == length(bronze_rows)` for any successful call.

### Property 2: Idempotent
Second call with same ingestion_id + same rows → `inserted: 0, skipped: N`.

### Property 3: Ingestion Gate
Non-existent or ARCHIVED ingestion → `{:error, atom()}` before any rows written.

### Property 4: parent_index Preserved
For any BronzeRow with `parent_index: P`, the corresponding BronzeRaw row has `parent_index == P`.

## Error Handling

| Error Condition | Return |
|---|---|
| Empty input | `{:ok, %{inserted: 0, skipped: 0}}` (short-circuit) |
| Ingestion not found | `{:error, :ingestion_not_found}` |
| Ingestion not ACTIVE | `{:error, :ingestion_not_active}` |
| Dedup (same row_hash) | Row silently skipped, counted |

## Implementation Notes

- `Repo.insert_all` bypasses changesets — validations are upstream (M3 parser ensures correct data).
- `on_conflict: :nothing` with `conflict_target: [:ingestion_id, :row_hash]` maps to SQLite `INSERT OR IGNORE` on the unique index.
- `insert_all` returns `{count, nil}` where count = rows actually inserted.
- Timestamps must be set manually since `insert_all` doesn't invoke Ecto callbacks.
- For very large files, `insert_all` can be chunked (e.g., 500 rows per batch). Not needed for MVP volumes.
