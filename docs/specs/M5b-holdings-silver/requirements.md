# Requirements: M5b — Holdings Silver (Own Tables)

## Introduction

Holdings (ByBenefitType) is the sole source for the Portfolio page. Currently, Holdings data enriches BH-created Silver tranches (Phase 5). This is wrong — Holdings should create its own Silver data independently, without requiring BH.

**Why this is needed now:**
- DHF-1: User 1 — all sold, no Holdings. BH shows sold grants as available.
- DHF-2: User 2 — Holdings uploaded but 0 tranches enriched (no Sellable Shares rows in file).
- Both fail because Portfolio depends on BH-created tranches + Phase 5 enrichment.

## Architecture Decision

**Separate Silver tables for Holdings.**

| Source | Silver Table | Purpose |
|---|---|---|
| Benefits History | `stock_plan_origins`, `stock_plan_tranches`, `stock_plan_sales` | History, tax docs, income analysis |
| Holdings | `stock_plan_holdings` (new) | Portfolio — current snapshot |
| G&L | Enriches BH Silver (sale_allocations) | Tax Centre — capital gains |

Holdings Silver is a **snapshot table** — rebuilt from Holdings Bronze on each ingestion. Not event-derived like BH Silver.

## Requirements

### Requirement 1: Holdings Silver Table

1. CREATE `stock_plan_holdings` table
2. One row per vest period (RSU: actual or scheduled vest) or purchase lot (ESPP: actual purchase)
3. Fields:

| Field | Type | Source | Notes |
|---|---|---|---|
| id | TEXT PK | Generated | |
| ingestion_id | TEXT FK | Holdings ingestion | |
| account_id | TEXT | | |
| symbol | TEXT | Grant/Purchase row | |
| plan_type | TEXT | Sheet name: "RSU" / "ESPP" | |
| grant_number | TEXT | Grant Number (RSU) or generated (ESPP) | |
| grant_date | DATE | Grant row / Purchase row | |
| vest_date | DATE | Vest Schedule / Purchase Date | |
| vest_period | INTEGER | Vest Period number | RSU only |
| granted_qty | SafeDecimal | Grant: Granted Qty | RSU origin level |
| vested_qty | SafeDecimal | Vest Schedule: Vested Qty | Per vest period |
| released_qty | SafeDecimal | Vest Schedule: Released Qty | Net after tax |
| sellable_qty | SafeDecimal | Sellable Shares: Sellable Qty + Blocked | Currently owned |
| cost_basis | SafeDecimal | RSU: Est. Cost Basis (vest FMV). ESPP: Purchase Date FMV | Always FMV — uniform across plan types |
| purchase_price | SafeDecimal | ESPP only: discounted buy price | Not used for P&L — informational |
| status | TEXT | Derived | "VESTED" / "UNVESTED" |
| metadata_json | TEXT | Blocked info, tax details | |
| timestamps | | | |

### Requirement 2: Holdings Silver Builder

1. New module: `StockPlan.Ingestion.HoldingsSilverBuilder`
2. Reads Holdings Bronze rows, creates Holdings Silver rows
3. RSU: one Silver row per Vest Schedule period (with Sellable Shares data merged by Vest Period)
4. ESPP: one Silver row per Purchase
5. DELETE + INSERT on rebuild (same as BH Silver)

### Requirement 3: Portfolio reads from Holdings Silver

1. `Portfolio.build/1` reads from `stock_plan_holdings` when Holdings ingestion exists
2. Falls back to BH Silver (with origin-level sold calculation) when no Holdings
3. Never mixes Holdings Silver + BH Silver for the same portfolio view

### Requirement 4: FX Enrichment on Holdings Silver

1. Holdings Silver rows get FX rates (vest_fx_rate) from FX service
2. Same logic as BH Silver Phase 3 — previous month's rate

### Requirement 5: Decouple from BH Silver

1. Holdings ingestion SHALL NOT require BH to exist
2. Holdings Silver is self-contained — all data comes from Holdings Bronze
3. BH Silver remains for History/Tax pages — untouched by this change

## What This Replaces

- Current Phase 5 in Silver Builder (enrichment of BH tranches) → removed
- Current Portfolio.build reading from `stock_plan_tranches` → reads from `stock_plan_holdings`
- `sellable_qty` and `cost_basis_broker` fields on `stock_plan_tranches` → no longer needed for Portfolio (keep for now, deprecate later)

## Portfolio Contract (Invariant)

```
Portfolio.build(account_id):

  IF Holdings ingestion exists:
    Source = Holdings Silver ONLY
    VESTED quantity = sellable_qty from Holdings
    UNVESTED = vest schedule rows present in Holdings (if any)
    No reconstruction from BH. No merge. No inference.

  IF no Holdings ingestion:
    Fallback = BH-derived portfolio (best-effort)
    Vested available = vested_qty - origin-level sold (from Sales)
```

**UNVESTED from Holdings:** Only shown if Holdings vest schedule rows exist for unvested periods. If absent, not shown. System does not infer or reconstruct unvested data from BH when Holdings is the active source.

**What system must NOT do when Holdings exists:**
- Merge BH data into Portfolio
- Derive missing unvested schedule from BH
- Reconcile cost_basis across sources
- Auto-correct user data

## Data Validation Guardrails (Separate Milestone — Future)

Structured validation with severity levels will be added as a separate milestone after M5b:

- **ERROR** (block ingestion): sellable_qty > vested_qty, negative quantities
- **WARNING** (allow, surface to user): missing unvested schedule, missing cost_basis, Holdings vs BH mismatch
- **INFO** (optional): partial data detected

Guardrails will include a `data_health` response with warnings/errors surfaced in UI.

Not in M5b scope — M5b assumes user uploads correct data.

## Out of Scope

- BH Silver schema changes
- Tax Centre / History pages
- G&L processing changes
- Data validation guardrails (separate milestone)
