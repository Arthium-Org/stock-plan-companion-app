# Requirements: M14b — Schedule FSI (Foreign Source Income)

## Introduction

Schedule FSI declares foreign source income in the Indian ITR. For stock plan holders, the relevant income heads are:

- **Capital Gains** — STCG + LTCG from selling shares (from G&L data)
- **Other Sources** — Dividend income (future — not in current data)

**NOT foreign source income** (excluded from FSI):
- RSU vest perquisite → Indian salary income (employer reports in Form 16)
- ESPP discount perquisite → Indian salary income

**Period:** Financial Year (Apr 1 - Mar 31)

> **See also:** [Indian Tax Rules](../../core/indian-tax-rules.md)

---

## Requirement 1: Schedule FSI Data

1. THE system SHALL generate Schedule FSI for a selected Financial Year
2. Output: one row per country (USA only for Phase 1) with income breakdown by head

### Income Heads (for stock plans)

| Sl No | Head of Income | Source | Amount |
|---|---|---|---|
| i | Salary | NOT applicable (not foreign income) | — |
| ii | House Property | NOT applicable | — |
| iii | Capital Gains | From M14 Capital Gains | STCG (INR) + LTCG (INR) |
| iv | Other Sources | Dividends (future) | ₹0 for Phase 1 |

### Capital Gains Detail

3. Capital Gains SHALL show breakdown: `shortTerm: $X/₹Y   longTerm: $X/₹Y`
4. Values from `CapitalGains.build(account_id, fy_start_year)` summary

### Tax Paid Outside India

5. For Capital Gains: `$0/₹0` — no US withholding on share sales for Indian residents
6. For Dividends: from broker 1042-S (future — user-entered for now)
7. Phase 1: Capital Gains tax_paid = 0 (no US withholding on CG)

### Tax Payable in India

8. "User to populate" — depends on individual's slab rate and total income
9. System cannot compute this without knowing user's full income profile
10. Show as placeholder: "User to populate based on effective tax rate"

### Tax Relief

11. For Capital Gains: "Not applicable for CG as no withholding"
12. For Dividends: "User to populate" (future)
13. DTAA article: "Nil" for CG, relevant article for dividends

## Requirement 2: Schedule FSI UI

1. Add as third tab on Tax Centre page: "Schedule FA | Capital Gains | Schedule FSI"
2. FY selector (same as Capital Gains)
3. Preview table matching ITR Schedule FSI format
4. Fields populated automatically where possible, "User to populate" for manual fields

## Requirement 3: Schedule FSI Download

1. Downloadable CSV matching ITR format
2. Columns: Sl No, Country Code, TIN, Head of Income, Income (INR), Tax Paid Outside (INR), Tax Payable in India, Tax Relief, DTAA Article
3. Filename: `Schedule_FSI_FY{year}-{year+1}.csv`

## Requirement 4: Data Dependencies

1. Capital Gains: from existing `CapitalGains.build` (M14)
2. Dividends: ₹0 for Phase 1 (no dividend tracking yet)
3. US tax withholding: ₹0 for CG, placeholder for dividends

## Out of Scope (Phase 1)

- Salary head (RSU/ESPP perquisite is Indian salary, not FSI)
- Dividend income tracking
- Form 67 (Foreign Tax Credit claim)
- Schedule TR (Tax Relief computation)
- Actual tax payable computation (needs user's full income)
