# Design Document: M5 — Silver Builder

## Overview

M5 reads Bronze rows for an ACTIVE ingestion, parses raw JSON values, and creates structured Silver records. It's the core financial interpretation layer — it decides what each row means based on plan type and event type. The builder runs as a full rebuild (DELETE + INSERT) to ensure Silver always matches the latest Bronze state.

### Key Design Principles

1. **Full rebuild**: Delete all Silver for the account, then recreate. No incremental updates.
2. **Bronze is source of truth**: Silver is always derivable from Bronze. If Silver is wrong, rebuild.
3. **Plan-type dispatch**: RSU, ESPP, ESOP each have dedicated processing logic — no god-function.
4. **Normalize once**: Raw values cleaned in one place (ValueNormalizer), then used consistently.
5. **parent_index for grouping**: Use persisted parent_index from Bronze to link children to parents.
6. **FX rates deferred**: Phase 1 leaves fx_rate fields nil. FX service (M7) fills them later.

### Architecture

```
stock_plan_bronze_raw (for ACTIVE ingestion)
     |
     v
┌─────────────────────────────────────────────┐
│  StockPlan.Ingestion.SilverBuilder          │
│                                             │
│  1. Validate ingestion ACTIVE               │
│  2. Delete existing Silver for account      │
│  3. Load Bronze rows, group by sheet        │
│  4. For each sheet:                         │
│     a. Group rows by parent (parent_index)  │
│     b. Dispatch to plan-type processor      │
│  5. Return summary                          │
│                                             │
│  Plan Processors:                           │
│  ├── process_rsu(parent, children)          │
│  ├── process_espp(parents_by_enrollment)    │
│  └── process_esop(parent, children)         │
│                                             │
│  Helpers:                                   │
│  └── ValueNormalizer (strip $/%/,, dates)   │
└─────────────────────────────────────────────┘
     |
     v
stock_plan_origins, stock_plan_tranches,
stock_plan_sales, stock_plan_sale_allocations
```

## Components and Interfaces

### 1. SilverBuilder (`lib/stock_plan/ingestion/silver_builder.ex`)

**Public API:**

```elixir
defmodule StockPlan.Ingestion.SilverBuilder do
  @spec build(String.t()) :: {:ok, map()} | {:error, atom()}
  def build(ingestion_id) do
    # 1. Validate ingestion ACTIVE, get account_id
    # 2. Delete Silver for account (in FK order)
    # 3. Load Bronze rows for ingestion
    # 4. Group by sheet_name
    # 5. Process "Restricted Stock" → RSU origins + tranches + sales
    # 6. Process "ESPP" → ESPP origins + tranches + sales
    # 7. Process "Options" → ESOP origins + tranches (if sheet exists)
    # 8. Return {:ok, %{origins: N, tranches: N, sales: N, allocations: N, warnings: [%{type, sheet, ...}]}}
  end
end
```

### 2. RSU Processor

**Input:** One Grant parent row + its children (Events + Vest Schedules).

**Logic:**

```
Grant parent → Origin (plan_type: RSU)
  Fields: symbol, grant_date, grant_number, total_quantity (Granted Qty)

Vest Schedule children → UNVESTED Tranches
  Fields: vest_date, vest_quantity (nil if not present — never derive)

Event children by type:
  "Shares granted"  → SKIP (redundant)
  "Shares vested"   → Find tranche by vest_date → set vest_quantity, status=VESTED (vest_fmv nil)
  "Shares released"  → Find tranche by vest_date → set net_quantity (post-tax)
  "Shares sold"     → Create Sale only (NO allocation — lot linkage unknown from Benefit History)
```

**RSU Vest/Release pairing:**
E*Trade reports vesting as TWO events on the same date:
- "Shares vested" (qty=7) — gross shares that vested
- "Shares released" (qty=5) — net shares after tax withholding

These are paired by date. The tranche gets:
- `vest_quantity` = vested qty (7)
- `net_quantity` = released qty (5) 
- `tax_withheld_qty` = 7 - 5 = 2

### 3. ESPP Processor

**Input:** All Purchase parent rows from ESPP sheet, grouped by Grant Date.

**Logic:**

```
Group Purchase rows by Grant Date → one Origin per enrollment period

For each enrollment (Grant Date group):
  Origin (plan_type: ESPP)
    origin_date = Grant Date
    origin_fmv = Grant Date FMV (lock-in price)
    grant_number = hash("ESPP:{symbol}:{grant_date}")
    metadata = {discount_percent, qualified_plan}

  For each Purchase in the group:
    Tranche (VESTED)
      vest_date = Purchase Date
      vest_quantity = Purchased Qty
      vest_fmv = Purchase Date FMV
      tax_withheld_qty = Tax Collection Shares
      net_quantity = Net Shares
      metadata = {buy_price: Purchase Price}

  For each SELL event child of any Purchase in the group:
    Sale + SaleAllocation → linked to parent's tranche
```

### 4. ESOP Processor

**Input:** One Options Grant parent + its children.

**Logic:**

```
Grant parent → Origin (plan_type: ESOP)
  metadata = {strike_price, option_type}

Vest Schedule → UNVESTED Tranches
"Shares vested" → update tranche to VESTED
"Shares exercised" → create Exercise record
"Shares granted" → SKIP
```

### 5. ValueNormalizer (`lib/stock_plan/ingestion/value_normalizer.ex`)

```elixir
defmodule StockPlan.Ingestion.ValueNormalizer do
  @doc "Strip $, %, commas from a value and return clean string or nil"
  def clean_number(nil), do: nil
  def clean_number(""), do: nil
  def clean_number(v) when is_binary(v) do
    cleaned = v |> String.replace(~r/[$,%,]/, "") |> String.trim()
    if cleaned == "" or cleaned == "0", do: nil, else: cleaned
  end
  def clean_number(v), do: to_string(v)

  @doc "Parse DD-MMM-YYYY or MM/DD/YYYY to Date"
  def parse_date(nil), do: nil
  def parse_date(""), do: nil
  def parse_date(v) when is_binary(v) do
    cond do
      v =~ ~r/^\d{2}-[A-Z]{3}-\d{4}$/ -> parse_dmy(v)
      v =~ ~r/^\d{2}\/\d{2}\/\d{4}$/ -> parse_mdy(v)
      true -> nil
    end
  end
  # ... parse_dmy, parse_mdy implementations
end
```

### 6. Delete Order for Rebuild

```elixir
defp delete_silver_for_account(account_id) do
  # FK order: children first
  Repo.delete_all(from a in SaleAllocation,
    join: s in Sale, on: a.sale_id == s.id,
    where: s.account_id == ^account_id)
  Repo.delete_all(from s in Sale, where: s.account_id == ^account_id)
  Repo.delete_all(from e in Exercise,
    join: t in Tranche, on: e.tranche_id == t.id,
    join: o in Origin, on: t.origin_id == o.id,
    where: o.account_id == ^account_id)
  Repo.delete_all(from t in Tranche,
    join: o in Origin, on: t.origin_id == o.id,
    where: o.account_id == ^account_id)
  Repo.delete_all(from o in Origin, where: o.account_id == ^account_id)
end
```

### 7. Sale Allocation Strategy

**No FIFO.** User picks which lot to sell — cannot be inferred from Benefit History.

- **ESPP sales**: Allocation created — parent_index links SELL to specific Purchase (tranche). Deterministic.
- **RSU sales**: Sale created, NO allocation. Lot linkage comes from G&L_Expanded spreadsheet (future ingestion source that has `Vest Date`, `Grant Number`, `Quantity` per lot sold).
- **ESOP sales**: Sale created, NO allocation (same as RSU).

Sales without allocations are a valid, expected state.

## Data Flow: RSU Example

```
Bronze:
  Grant(row=0): Symbol=ADBE, GrantDate=24-JAN-2024, GrantNum=RU401836, Qty=100
    VestSchedule(row=1, parent=0): VestDate=04/15/2024, Period=1
    VestSchedule(row=2, parent=0): VestDate=07/15/2024, Period=2
    ...
    Event(row=17, parent=0): Shares vested, Date=04/15/2024, Qty=7
    Event(row=18, parent=0): Shares released, Date=04/15/2024, Qty=5
    Event(row=19, parent=0): Shares sold, Date=04/28/2025, Qty=4

Silver:
  Origin: {plan_type: RSU, symbol: ADBE, grant_date: 2024-01-24, grant_number: RU401836, total_qty: 100}
  Tranche: {vest_date: 2024-04-15, vest_qty: 7, net_qty: 5, tax: 2, vest_fmv: nil, status: VESTED}
  Tranche: {vest_date: 2024-07-15, vest_qty: nil, status: UNVESTED}
  ...
  Sale: {origin_id: <origin>, sale_date: 2025-04-28, total_qty: 4, sale_price: nil}
  (NO allocation — lot linkage unknown from Benefit History, comes from G&L_Expanded)
```

## Data Flow: ESPP Example

```
Bronze:
  Purchase(row=0): Symbol=ADBE, GrantDate=03-JUL-2017, PurchaseDate=28-JUN-2019,
                    Price=117.6485, Qty=58, Tax=0, Net=58, FMV=$294.65, Discount=15%
    Event(row=1, parent=0): SELL, Date=12/24/2019, Qty=23
    Event(row=2, parent=0): SELL, Date=10/30/2019, Qty=25
    Event(row=3, parent=0): SELL, Date=08/01/2019, Qty=10
    Event(row=4, parent=0): PURCHASE, Date=06/28/2019, Qty=58  ← SKIP

Silver:
  Origin: {plan_type: ESPP, origin_date: 2017-07-03, origin_fmv: 441,
           grant_number: hash("ESPP:ADBE:2017-07-03")}
  Tranche: {vest_date: 2019-06-28, vest_qty: 58, vest_fmv: 294.65,
            net_qty: 58, status: VESTED, metadata: {buy_price: 117.6485}}
  Sale: {origin_id: <origin>, sale_date: 2019-08-01, total_qty: 10}
  Sale: {origin_id: <origin>, sale_date: 2019-10-30, total_qty: 25}
  Sale: {origin_id: <origin>, sale_date: 2019-12-24, total_qty: 23}
  SaleAllocation: {tranche_id: <purchase tranche>, quantity: 10}  (per ESPP sale)
```

## Warning Structure

```elixir
%{
  type: atom(),           # :orphan_event, :unparseable_date, :unparseable_number, :vest_without_release, etc.
  sheet: String.t(),      # "Restricted Stock", "ESPP", "Options"
  parent_index: integer() | nil,
  row_index: integer() | nil,
  message: String.t()     # Human-readable description
}
```

## Invariants (enforced in Silver Builder)

1. **Vest + Release aggregation**: Group RSU events by (parent_index, date). `vest_qty = sum("Shares vested")`, `release_qty = sum("Shares released")`. Prevents silent corruption from multiple events on same date.
2. **ESPP allocation limit**: For each ESPP tranche, `sum(allocations.quantity) ≤ net_quantity`. Enforced during allocation creation.
3. **Idempotency**: Rebuild produces logically identical state (same record values), but physical IDs are regenerated each run.
4. **ESPP grouping key**: `(symbol, grant_date)` — assumes single account per employer (Phase 1 constraint).
5. **Deletion scope**: Delete Silver scoped to `ingestion.account_id` (validated by loading the ingestion first, not raw account_id parameter).

## Correctness Properties

### Property 1: Rebuild Idempotency
*For any* ingestion, calling `build/1` twice produces identical Silver state.

### Property 2: Bronze Conservation
*For any* build, every Bronze parent row produces exactly one origin. No Bronze rows are modified.

### Property 3: Tranche-Event Pairing
*For any* RSU "Shares vested" + "Shares released" on the same date, one tranche captures both.

### Property 4: ESPP Enrollment Grouping
*For any* set of ESPP Purchase rows sharing the same Grant Date, exactly one origin is created.

## Error Handling

| Error Condition | Handling | Return |
|---|---|---|
| Ingestion not found / not ACTIVE | Reject | `{:error, :ingestion_not_active}` |
| Unparseable date | Skip field, add warning | Warning in summary |
| Unparseable number | Skip field, add warning | Warning in summary |
| Sale can't be matched to lot | Create sale, no allocation, add warning | Warning in summary |
| Empty sheet | Skip sheet | No error |
| Vest event without matching tranche | Create tranche from event data, add warning | Warning in summary |

## Testing Strategy

| Test Type | Coverage | Key Scenarios |
|---|---|---|
| Unit | ValueNormalizer | `$`, `%`, commas, date formats, nil/empty |
| Unit | RSU processing | Grant → origin, vest schedule → tranches, event pairing |
| Unit | ESPP processing | Enrollment grouping, purchase → tranche, redundant PURCHASE skip |
| Integration | Full build with sample data | SampleUser-2 Bronze → Silver, verify counts and relationships |
| Integration | Rebuild idempotency | Build twice, same Silver state |

## Implementation Notes

- **Transaction**: Wrap the full rebuild (delete + insert) in a Repo.transaction for atomicity.
- **Bronze query**: `FROM bronze_raw WHERE ingestion_id = ? ORDER BY sheet_name, row_index`. The row_index ordering + parent_index makes grouping trivial.
- **RSU vest_quantity from schedule**: Vest Schedule rows have empty Qty. Do NOT derive. Leave nil. The "Shares vested" event provides the actual qty when available.
- **RSU vest_fmv**: Not available in Benefit History. Leave nil. Future sources: G&L_Expanded (has `Vest Date FMV`), or stock price API (Yahoo adjusted close).
- **FX rates**: All fx_rate fields left nil in Phase 1. M7 (FX Service) will populate them later.
- **No exercises in Phase 1 data**: SampleUser-2 has no Options sheet. Exercise processing is implemented but untested with real data.
- **Sale price always nil from Benefit History**: Sales created with `sale_price: nil`. G&L_Expanded fills this in.
- **RSU sale allocations**: NOT created from Benefit History. Lot linkage is indeterminate (user picks which lot to sell). Allocations come from G&L_Expanded which has per-lot sale records with Grant Number + Vest Date.

## Future Data Sources (not M5 scope, separate milestones)

| Source | What it provides | Priority |
|---|---|---|
| G&L_Expanded XLSX | Sale allocations (lot linkage), vest_fmv, sale price, cost basis, capital gains | High — unlocks tax reporting |
| Stock Price API (Yahoo) | vest_fmv for unsold lots, current portfolio value | Medium |
| FX Rate API (RBI/manual) | USD/INR rates for all dates | Medium |
