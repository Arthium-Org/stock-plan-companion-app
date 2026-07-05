# Design Document: M6 — G&L Expanded Ingestion

## Overview

M6 extends the ingestion pipeline to support G&L_Expanded XLSX files. G&L data flows through the standard medallion pipeline: parse → Bronze → Silver (during rebuild). The Silver Builder is extended with a second phase that processes G&L Bronze rows after Benefit History, enriching tranches with vest_fmv and creating RSU sale_allocations. The system works fully without G&L — G&L is optional enrichment.

### Key Design Principles

1. **Bronze for everything**: G&L rows stored in `stock_plan_bronze_raw` like Benefit History. Complete audit trail.
2. **Silver Builder is the single truth builder**: No separate enrichment process. Silver Builder handles both sources during rebuild.
3. **Benefit History first, G&L second**: Phase 1 creates the structure, Phase 2 enriches it. G&L without Benefit History has nothing to enrich.
4. **Rebuild always works**: DELETE + INSERT from all Bronze sources. No data loss from G&L if Benefit History is re-uploaded.
5. **Multiple ingestions coexist**: One ACTIVE Benefit History + N ACTIVE G&L files per account.

### Architecture

```
Benefit History XLSX ──→ M3 Parser ──→ M4 Bronze Writer ──→ bronze_raw (sheet: ESPP/RS/Options)
                                                                    │
G&L_Expanded XLSX ────→ M6 Parser ──→ M4 Bronze Writer ──→ bronze_raw (sheet: G&L_Expanded)
                                                                    │
                                                                    v
                                              ┌──────────────────────────────────┐
                                              │  Silver Builder (M5 extended)    │
                                              │                                 │
                                              │  Phase 1: Benefit History Bronze │
                                              │    → origins, tranches, sales    │
                                              │                                 │
                                              │  Phase 2: G&L Bronze            │
                                              │    → enrich vest_fmv            │
                                              │    → update sale prices          │
                                              │    → create RSU allocations      │
                                              └──────────────────────────────────┘
```

## Components

### 1. G&L Parser (`lib/stock_plan/ingestion/gl_parser.ex`)

Parses G&L_Expanded XLSX into BronzeRow structs. Reuses the same BronzeRow struct from M3.

```elixir
defmodule StockPlan.Ingestion.GlParser do
  @spec parse(String.t()) :: {:ok, [BronzeRow.t()], [warning()]} | {:error, atom()}
  def parse(file_path)
    # 1. Open XLSX, read "G&L_Expanded" sheet
    # 2. Skip Summary rows
    # 3. For each Sell row:
    #    a. Convert Vest Date FMV from NaiveDateTime to decimal
    #    b. Serialize as JSON (sorted keys, values stringified)
    #    c. Compute row_hash
    #    d. Emit BronzeRow with sheet_name: "G&L_Expanded", record_type: "Sell"
    # 4. Return {:ok, rows, warnings}
  end
end
```

**Excel Date Serial Handling:**

xlsxir returns `Vest Date FMV` as NaiveDateTime when Excel stores a number in a date-formatted cell. The parser must convert BEFORE JSON serialization:

```elixir
# ~N[1901-04-17 13:26:24] → "473.56" (the actual FMV value)
defp decode_excel_date_serial(%NaiveDateTime{} = ndt) do
  epoch = ~D[1899-12-30]
  days = Date.diff(NaiveDateTime.to_date(ndt), epoch)
  seconds = NaiveDateTime.to_time(ndt) |> Time.diff(~T[00:00:00])
  Float.round(days + seconds / 86400.0, 6) |> Float.to_string()
end
```

This conversion happens at parse time — the raw_row_json stores the corrected decimal value, not the NaiveDateTime.

**Guard:** Only apply date-serial decoding to KNOWN FMV columns (`Vest Date FMV`, `Exercise Date FMV`). Do NOT apply to actual date columns (`Vest Date`, `Date Sold`, etc.) which are legitimately dates. The parser must distinguish by column name, not by type alone.

**BronzeRow output:**
- `sheet_name`: `"G&L_Expanded"`
- `record_type`: `"Sell"`
- `row_index`: 0-based within the G&L file
- `parent_index`: nil (G&L rows are flat, no parent-child)
- `raw_row_json`: All 47 columns as JSON (sorted keys, values stringified)
- `row_hash`: SHA256 of `"G&L_Expanded:{row_index}:{json}"`

### 2. Ingestion Lifecycle Changes

**Current rule:** Exactly one ACTIVE ingestion per account.  
**New rule:** One ACTIVE Benefit History + N ACTIVE G&L per account.

To support this, add a concept of ingestion category:

Option A: Add `category` field to ingestions (`"BENEFIT_HISTORY"` / `"GL_EXPANDED"`)  
Option B: Derive category from sheet names in Bronze rows  
Option C: Use file naming convention  

**Recommendation: Option A** — explicit `category` field. Clean, queryable, no ambiguity.

New ingestion lifecycle:
- Upload Benefit History → archive previous Benefit History (if exists) → new ACTIVE Benefit History
- Upload G&L → create new ACTIVE G&L ingestion (no archiving of other G&L files)
- Re-upload same G&L (same file_hash) → warn, skip

### 3. Extended Silver Builder

Silver Builder gains Phase 2 after existing Phase 1:

```elixir
def build(account_id) do
  # 1. Validate: exactly 1 ACTIVE Benefit History exists for account
  #    → if 0: {:error, :no_benefit_history}
  #    → if >1: {:error, :multiple_benefit_histories}
  # 2. Delete existing Silver for account
  # 3. Load Benefit History Bronze rows → Phase 1 (existing logic)
  #    → origins, tranches, sales
  # 4. Load G&L Bronze rows (from all ACTIVE G&L ingestions) → Phase 2
  #    → enrich tranches, update sales, create allocations
  # 5. Return summary
end
```

**Guardrails:**
- `build/1` MUST verify exactly 1 ACTIVE Benefit History ingestion for the account
- If no Benefit History: return `{:error, :no_benefit_history}` — do NOT delete existing Silver
- If no G&L ingestions: Phase 2 skipped silently (system works without G&L)

**Phase 2 — G&L Processing:**

```
For each G&L Bronze row:
  1. Parse raw_row_json
  2. Determine plan type (RS or ESPP)
  3. RSU:
     a. Find origin by grant_number
     b. Find tranche by vest_date
     c. Fill vest_fmv on tranche (ONLY if nil — never overwrite)
     d. Find/create sale by matching key (see Sale Matching below)
     e. Fill sale_price + proceeds on sale (ONLY if nil — never overwrite)
     f. Create sale_allocation IF not already exists (check sale_id + tranche_id)
  4. ESPP:
     a. Find origin by grant_date
     b. Find tranche by purchase_date (= vest_date)
     c. Fill sale_price + proceeds (ONLY if nil)
     d. DO NOT create new allocations (M5 already created ESPP allocations)
  5. Unmatched rows → warning
```

**Overwrite Rules (Critical):**
- `IF field is nil → fill from G&L`
- `IF field already has value → DO NOT overwrite (even if G&L has different value)`
- This prevents data corruption from duplicate G&L imports or amended filings

**Recommendation:** `build/1` takes `account_id`. Finds all ACTIVE ingestions, identifies Benefit History vs G&L by category, processes in order.

### 4. G&L Row → Silver Matching

**RSU matching key:** `Grant Number` → origin, `Vest Date` → tranche

```
G&L: Grant Number = "RU383544", Vest Date = "04/15/2024"
  → origin WHERE grant_number = "RU383544"
  → tranche WHERE origin_id = origin.id AND vest_date = ~D[2024-04-15]
```

**ESPP matching key:** `Grant Date` → origin, `Purchase Date` → tranche

```
G&L: Grant Date = "01/04/2021", Purchase Date = "06/30/2022"
  → origin WHERE plan_type = "ESPP" AND origin_date = ~D[2021-01-04]
  → tranche WHERE origin_id = origin.id AND vest_date = ~D[2022-06-30]
```

### 5. Sale Matching Key

**`(origin_id, sale_date)` alone is NOT sufficient** — multiple sells on the same date are common.

**Matching strategy (ordered by preference):**

1. **Primary: `Order Number`** — G&L provides this. Unique per sell order. Store in `sale.metadata_json` for matching.
2. **Fallback: `(origin_id, sale_date, total_quantity)`** — if Order Number absent or sale pre-exists without it.

```
For each G&L row:
  1. IF order_number present:
       Find sale WHERE metadata_json contains order_number
       OR create sale WITH order_number in metadata_json
  2. ELSE:
       Find sale WHERE origin_id + sale_date + total_quantity match
       OR create sale
```

**Multi-lot sales:** One sell order may consume multiple lots. G&L has one row per lot. Multiple G&L rows with the same `Order Number` → one sale, multiple allocations.

**Sale creation rule:** When creating a sale from G&L, `total_quantity` = sum of ALL G&L rows for that `order_number`. Group G&L rows by order_number first, then create sale with aggregated quantity.

**Fallback matching key** (when Order Number absent): `(origin_id, sale_date, quantity, proceeds_per_share)` — includes price to disambiguate same-day/same-quantity trades at different prices.

**G&L processing order:** Process rows sorted by `(sale_date, order_number, row_index)` for deterministic output.

**Sale metadata_json contract for Order Number:**
```json
{"order_number": "89159154"}
```

### 6. Allocation Uniqueness

**Constraint:** `(sale_id, tranche_id)` must be unique in `sale_allocations`.

- Before creating an allocation, check if one already exists for that sale + tranche.
- If it exists: skip (idempotent). Do not create duplicate.
- This handles: duplicate G&L imports, same lot appearing across amended G&L files.

**Invariant:** For each sale, `sum(allocations.quantity)` should equal `sale.total_quantity`. Verified as post-build check — if mismatch detected, add warning (not failure). Mismatch is expected when not all G&L files are ingested yet.

### 7. ESPP Enrichment Clarification

For ESPP G&L rows:
- **DO** fill sale_price and proceeds on the sale (if nil)
- **DO NOT** create new allocations — M5 already creates ESPP allocations from Benefit History parent_index linkage
- **DO NOT** overwrite existing allocation quantities
- G&L for ESPP is price-enrichment only

### 5. Schema Changes

**Ingestion table:** Add `category` field.

```
category TEXT NOT NULL  — "BENEFIT_HISTORY" or "GL_EXPANDED"
```

New lifecycle rule: archive on new upload applies only within the same category.

**No other schema changes needed.** Bronze, origins, tranches, sales, sale_allocations all support G&L data already.

## Data Flow Example

```
Bronze (from Benefit History — ingestion A):
  [Restricted Stock] Grant: RU383544, 2023-01-24, qty=209
  [Restricted Stock] VestSchedule: 04/15/2024
  [Restricted Stock] Event: Shares vested, 04/15/2024, qty=13
  [Restricted Stock] Event: Shares released, 04/15/2024, qty=9
  [Restricted Stock] Event: Shares sold, 05/03/2024, qty=3

Bronze (from G&L 2024 — ingestion B):
  [G&L_Expanded] Sell: RS, Grant=RU383544, VestDate=04/15/2024, Qty=3,
                  DateSold=05/03/2024, ProceedsPerShare=483.83,
                  VestDateFMV=597.46

Silver (after rebuild processing both):
  Origin: {grant_number: RU383544, plan_type: RSU, ...}
  Tranche: {vest_date: 2024-04-15, vest_qty: 13, net_qty: 9, vest_fmv: "597.46", status: VESTED}
                                                               ↑ enriched by G&L
  Sale: {sale_date: 2024-05-03, total_qty: 3, sale_price: "483.83", proceeds: ...}
                                                 ↑ enriched by G&L
  SaleAllocation: {sale→sale, tranche→tranche, quantity: 3}
                   ↑ created by G&L (not possible from Benefit History alone)
```

## Correctness Properties

### Property 1: Silver Without G&L
*For any* account with only Benefit History ingested, Silver SHALL be valid and complete (vest_fmv nil, sale_price nil, no RSU allocations).

### Property 2: G&L Is Additive
*For any* G&L enrichment, no Benefit History-created data SHALL be deleted or overwritten destructively. G&L only fills nil fields and creates new allocations.

### Property 3: Rebuild Incorporates All Sources
*For any* rebuild, Silver SHALL reflect data from ALL ACTIVE ingestions (Benefit History + all G&L files).

### Property 4: Order Independence
*For any* set of G&L files, the order of ingestion SHALL not affect the final Silver state after rebuild.

## Error Handling

| Error Condition | Handling | Impact |
|---|---|---|
| G&L uploaded without Benefit History | Warning — nothing to enrich | G&L Bronze stored, but Phase 2 produces no updates |
| Grant Number not found in Silver | Warning per row | Row skipped |
| Vest Date not found as tranche | Warning per row | Row skipped |
| Duplicate G&L file (same hash) | Warn, skip write | No new Bronze rows |
| NaiveDateTime in FMV column | Convert to decimal | Transparent to downstream |

## Testing Strategy

| Test Type | Coverage | Key Scenarios |
|---|---|---|
| Unit | G&L parser | Parse, Summary skip, NaiveDateTime conversion, JSON serialization |
| Unit | G&L → Silver matching | RSU match by grant+vest, ESPP match by grant_date+purchase |
| Integration | Full pipeline | Benefit History → Bronze → Silver → G&L → Bronze → Silver rebuild → verify enrichment |
| Integration | Without G&L | Benefit History only → Silver valid with nil fields |
| Integration | Rebuild idempotency | Build twice with both sources → same result |
| Integration | Multi-year G&L | Ingest 2023 + 2024 + 2025 G&L → all enrichments applied |

## Implementation Notes

- The G&L parser is simpler than M3 — single sheet, flat rows (no parent-child), only "Sell" type.
- Excel date-serial conversion must happen at PARSE time (before JSON serialization), not at Silver build time. Bronze stores the corrected value.
- The Silver Builder `build/1` signature changes from `build(ingestion_id)` to `build(account_id)`. This is a breaking change to M5's API — tests must be updated.
- Multi-lot sales: Group G&L rows by `Order Number` to identify rows belonging to the same sell order. Create one sale, multiple allocations.
- The `category` field on ingestions is a migration. Add via `mix ecto.gen.migration add_category_to_ingestions`.
