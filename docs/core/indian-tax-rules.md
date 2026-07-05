# Indian Tax Rules — Foreign Income from US Stock Plans

Reference document for tax computation logic. Verify specific rates against the latest Finance Act before production use.

---

## Tax Documents Required

| Document | Period | Purpose |
|---|---|---|
| **Schedule FA** | Calendar Year (Jan-Dec) | Foreign Assets declaration — every lot held during CY |
| **Schedule FSI** | Financial Year (Apr-Mar) | Foreign Source Income — capital gains, dividends |
| **Schedule TR** | Financial Year (Apr-Mar) | Tax Relief — credit for taxes paid in US (DTAA) |
| **Form 67** | Financial Year (Apr-Mar) | Claim Foreign Tax Credit — mandatory for FTC |
| **Capital Gains Statement** | Financial Year (Apr-Mar) | Per-trade STCG/LTCG detail |
| **Form 1042-S** | US Calendar Year (Jan-Dec) | US tax withholding certificate (from broker) |

---

## Income Types from Stock Plans

### RSU Vest Income
- **Tax event:** Vest date (shares released)
- **Classification:** Perquisite under Section 17(2) → **Salary income**
- **Taxable amount:** FMV on vest date × qty, converted to INR
- **Cost basis for future sale:** FMV on vest date (already taxed as perquisite)

### ESPP Discount Income
- **Tax event:** Purchase date
- **Classification:** Perquisite under Section 17(2) → **Salary income**
- **Taxable amount:** (Purchase Date FMV - Discounted Price) × qty
- **Cost basis for future sale:** Discounted purchase price (the actual amount paid)
- **Note:** India taxes discount as perquisite regardless of US "qualified" plan status

### Capital Gains on Sale
- **Tax event:** Sale date
- **Cost basis:**
  - RSU: FMV on vest date (already taxed as perquisite)
  - ESPP: Discounted purchase price (amount actually paid)
  - ESOP: Exercise/strike price
- **Holding period:** From acquisition date (vest/purchase/exercise) to sale date

### Dividend Income
- **Classification:** Income from Other Sources (Section 56)
- **Tax rate:** Slab rates (added to total income)
- **US withholding:** 25% (or 15% under DTAA with W-8BEN)

---

## Capital Gains Classification

### Holding Period
- Foreign company shares = **unlisted shares**
- LTCG threshold: **> 24 months** from acquisition to sale
- ≤ 24 months = STCG

### Tax Rates (AY 2025-26 onwards, Finance Act 2024)

| Type | Rate | Indexation |
|---|---|---|
| STCG (unlisted foreign shares) | **Slab rates** (up to 30%) | N/A |
| LTCG (unlisted foreign shares) | **12.5%** | **No indexation** |
| LTCG (acquired before 23-Jul-2024) | Lower of: 12.5% w/o indexation OR 20% with indexation | Grandfathered |

Plus surcharge (based on total income) + 4% Health & Education Cess.

### Loss Set-off
- STCL → set off against STCG and LTCG
- LTCL → set off against LTCG only
- Carry forward: 8 assessment years (must file on time)

---

## FX Rate Rules

- **Rate:** SBI TT (Telegraphic Transfer) Buying Rate
- **Date:** Last day of the month **preceding** the month of the event (Rule 115)
- Examples:
  - Vest on Mar 15 → use SBI TT rate on Feb 28
  - Sale on Jul 20 → use SBI TT rate on Jun 30
  - Schedule FA closing (Dec 31) → use SBI TT rate on Nov 30

---

## Schedule FA Specifics

### Period: Calendar Year (Jan 1 - Dec 31)
- Reported in ITR for the FY in which the CY ends
- CY 2024 → reported in FY 2024-25 ITR (filed by Jul 31, 2025)

### One row per lot held at any point during the CY

### Columns (from INDmoney sample)

| # | Column | Source for our app |
|---|---|---|
| 1 | Country Name | "United States" (hardcoded) |
| 2 | Country Code | "US" (hardcoded) |
| 3 | Name of entity | "Adobe Inc." (hardcoded per company) |
| 4 | Address of entity | Company HQ address (hardcoded) |
| 5 | ZIP Code | Company zip (hardcoded) |
| 6 | Nature of entity | "Company" (hardcoded) |
| 7 | Date of acquiring interest | vest_date (RSU) / purchase_date (ESPP) |
| 8 | Initial value of investment (INR) | cost_basis × qty × vest_fx_rate |
| 9 | Peak value of investment (INR) | peak_price × qty × peak_month_fx |
| 10 | Closing Balance (INR) | dec31_price × qty × dec31_fx (0 if sold) |
| 11 | Gross amount paid/credited (INR) | Dividends during CY (0 for now) |
| 12 | Gross proceeds from sale (INR) | Sale proceeds during CY (0 if not sold) |
| 13 | Broker Name | "E*Trade" (hardcoded) |

### Peak Value
- Highest stock price during the months the lot was held in the CY
- × quantity held × SBI TT rate for that month

### Closing Value
- Stock price on Dec 31 (or last trading day) × qty held on Dec 31 × FX rate
- 0 if fully sold before Dec 31 (but row still appears)

---

## Schedule FSI Specifics

### Period: Financial Year (Apr 1 - Mar 31)

### Income heads for stock plans (foreign source only)

| Head | Income Type | Amount |
|---|---|---|
| Capital Gains | STCG + LTCG from share sales | Gain/loss in INR |
| Other Sources | Dividend income | Dividend × FX rate |

**NOT foreign source income (NOT in Schedule FSI):**
- RSU vest perquisite → salary income, taxed by Indian employer, appears in Form 16
- ESPP discount perquisite → salary income, taxed by Indian employer, appears in Form 16

These are employment income for services rendered in India. The shares are of a US company but the perquisite is Indian salary income.

### Per income head: Tax paid outside India (from 1042-S), Tax payable in India, Tax relief

---

## Schedule TR + Form 67

### Foreign Tax Credit (FTC)
- Credit = lower of (US tax paid, Indian tax payable on same income)
- Claimed under Section 90 (DTAA) or Section 91 (unilateral)
- Form 67 is mandatory procedural requirement for FTC

### DTAA Articles (India-US)
- Article 16: Salary/employment income
- Article 13: Capital gains
- Article 10: Dividends (max 15% with W-8BEN)
- Article 25: Relief from double taxation

---

## Calendar Year vs Financial Year — Mapping

| Event | Indian FY | Schedule FA CY | US Tax Year |
|---|---|---|---|
| RSU vest Nov 2025 | FY 2025-26 | CY 2025 | US CY 2025 |
| RSU vest Feb 2026 | FY 2025-26 | CY 2026 | US CY 2026 |
| Sale Jul 2025 | FY 2025-26 | CY 2025 | US CY 2025 |
| Sale Jan 2026 | FY 2025-26 | CY 2026 | US CY 2026 |

CY and FY misalign for events in Jan-Mar.

---

## Items Requiring Verification

1. LTCG rate 12.5% — confirm applies to unlisted foreign shares (not just listed)
2. Grandfathering scope for shares acquired before Jul 23, 2024
3. ESPP cost basis: purchase price vs FMV (make user-configurable)
4. Schedule FA for unvested RSUs — conservative practice includes them
5. Budget 2025 changes to capital gains rates
6. New Tax Regime impact on STCG slab rates

---

## Penalty for Non-Disclosure

- Schedule FA non-disclosure: Rs 10 lakh penalty under Black Money Act 2015
- Undisclosed foreign income: flat 30% tax + penalty
