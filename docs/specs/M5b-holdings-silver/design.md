# Design: M5b — Holdings Silver (Own Tables)

> **See also:** [System Invariants](../../core/invariants.md) — especially #1 (full rebuild), #4 (portfolio composition)

## Architecture

```
Holdings XLSX (ByBenefitType_expanded)
     |
     v
Bronze (Holdings_ESPP + Holdings_RSU rows)
     |
     v
HoldingsSilverBuilder.build(account_id)
     |
     ├── RSU: Grant + Vest Schedule + Sellable Shares → stock_plan_holdings rows
     └── ESPP: Purchase rows → stock_plan_holdings rows
     |
     v
FX Enrichment (vest_fx_rate on each holding row)
     |
     v
Portfolio.build(account_id) ← reads from stock_plan_holdings
```

## Schema: stock_plan_holdings

```elixir
schema "stock_plan_holdings" do
  field :id, :string                          # PK, app-generated
  field :ingestion_id, :string                # FK → ingestions (Holdings)
  field :account_id, :string
  field :symbol, :string                      # e.g., "ADBE"
  field :plan_type, :string                   # "RSU" / "ESPP"
  field :grant_number, :string                # Broker-assigned (RSU) or generated (ESPP)
  field :grant_date, :date                    # RSU: grant date. ESPP: enrollment date
  field :granted_qty, SafeDecimal             # Total granted (RSU origin level, nil for ESPP)
  field :vest_date, :date                     # Vest/purchase date
  field :vest_period, :integer                # Vest Period # (RSU only, nil for ESPP)
  field :vested_qty, SafeDecimal              # Shares vested in this period
  field :released_qty, SafeDecimal            # Net shares after tax withholding
  field :sellable_qty, SafeDecimal            # Currently sellable (from Sellable Shares)
  field :blocked_qty, SafeDecimal             # Blocked due to trading window
  field :cost_basis, SafeDecimal              # Always FMV. RSU: vest FMV. ESPP: Purchase Date FMV
  field :purchase_price, SafeDecimal          # ESPP only: discounted buy price (informational, not for P&L)
  field :status, :string                      # "VESTED" / "UNVESTED"
  field :vest_fx_rate, SafeDecimal            # USD/INR at vest date (FX enrichment)
  field :metadata_json, :string               # Tax details, blocked info
  timestamps(type: :utc_datetime_usec)
end
```

## Sellable vs Blocked Qty — ESPP vs RSU

ESPP and RSU handle sellable/blocked quantities differently in the Holdings XLSX:

| | ESPP (Purchase row) | RSU (Sellable Shares row) |
|---|---|---|
| `Sellable Qty` | Total owned shares (always filled) | Shares available to sell (0 if all blocked) |
| `Blocked Qty` | Subset of Sellable under trading restriction | Shares blocked (full count if all blocked) |
| Relationship | Blocked is a subset of Sellable | Additive: Sellable + Blocked = total owned |
| Total owned | = Sellable Qty | = Sellable Qty + Blocked Qty |

**ESPP example (all blocked):**
```
Sellable Qty: 15.317    ← total owned
Blocked Qty:  15.317    ← all blocked (= Sellable)
```

**RSU example (all blocked):**
```
Sellable Qty._3: 0      ← nothing available to sell
Blocked Share Qty: 9     ← all blocked
Total owned: 0 + 9 = 9
```

### Assumptions (unverified — no sample data with open trading window)

1. **RSU partial block:** If only some shares are blocked, we assume both `Sellable Qty._3` and `Blocked Share Qty.` will be non-zero and additive (e.g., Sellable=5, Blocked=4, Total=9). Not verified — all sample data has full company blackout.
2. **ESPP partial block:** We assume `Sellable Qty` remains the total owned, with `Blocked Qty < Sellable Qty`. Not verified.
3. **ESPP unblocked:** We assume `Sellable Qty` stays the same, `Blocked Qty = 0`. Not verified.

These assumptions should be verified when sample data from an open trading window is available.

---

## Data Extraction — RSU

For each Grant in Holdings Bronze:

```
Grant row → extract: symbol, grant_date, granted_qty, grant_number, status

Vest Schedule rows (grouped by Vest Period under this Grant):
  → vest_date, vested_qty, released_qty, shares_traded_for_taxes

Sellable Shares rows (matched by Vest Period):
  → sellable_qty (= Sellable Qty._3 + Blocked Share Qty.)
  → blocked_qty (= Blocked Share Qty.)
  → cost_basis (= Est. Cost Basis)
  → blocked, blocked_type, release_date → metadata_json

Status derivation:
  If vested_qty > 0 or released_qty > 0 → VESTED
  If vested_qty == 0 and released_qty == 0 → UNVESTED
```

**One Holdings Silver row per Vest Schedule period.**

Vest periods WITH Sellable Shares: have sellable_qty (current owned count).
Vest periods WITHOUT Sellable Shares: vested but fully sold (sellable_qty = 0), OR unvested.

**Determining sellable_qty when no Sellable Shares row:**
- If VESTED (released_qty > 0) but no Sellable Shares → `sellable_qty = 0` (fully sold)
- If UNVESTED → `sellable_qty = nil` (not yet vested)

This is the key insight: Sellable Shares rows only exist for vest periods that have shares currently owned. Absence = sold or not yet vested.

## Data Extraction — ESPP

For each Purchase row in Holdings Bronze:

```
Purchase row → extract:
  symbol, grant_date (enrollment), vest_date (= purchase_date),
  vested_qty (= purchased_qty), released_qty (= net_shares),
  sellable_qty (= Sellable Qty. + Blocked Qty.),
  blocked_qty (= Blocked Qty.),
  cost_basis (= Purchase Date FMV — for Indian capital gains),
  purchase_price (= Purchase Price — discounted buy price),
  status: always "VESTED" (purchases are immediate)

grant_number: generated hash of "ESPP:{symbol}:{grant_date}"
```

**One Holdings Silver row per Purchase.**

## HoldingsSilverBuilder

```elixir
defmodule StockPlan.Ingestion.HoldingsSilverBuilder do
  def build(account_id) do
    # 1. Find ACTIVE Holdings ingestion
    # 2. Delete existing holdings: DELETE FROM stock_plan_holdings WHERE account_id = ?
    # 3. Load Holdings Bronze rows
    # 4. Process RSU rows → insert holdings
    # 5. Process ESPP rows → insert holdings
    # 6. Enrich with FX rates
    # 7. Return counts
  end
end
```

### RSU Processing

```
1. Group Bronze rows by Grant Number
2. For each Grant:
   a. Extract grant-level fields (symbol, grant_date, granted_qty, grant_number)
   b. Build Vest Period → Vest Date map from Vest Schedule rows
   c. Build Vest Period → Sellable data map from Sellable Shares rows
   d. For each Vest Schedule row:
      - Look up Sellable Shares for same Vest Period
      - Determine status: VESTED if released_qty > 0, else UNVESTED
      - Set sellable_qty:
          If Sellable Shares exists → Sellable Qty + Blocked Share Qty
          If VESTED but no Sellable Shares → 0 (fully sold)
          If UNVESTED → nil
      - Insert Holdings Silver row
```

### ESPP Processing

```
1. For each Purchase Bronze row:
   - Parse all fields directly (flat structure, no parent-child)
   - Set status = "VESTED"
   - Set cost_basis = Purchase Date FMV (for Indian CG)
   - Set purchase_price = Purchase Price (discounted)
   - Insert Holdings Silver row
```

## Portfolio.build — Revised

```elixir
def build(account_id) do
  if has_holdings_ingestion?(account_id) do
    build_from_holdings(account_id)
  else
    build_from_bh(account_id)  # fallback — existing logic with DHF-1 fix
  end
end

defp build_from_holdings(account_id) do
  # Query stock_plan_holdings for ACTIVE Holdings ingestion
  # Group by plan_type → grant_number → rows
  # Return hierarchical structure
end

defp build_from_bh(account_id) do
  # Existing logic (BH origins + tranches)
  # With DHF-1: subtract origin-level sold from Sales
end
```

## FX Enrichment

After Holdings Silver rows are created:

```
For each Holdings Silver row with vest_date and nil vest_fx_rate:
  vest_fx_rate = FX.get_rate(vest_date)  # previous month's rate
  Update row
```

Same logic as BH Silver Phase 3, applied to stock_plan_holdings.

## Integration with Orchestrator

```elixir
def ingest_holdings(account_id, file_path) do
  # Parse → Bronze (existing)
  # Archive previous Holdings ingestion (existing)
  # Build Holdings Silver (NEW — replaces Phase 5)
  # Do NOT trigger BH Silver rebuild
end
```

Holdings ingestion no longer calls `SilverBuilder.build/1`. It has its own builder.

## What Changes

| Component | Before | After |
|---|---|---|
| Phase 5 in SilverBuilder | Enriches BH tranches | Removed |
| Portfolio.build | Reads stock_plan_tranches | Reads stock_plan_holdings (or BH fallback) |
| ingest_holdings | Parse → Bronze → BH Silver rebuild | Parse → Bronze → Holdings Silver build |
| sellable_qty on tranches | Set by Phase 5 | No longer set (field stays, unused by Portfolio) |

## Migration

```elixir
create table(:stock_plan_holdings) do
  add :id, :string, primary_key: true
  add :ingestion_id, :string, null: false
  add :account_id, :string, null: false
  add :symbol, :string
  add :plan_type, :string, null: false
  add :grant_number, :string
  add :grant_date, :date
  add :granted_qty, :string          # SafeDecimal
  add :vest_date, :date
  add :vest_period, :integer
  add :vested_qty, :string           # SafeDecimal
  add :released_qty, :string         # SafeDecimal
  add :sellable_qty, :string         # SafeDecimal
  add :blocked_qty, :string          # SafeDecimal
  add :cost_basis, :string           # SafeDecimal — always FMV
  add :purchase_price, :string       # SafeDecimal — ESPP discounted price (informational)
  add :status, :string, null: false
  add :vest_fx_rate, :string         # SafeDecimal
  add :metadata_json, :string
  timestamps(type: :utc_datetime_usec)
end

create index(:stock_plan_holdings, [:account_id, :ingestion_id])
```
