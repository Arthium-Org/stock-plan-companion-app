# Design Document: M3b — Holdings (ByBenefitType) Ingestion

> **See also:** [System Invariants](../../core/invariants.md) — especially #1 (full rebuild), #3 (one ACTIVE per category), #5 (cost basis no reconciliation)

## Overview

M3b ingests the ByBenefitType_expanded XLSX — the broker's snapshot of current holdings. This is the sole source for the Portfolio page. Two sheets: ESPP (purchases) and Restricted Stock (grants + vests).

## Architecture

```
ByBenefitType_expanded.xlsx
     |
     ├── ESPP sheet ──→ HoldingsParser ──→ BronzeRow (Holdings_ESPP)
     │                                          |
     └── RS sheet ────→ HoldingsParser ──→ BronzeRow (Holdings_RSU)
                                                |
                                                v
                                         bronze_raw (category: HOLDINGS)
                                                |
                                                v
                                    Silver Builder Phase 5
                                    Match by grant_number + vest_date
                                    Update: sellable_qty, cost_basis_broker
```

## File Format

### ESPP Sheet (25 columns)
```
Purchase rows only (flat, no parent-child):
  Symbol, Purchase Date, Purchase Price, Purchased Qty,
  Net Shares, Sellable Qty, Est. Market Value,
  Grant Date, Discount Percent, Grant Date FMV, Purchase Date FMV,
  Est. Cost Basis (per share), Blocked Qty, Blocked Type
```

### Restricted Stock Sheet (63 columns)
```
Grant (parent):
  Symbol, Grant Date, Granted Qty, Vested/Unvested Qty,
  Sellable Qty, Grant Number, Status

Vest Schedule (child of Grant, by Grant Number + Vest Period):
  Vest Date, Granted Qty, Vested Qty, Released Qty,
  Shares Traded for taxes, Total Taxes Paid

Sellable Shares (child, by Grant Number + Vest Period):
  Sellable Est. Market Value, Est. Cost Basis (per share),
  Tax Status ("Long Term"/"Short Term"), Blocked, Blocked Type

Tax Withholding (child, by Grant Number + Vest Period):
  Tax Description, Taxable Gain, Effective Tax Rate, Withholding Amount
```

## Schema Changes

```elixir
# Migration: add to stock_plan_tranches
add :sellable_qty, :string        # SafeDecimal — broker-reported current sellable count
add :cost_basis_broker, :string   # SafeDecimal — broker-calculated cost basis per share
```

**Not stored in Silver:** Tax Status ("Long Term"/"Short Term") is US-specific and date-sensitive. It lives in Bronze only. Indian tax classification (STCG/LTCG) is computed from vest_date + holding period using Indian rules in Tax Centre (Phase 2).

## Silver Builder Phase 5 — Holdings Enrichment

```
For each Holdings Bronze row:
  ESPP Purchase:
    → Find origin by symbol + grant_date (enrollment)
    → Find tranche by purchase_date (= vest_date)
    → Update: sellable_qty, cost_basis_broker
    → metadata_json += {blocked, blocked_type}

  RSU Vest Schedule + Sellable Shares (grouped by Grant Number + Vest Period):
    → Find origin by grant_number
    → Find tranche by vest_date
    → From Vest Schedule: update released_qty, tax details
    → From Sellable Shares: update sellable_qty, cost_basis_broker, tax_status
    → metadata_json += {blocked, blocked_type, release_date}

  RSU Grant:
    → Update origin status
```

## Portfolio Impact

Portfolio.build becomes simple:

```elixir
def build(account_id) do
  # Load all tranches with Holdings data
  # Filter: sellable_qty > 0 OR status == UNVESTED
  # Return rows with broker-reported values
end
```

**Cost basis priority:**
1. `cost_basis_broker` (Holdings) — broker-calculated, authoritative
2. `vest_fmv` (G&L) — actual FMV from tax lot report
3. `vest_day_close` (Yahoo) — market close, approximate
4. nil

**Sellable quantity:**
- Use `sellable_qty` (Holdings) when available — broker says exactly what's sellable
- Fallback: `net_quantity - sold` (derived from BH + allocations) when no Holdings data

## Implementation Notes

- Holdings is RSU + ESPP. No ESOP/Options in sample data.
- "Sellable Shares" row type (RSU) has blocked status — store in metadata, not a portfolio filter. It's a company trading window restriction, temporary.
- **One ACTIVE Holdings ingestion per account.** New upload archives previous Holdings ingestion. Same pattern as BH. Does NOT archive BH or G&L (each category independent).
- Holdings enrichment is OVERWRITE (not fill-only) — newer snapshot replaces older values.
- Grant rows without vest details (fully unvested grants) → origin status update only, no tranche changes.
- **Determinism:** Holdings goes through Bronze like everything else. Rebuild from all Bronze (BH + G&L + Holdings) is deterministic. Same Bronze inputs = same Silver outputs.
