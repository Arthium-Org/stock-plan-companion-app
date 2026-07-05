# Design Document: M8 — Ingestion Orchestrator

## Overview

M8 is thin glue code that sequences M3–M7 into clean API calls. It manages ingestion records (create, archive, duplicate detection) and is the single entry point for all ingestion operations. No new data processing logic.

### Architecture

```
User / CLI / UI
     |
     v
┌──────────────────────────────────────────┐
│  StockPlan.Ingestions (M8 Orchestrator)   │
│                                          │
│  ingest_benefit_history(account, file)   │
│    1. Validate file exists               │
│    2. Compute file_hash (streaming)      │
│    3. Check duplicate                    │
│    4. Parse XLSX (M3) — OUTSIDE tx       │
│    5. Transaction:                       │
│       a. Archive previous BH             │
│       b. Create ingestion record         │
│       c. Write Bronze (M4)              │
│       d. Rebuild Silver (M5+M6+M7)      │
│    6. Return summary                     │
│                                          │
│  ingest_gl(account, file)                │
│    1-3. Same as above                    │
│    4. Parse (M6 parser) — OUTSIDE tx     │
│    5. Validate ACTIVE BH exists          │
│    6. Transaction: create + bronze +     │
│       silver (no archiving for G&L)      │
│                                          │
│  rebuild(account)                        │
│    → SilverBuilder.build(account)        │
└──────────────────────────────────────────┘
```

## Implementation

```elixir
defmodule StockPlan.Ingestions do
  alias StockPlan.Repo
  alias StockPlan.Schema.Ingestion
  alias StockPlan.Ingestion.{XlsxParser, GlParser, BronzeWriter, SilverBuilder}
  alias StockPlan.ID
  import Ecto.Query

  def ingest_benefit_history(account_id, file_path) do
    # Parse OUTSIDE transaction — no DB state change on parse failure
    with :ok <- validate_file(file_path),
         {:ok, file_hash} <- compute_hash(file_path),
         :ok <- check_duplicate(account_id, file_hash),
         {:ok, rows, parse_warnings} <- XlsxParser.parse(file_path) do
      # DB operations in transaction — atomic
      Repo.transaction(fn ->
        archive_previous_bh(account_id)
        {:ok, ing} = create_ingestion(account_id, file_path, file_hash, "BENEFIT_HISTORY")
        {:ok, bronze_counts} = BronzeWriter.write(ing.ingestion_id, rows)
        {:ok, silver_summary} = SilverBuilder.build(account_id)

        %{
          ingestion_id: ing.ingestion_id,
          bronze: bronze_counts,
          silver: silver_summary,
          parse_warnings: parse_warnings
        }
      end)
    end
  end

  def ingest_gl(account_id, file_path) do
    with :ok <- validate_file(file_path),
         {:ok, file_hash} <- compute_hash(file_path),
         :ok <- check_duplicate(account_id, file_hash),
         :ok <- validate_active_bh(account_id),
         {:ok, rows, parse_warnings} <- GlParser.parse(file_path) do
      Repo.transaction(fn ->
        {:ok, ing} = create_ingestion(account_id, file_path, file_hash, "GL_EXPANDED")
        {:ok, bronze_counts} = BronzeWriter.write(ing.ingestion_id, rows)
        {:ok, silver_summary} = SilverBuilder.build(account_id)

        %{
          ingestion_id: ing.ingestion_id,
          bronze: bronze_counts,
          silver: silver_summary,
          parse_warnings: parse_warnings
        }
      end)
    end
  end

  def rebuild(account_id) do
    SilverBuilder.build(account_id)
  end
end
```

### Helper Functions

```elixir
defp validate_file(path) do
  if File.exists?(path), do: :ok, else: {:error, :file_not_found}
end

defp compute_hash(path) do
  # Streaming hash — avoids loading entire file into memory
  hash = File.stream!(path, 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  {:ok, hash}
end

defp check_duplicate(account_id, file_hash) do
  case Repo.one(from i in Ingestion,
    where: i.account_id == ^account_id and i.file_hash == ^file_hash, limit: 1) do
    nil -> :ok
    existing -> {:error, :duplicate_file, existing.ingestion_id}
  end
end

defp archive_previous_bh(account_id) do
  Repo.update_all(
    from(i in Ingestion,
      where: i.account_id == ^account_id and i.status == "ACTIVE" and i.category == "BENEFIT_HISTORY"),
    set: [status: "ARCHIVED", updated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)]
  )
end

defp validate_active_bh(account_id) do
  case Repo.one(from i in Ingestion,
    where: i.account_id == ^account_id and i.status == "ACTIVE" and i.category == "BENEFIT_HISTORY",
    limit: 1) do
    nil -> {:error, :no_benefit_history}
    _ -> :ok
  end
end

defp create_ingestion(account_id, file_path, file_hash, category) do
  %Ingestion{}
  |> Ingestion.changeset(%{
    ingestion_id: ID.generate(),
    account_id: account_id,
    broker: "ETRADE",
    source_type: "XLSX",
    file_name: Path.basename(file_path),
    file_hash: file_hash,
    status: "ACTIVE",
    category: category
  })
  |> Repo.insert()
end
```

## Transaction Boundary

```
Parse (pure, no DB)          ← OUTSIDE transaction
  |
  v (success)
Transaction:                 ← INSIDE transaction (atomic)
  Archive previous BH
  Create ingestion
  Write Bronze
  Rebuild Silver
  |
  v (commit or rollback)
Return summary
```

If any DB step fails, the entire transaction rolls back — no partial state.

## Summary Output Structure

```elixir
%{
  ingestion_id: "abc123...",
  bronze: %{inserted: 531, skipped: 0},
  silver: %{
    origins: 23,
    tranches: 146,
    sales: 118,
    allocations: 89,
    fx_enriched: %{origins: 23, tranches: 116, sales: 118},
    stock_prices_enriched: %{tranches: 116},
    warnings: []
  },
  parse_warnings: []
}
```

## Contracts

1. **Idempotency:** Re-running ingestion with same file returns `{:error, :duplicate_file, id}`. Bronze/Silver are never duplicated.
2. **Single ingestion at a time:** Phase 1 assumes no concurrent ingestions for the same account. No locking mechanism.
3. **Silver rebuild scope:** `SilverBuilder.build(account_id)` consumes ALL Bronze rows across ALL ACTIVE ingestions for the account. Order: Benefit History first (Phase 1), then G&L (Phase 2), then FX (Phase 3), then Stock Prices (Phase 4).
4. **Duplicate override:** `{:error, :duplicate_file, id}` returns the existing ingestion_id — UI can offer "re-upload anyway" option in the future.

## Error Flow

| Step | Failure | DB Impact | Recovery |
|---|---|---|---|
| File validation | `{:error, :file_not_found}` | None | Fix path |
| Hash computation | Unexpected | None | Retry |
| Duplicate check | `{:error, :duplicate_file, id}` | None | Use existing |
| Parse | `{:error, :parse_failed}` | None | Fix file |
| G&L BH check | `{:error, :no_benefit_history}` | None | Upload BH first |
| Transaction (create+bronze+silver) | Any failure | Full rollback | Retry |
