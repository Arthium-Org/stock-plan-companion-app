# Requirements Document: M7b — Stock Price Service

## Introduction

The Stock Price Service fetches historical and current stock prices from Yahoo Finance. Historical close prices are stored on tranches as `vest_day_close` — a fallback display value when actual `vest_fmv` (from G&L/broker) is unavailable. Current stock prices are fetched live and cached for portfolio valuation.

## Glossary

- **vest_day_close**: Adjusted close price of the stock on the vest/purchase date — from Yahoo Finance. Stored on tranches. Distinct from `vest_fmv` which is the actual broker-reported FMV.
- **Current_Price**: Live stock price for portfolio current value — cached briefly, not stored in Silver.

## Requirements

### Requirement 1: Historical Close Price

**User Story:** As a developer, I want the adjusted close price on vest dates, so that I can display an approximate FMV when broker-actual FMV is unavailable.

#### Acceptance Criteria

1. THE service SHALL fetch historical adjusted close prices from Yahoo Finance
2. THE service SHALL support fetching price for a specific symbol and date
3. IF the exact date is a weekend/holiday, THE service SHALL return the most recent trading day's close
4. THE service SHALL be callable as `StockPlan.StockPrice.get_close(symbol, date)`
5. THE return value SHALL be a decimal string or nil

### Requirement 2: Tranche Enrichment — vest_day_close

**User Story:** As a developer, I want vest_day_close stored on tranches, so that the UI can display it as a fallback when vest_fmv is nil.

#### Acceptance Criteria

1. THE system SHALL add `vest_day_close` (SafeDecimal, nullable) to `stock_plan_tranches`
2. THE Silver Builder SHALL fill `vest_day_close` during a post-build enrichment pass
3. `vest_day_close` SHALL be filled for ALL VESTED tranches (even those with vest_fmv from G&L)
4. `vest_day_close` is an independent field — it does NOT replace or overwrite `vest_fmv`
5. IF Yahoo Finance returns no data for a date, THE field SHALL remain nil

### Requirement 3: Current Stock Price

**User Story:** As a user, I want to see the current stock price on the portfolio page.

#### Acceptance Criteria

1. THE service SHALL provide `StockPlan.StockPrice.current_price(symbol)` returning the latest price
2. THE current price SHALL be cached for a configurable duration (default: 15 minutes)
3. THE current price SHALL NOT be stored in Silver (fetched live)
4. IF Yahoo Finance is unavailable, THE service SHALL return the cached value or nil

### Requirement 4: Batch Fetch

**User Story:** As a developer, I want to fetch prices for multiple dates efficiently, so that vest_day_close can be populated during rebuild.

#### Acceptance Criteria

1. THE service SHALL support batch fetch: `get_close_range(symbol, from_date, to_date)` returning a map of `{date => price}`
2. Yahoo Finance historical API returns daily data — one API call covers a date range
3. THE batch result SHALL be used to populate multiple tranches in one pass

### Requirement 5: Error Handling and Resilience

1. IF Yahoo Finance API fails (timeout, 5xx, network error), THE service SHALL return nil or empty map — never raise, never fail the rebuild
2. IF Yahoo returns no data for a symbol, THE service SHALL return nil (invalid symbol)
3. THE Silver Builder SHALL continue rebuild even if stock price enrichment partially fails — missing prices are nil, not errors
4. Future: if date range exceeds 2 years, split into chunks (not implemented yet)

### Data Type Convention

- Internal computation: `%Decimal{}` (FX) or `String.t()` (stock price)
- Storage: SafeDecimal (TEXT in SQLite)
- API boundary (to UI): `String.t()`
