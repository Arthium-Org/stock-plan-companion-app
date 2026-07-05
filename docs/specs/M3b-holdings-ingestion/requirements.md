# Requirements Document: M3b — Holdings (ByBenefitType) Ingestion

## Introduction

The ByBenefitType_expanded XLSX is E*Trade's current holdings export — a point-in-time snapshot of what the user currently owns. It is the **sole data source for the Portfolio page**. Benefits History and G&L feed into Tax Centre and History pages, NOT into Portfolio.

Two sheets: "ESPP" (purchase-level holdings) and "Restricted Stock" (grant/vest-level holdings).

## Data Source Architecture

| Data Source | Feeds Into | Purpose |
|---|---|---|
| **Holdings (ByBenefitType)** | **Portfolio page** | What you own now — broker snapshot |
| Benefits History | Tax Centre, History | Transaction log — what happened |
| G&L Expanded | Tax Centre | Lot-level sell details for capital gains |

## Requirements

### Requirement 1: ESPP Sheet Parsing (25 columns)

1. THE parser SHALL read the "ESPP" sheet
2. Row types: Purchase (data), Totals (skip)
3. EACH Purchase row provides: Symbol, Purchase Date, Purchase Price, Purchased Qty, Net Shares, Sellable Qty, Est. Market Value, Grant Date, Discount Percent, Grant Date FMV, Purchase Date FMV, Est. Cost Basis (per share), Blocked Qty, Blocked Type
4. THE parser SHALL output BronzeRow structs with `sheet_name: "Holdings_ESPP"`

### Requirement 2: Restricted Stock Sheet Parsing (63 columns)

1. THE parser SHALL read the "Restricted Stock" sheet
2. Row types: Grant (parent), Vest Schedule (child), Sellable Shares (child), Tax Withholding (child), Totals (skip)
3. Parent-child linking via Grant Number and Vest Period
4. **Grant** rows provide: Symbol, Grant Date, Granted Qty, Vested Qty, Unvested Qty, Sellable Qty, Grant Number, Status
5. **Vest Schedule** rows provide: Vest Period, Vest Date, Granted Qty (per vest), Vested Qty, Released Qty, Shares Traded for taxes, Total Taxes Paid
6. **Sellable Shares** rows provide: Sellable Est. Market Value, Est. Cost Basis (per share), Est. Taxable Gain/Loss (per share), Tax Status (Long Term / Short Term), Blocked, Blocked Type, Release Date
7. **Tax Withholding** rows provide: Tax Description, Taxable Gain, Effective Tax Rate, Withholding Amount
8. THE parser SHALL output BronzeRow structs with `sheet_name: "Holdings_RSU"`

### Requirement 3: Bronze Storage

1. Holdings data SHALL go through Bronze (`stock_plan_bronze_raw`)
2. New ingestion category: `"HOLDINGS"`
3. **One ACTIVE Holdings ingestion per account** — new upload archives previous Holdings ingestion (same pattern as BH)
4. Holdings ingestion does NOT archive BH or G&L — each category manages its own ACTIVE independently
5. Dedup via row_hash within same ingestion

### Requirement 4: Schema Changes

1. ADD `sellable_qty` (SafeDecimal, nullable) to `stock_plan_tranches`
2. ADD `cost_basis_broker` (SafeDecimal, nullable) to `stock_plan_tranches`
3. These are SEPARATE from BH-derived fields — Holdings is broker-authoritative
4. Date-sensitive data (US tax status, gain/loss) stays in Bronze only — not stored in Silver. Tax classification computed fresh using Indian rules when needed (Tax Centre, Phase 2).

### Requirement 5: Silver Enrichment (New Phase)

1. Silver Builder SHALL process Holdings Bronze as a new phase (after FX + Stock Prices)
2. FOR EACH ESPP Purchase row: match to origin by (symbol, grant_date, purchase_date), update sellable_qty, cost_basis_broker
3. FOR EACH RSU Vest Schedule + Sellable Shares row: match to tranche by (grant_number, vest_date), update sellable_qty, cost_basis_broker, tax_status, tax metadata
4. Holdings data is **overwrite** (not fill-only) — it's a newer snapshot, authoritative for current state
5. "Sellable Shares" blocked status stored in metadata_json (informational — company trading window restriction)

### Requirement 6: Orchestrator

1. `Ingestions.ingest_holdings(account_id, file_path)` SHALL be the entry point
2. Holdings SHALL NOT archive BH or G&L — all coexist
3. Holdings triggers Silver rebuild (incorporates all data sources)
