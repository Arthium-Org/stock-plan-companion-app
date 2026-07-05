# Requirements Document: M7a — FX Rate Service

## Introduction

The FX Rate Service provides SBI TT Buying Rates for USD/INR conversion as required by Indian income tax law. Per tax rules, the conversion rate for any transaction is the **SBI TT Buying Rate on the last day of the month preceding the transaction month**. The service maintains a master table of monthly rates with three rate fields, a seed script for historical data, and applies rates to Silver records during rebuild.

## Requirements

### Requirement 1: FX Rate Master Table

1. THE system SHALL store rates in `stock_plan_fx_monthly_rates` table. Schema module: `StockPlan.Schema.FxMonthlyRate`
2. EACH row SHALL represent rates for one calendar month
3. THE table SHALL have columns:
   - `id` (TEXT PK)
   - `rate_date` (:date — last day of the month)
   - `year_month` (TEXT — "2024-03" for quick lookup)
   - `currency_pair` (TEXT — "USD/INR")
   - `tt_buying_rate_month_end` (SafeDecimal — SBI TT Buying Rate on last day of month)
   - `standard_rate_month_end` (SafeDecimal — RBI reference rate on last day of month)
   - `standard_rate_month_avg` (SafeDecimal — monthly average market rate)
   - `source` (TEXT)
   - `timestamps`
4. THE `{year_month, currency_pair}` SHALL have a unique index

### Requirement 2: Rate Lookup — Previous Month Rule

1. `FX.get_rate(date)` SHALL return the rate from the last day of the PREVIOUS month
2. **Priority:** `tt_buying_rate_month_end` → `standard_rate_month_end` → `standard_rate_month_avg`
3. FOR transaction date 2024-04-15, return the rate for year_month "2024-03"
4. IF no rate exists for the required month, return nil
5. `FX.get_rate_string(date)` SHALL return the rate as a string (for SafeDecimal fields)
6. `FX.current_rate()` SHALL return the most recent available rate

### Requirement 3: Rate Data — Seeded Historical Data

1. 333 monthly rates seeded via `priv/repo/fx_seed_data.exs`
2. **TT Buying Rate (2020–2026, 76 months):** SBI TT Buy on last day of month. Sources: sahilgupta/sbi-fx-ratekeeper GitHub, taxroutine.com
3. **Standard Rate Month-End (Aug 1998–2026, 289 months):** RBI reference rate. Source: rbi.org.in/scripts/ReferenceRateArchive.aspx
4. **Standard Rate Month-Avg (2016–2026, 124 months):** Monthly average. Source: x-rates.com
5. No gaps in standard_rate_month_end from Aug 1998 onwards
6. TT buying rate is consistently ~₹0.43 (0.51%) lower than RBI standard — expected (TT buy is bank buying rate)

### Requirement 4: Silver Builder Integration (Phase 3)

1. THE Silver Builder SHALL fill `origin_fx_rate` on all origins using `FX.get_rate(origin_date)`
2. THE Silver Builder SHALL fill `vest_fx_rate` on VESTED tranches using `FX.get_rate(vest_date)`
3. THE Silver Builder SHALL fill `sale_fx_rate` on all sales using `FX.get_rate(sale_date)`
4. Fill-only: never overwrite existing rates
5. If rate not available for a date, field remains nil

### Requirement 5: UI Disclaimer

1. Display note: "FX rates use SBI TT Buying Rate (available from 2020). Earlier dates use RBI reference rate."
