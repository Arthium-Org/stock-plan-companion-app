# Requirements: M14 — Tax Centre (Phase 1)

> **See also:** [Indian Tax Rules](../../core/indian-tax-rules.md) — complete reference for tax laws, rates, FX rules

## Introduction

Tax Centre provides two features for Phase 1:
1. **Schedule FA** — Foreign Asset disclosure for Indian ITR (**calendar year: Jan-Dec**)
2. **Capital Gains Statement** — Realized gains/losses from share sales (**Indian Financial Year: Apr-Mar**)

**Data sources:** Benefits History (origins, tranches, sales) + G&L Expanded (lot-level sale details). NOT Holdings.

**Future documents** (not in Phase 1): Schedule FSI, Schedule TR, Form 67, Perquisite/Salary income

---

## Feature 1: Schedule FA (Foreign Assets)

### What is Schedule FA?

Indian tax residents must disclose foreign assets in their ITR under Schedule FA. For stock plans, each grant and holding must be reported with:
- Country of asset
- Nature of asset (shares)
- Date of acquisition
- Initial value
- Peak value during the year
- Closing value as of Dec 31

### Requirement FA-1: Schedule FA Data

1. THE system SHALL generate Schedule FA data for a selected **calendar year** (Jan 1 - Dec 31)
2. Schedule FA for CY 2024 is reported in ITR for FY 2024-25
3. FOR EACH lot (tranche) held at any point during the CY:
   - One row per lot — same company may have multiple rows (different acquisition dates)
   - "Held during CY" = acquired (vested/purchased) on or before Dec 31 AND not fully sold before Jan 1
4. Per row — all values in **INR**:
   - Date acquired: vest_date (RSU) or purchase_date (ESPP)
   - Initial value: cost_basis × qty × vest_fx_rate
   - Peak value: highest monthly stock price during CY × qty × FX rate for that month
   - Closing balance: Dec 31 price × qty held on Dec 31 × FX rate (0 if sold before Dec 31)
   - Gross amount paid/credited: dividends during CY (0 for Phase 1)
   - Gross proceeds from sale: sale proceeds during CY if sold (0 if not sold)
5. Lots fully sold before Jan 1 of the CY: excluded (not held during the CY)
6. Lots sold mid-CY: still included (held during part of the CY), closing balance = 0
7. Partial sale mid-CY: one row for the lot. Closing balance = remaining qty × Dec 31 price. Sale proceeds = proceeds from partial sale.

### Requirement FA-1a: Peak Value Calculation

Peak value must account for quantity changes during the CY (partial sales):

```
Split CY into intervals by quantity-change events (acquisition, each partial sale):
  For each interval:
    interval_peak = highest_stock_price_in_interval × qty_held_during_interval × FX_rate
  
  Peak value = MAX(interval_peak across all intervals)
```

Example:
- Jan 1: hold 100 shares
- May peak price $300 → 100 × $300 × FX = ₹25L
- Jun 15: sell 40 → hold 60
- Sep peak price $350 → 60 × $350 × FX = ₹18L
- Peak value = ₹25L (May period wins)

**Open question:** Verify this interpretation against ITR guidelines or CA practice. No authoritative guidance found on partial-sale peak calculation.

### Requirement FA-2: Schedule FA Download

1. THE system SHALL provide a downloadable **CSV** file for Schedule FA
2. Columns matching INDmoney format (verified from sample):
   - Country Name, Country Code, Name of entity, Address, ZIP, Nature of entity
   - Date of acquiring interest, Initial value, Peak value, Closing Balance
   - Gross amount paid/credited, Gross proceeds from sale, Broker Name
3. One row per lot (tranche) held during the CY
4. All amounts in **INR** (rounded to nearest rupee, no decimals)
5. Company details hardcoded for Phase 1 (single company: Adobe Inc.)
6. **Commas in address fields SHALL be replaced with semicolons** (CSV-safe)
7. Filename: `Schedule_FA_CY{year}.csv` (e.g., `Schedule_FA_CY2024.csv`)

### Requirement FA-3: Schedule FA UI

1. Route: `GET /tax`
2. Calendar year selector (dropdown)
3. Preview table showing Schedule FA data before download
4. Download button for Excel/CSV

### Requirement FA-4: Data Dependencies

1. Requires: BH ingestion (origins + tranches) + G&L (for vest_fmv, sale details)
2. Requires: FX rates for the year (vest_fx_rate on tranches + Dec 31 rate)
3. Requires: Stock price history (peak price during year + Dec 31 closing price)
4. If vest_fmv missing: use vest_day_close as fallback (with indicator)

---

## Feature 2: Capital Gains Assessment

### What is Capital Gains?

When shares are sold, the difference between sale proceeds and cost basis is a capital gain or loss. Indian tax classifies:
- **STCG (Short Term):** Holding period ≤ 24 months for unlisted shares (foreign company shares)
- **LTCG (Long Term):** Holding period > 24 months

Note: Foreign company shares are treated as "unlisted" under Indian tax law regardless of whether the company is publicly listed abroad.

### Requirement CG-1: Capital Gains Data

1. THE system SHALL compute capital gains per sell transaction for a selected Financial Year (Apr-Mar)
2. FOR EACH sale with lot-level allocation (from G&L):
   - Sale date, sale price, proceeds
   - Cost basis: vest_fmv (RSU) or purchase_fmv (ESPP) — per lot
   - Holding period: sale_date - vest_date (days)
   - Classification: STCG (≤ 24 months) or LTCG (> 24 months)
   - Gain/Loss in USD: proceeds - cost_basis
   - Gain/Loss in INR: (proceeds × sale_fx_rate) - (cost_basis × vest_fx_rate)
3. FOR sales WITHOUT lot-level allocation: show as "Lot unknown — requires G&L data"

### Requirement CG-2: Capital Gains Summary

1. Summary by classification: Total STCG, Total LTCG (both USD and INR)
2. Summary by plan type: RSU gains, ESPP gains
3. Net gain/loss for the FY

### Requirement CG-3: Capital Gains UI

1. Display on `/tax` page (same page as Schedule FA, tabbed or sectioned)
2. Financial Year selector (e.g., "FY 2024-25" = Apr 2024 - Mar 2025)
3. Table: one row per sale-lot combination
4. Columns: Sale Date, Grant#, Vest Date, Qty, Sale Price, Cost Basis, Holding Period, Type (STCG/LTCG), Gain/Loss (USD), Gain/Loss (INR)
5. Summary cards: Total STCG, Total LTCG, Net Gain/Loss

### Requirement CG-4: Indian Tax Rules

1. Holding period: vest_date (RSU) or purchase_date (ESPP) to sale_date
2. Threshold: ≤ 24 months = STCG, > 24 months = LTCG (unlisted foreign shares)
3. Tax rates (AY 2025-26+): STCG at slab rates, LTCG at 12.5% (no indexation)
4. Cost basis per share:
   - RSU: vest_fmv (already taxed as perquisite at vest)
   - ESPP: purchase_date_fmv (discount taxed as perquisite, capital gains starts from FMV)
5. Cost basis in INR: cost_basis_per_share × qty × FX rate on acquisition date
6. Proceeds in INR: sale_price × qty × FX rate on sale date
7. FX rate rule: SBI TT Buying Rate on last day of month preceding the event month (Rule 115)
8. FX rates: already enriched on tranches (vest_fx_rate) and sales (sale_fx_rate) in Silver
9. Grandfathering: lots acquired before Jul 23, 2024 → lower of (12.5% w/o indexation, 20% with indexation)

### Requirement CG-5: Data Dependencies

1. Requires: G&L ingestion (sale_allocations linking sales to specific tranches)
2. Sales without allocations: show with "Lot details unavailable" warning
3. Requires: FX rates on sales and tranches
4. If vest_fmv missing: use vest_day_close with indicator

---

## ESPP Cost Basis — Decision

ESPP cost basis for capital gains = **Purchase Date FMV** (not discounted purchase price).

Rationale: The discount (FMV - purchase price) is taxed as perquisite income at purchase. Capital gains therefore starts from FMV, same as RSU treatment.

- **Portfolio:** Shows Purchase Date FMV as cost basis (consistent)
- **Tax Centre:** Uses Purchase Date FMV for capital gains computation (consistent)
- **Alternative interpretation** (purchase price as cost basis) may be supported as user-configurable option in a future phase. Users should consult their tax advisor.

## Out of Scope (Phase 1)

- Perquisite income (RSU vest income, ESPP discount income) — separate feature
- Schedule FSI (Foreign Source Income) — separate feature
- Schedule TR (Tax Relief) — separate feature
- Form 67 (Foreign Tax Credit claim) — separate feature
- Tax payment computation (actual tax owed) — separate feature
- Sell advisor (tax-optimal lot selection) — separate feature
- ITR XML generation — separate feature
- Dividend tracking — separate feature
