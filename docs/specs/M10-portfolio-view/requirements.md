# Requirements Document: M10 — Portfolio View (Revised)

## Introduction

The Portfolio View shows **current holdings only** — what the user owns today and what's coming (unvested). It answers one question: "What's my stock plan worth today?"

**Data source:** Holdings (ByBenefitType) ingestion is the **sole source** for this page. Benefits History and G&L feed Tax Centre and History pages, NOT Portfolio.

| Data Source | Page | What it shows |
|---|---|---|
| **Holdings (ByBenefitType)** | **Portfolio** | Current owned shares, sellable qty, broker cost basis |
| Benefits History | Tax Centre, History | Transaction history, lifetime events |
| G&L Expanded | Tax Centre | Lot-level sell details, capital gains |

**No Holdings data = empty Portfolio.** The page will show "Upload your Holdings file to see portfolio" instead of attempting to derive holdings from Benefits History.

## Requirements

### Requirement 1: Portfolio Page Route

1. THE page SHALL be at `GET /portfolio`
2. THE page SHALL be a LiveView (`StockPlanWeb.PortfolioLive`)
3. THE page SHALL fetch current stock price (cached) and current FX rate on mount

### Requirement 2: Data Source — Portfolio Composition

1. THE Portfolio SHALL read from tranches enriched by Holdings (M3b Phase 5)
2. THE Portfolio SHALL use `sellable_qty` (broker-reported) as the vested available quantity
3. THE Portfolio SHALL use `cost_basis_broker` (broker-calculated) as the primary cost basis
4. THE Portfolio SHALL NOT derive available quantity from sale_allocations or benefit history
5. IF no Holdings data has been ingested, THE page SHALL show an empty state with upload prompt

**Explicit composition rules:**

| Row type | Source | Condition |
|---|---|---|
| VESTED | Holdings (sellable_qty > 0) | Holdings ingestion exists |
| UNVESTED | Benefit History (vest schedule) | BH ingestion exists |

**Behavior matrix:**

| Holdings | BH | Portfolio shows |
|---|---|---|
| Yes | Yes | Vested (from Holdings) + Unvested (from BH) |
| Yes | No | Vested only (no future schedule available) |
| No | Yes | **Empty** — no guessing from BH |
| No | No | Empty with upload prompt |

Holdings NEVER provides unvested data. BH NEVER provides vested/sellable data for Portfolio.

### Requirement 3: Summary Cards

**User Story:** As a user, I want to see my current asset value and potential future value at a glance.

#### Acceptance Criteria

1. THE page SHALL display three summary cards (E*Trade style):
   - **Total Account Value** — Current + Potential
   - **Current Value** — sum of (sellable_qty x current_price) across all vested tranches with Holdings data
   - **Potential Benefit Value** — sum of (unvested_qty x current_price) across unvested tranches
2. Below the totals, breakdown by plan type:
   - RSU: Current Value + Potential Value
   - ESPP: Current Value + Potential Value
3. THE summary SHALL show current stock price
4. Summary SHALL update when currency toggle changes (USD/INR)

### Requirement 4: Holdings Table — Grouping, Filtering, Sorting

**User Story:** As a user, I want to view my holdings grouped by plan type or status, filtered to what matters.

#### Scope: Current Holdings Only

THE table SHALL show **sellable (vested)** and **unvested** tranches from Holdings data. No sold tranches. No realized gains.

#### Table Columns

1. EACH row at tranche level:
   - Grant Number / Enrollment Date
   - Vest Date
   - Status (Vested / Unvested)
   - Qty — sellable_qty for vested (from Holdings), vest_quantity for unvested
   - Cost Basis per share — cost_basis_broker (from Holdings). Fallback: vest_fmv, vest_day_close
   - Current Value (qty x current_price)
   - Unrealized P&L (current value - cost basis — vested only)
2. Vested rows: color-coded by P&L (green profit / red loss)
3. Unvested rows: show potential value, no P&L

#### Grouping

4. Two grouping modes:
   - **Group by Type** (default): ESPP -> RSU, sub-grouped by grant
   - **Group by Status**: Vested -> Unvested
5. Group headers show subtotals

#### Filters (pinned chips)

6. Status filter chips:
   - **Vested** — DEFAULT ON
   - **Unvested** — DEFAULT ON
7. P&L filter chips (applies to vested only):
   - **Profit only** — P&L > 0
   - **Loss only** — P&L < 0
   - Default: both (no P&L filter)
8. Multiple filters toggleable simultaneously

#### Sorting

9. DEFAULT sort: vest date (newest first) within each group
10. Sortable columns: Vest Date, Grant Number, Current Value, Unrealized P&L
11. Sort direction toggles on click (asc <-> desc)

### Requirement 5: Cost Basis Priority

1. **Primary:** `cost_basis_broker` (from Holdings) — broker-calculated, authoritative
2. **Fallback 1:** `vest_fmv` (from G&L) — actual FMV from tax lot report
3. **Fallback 2:** `vest_day_close` (from Yahoo) — market close, approximate (show with *)
4. **Fallback 3:** nil — show "N/A"
5. Unvested tranches have NO cost basis

**Invariant:** This is a pure fallback chain, NOT a reconciliation. If `cost_basis_broker` exists, it is authoritative — never compare or "correct" against `vest_fmv`. They may differ (broker includes adjustments like wash sale, ESPP qualification rules) and that's correct.

### Requirement 6: Sellable Quantity

1. **Primary:** `sellable_qty` (from Holdings) — broker says exactly what's sellable
2. **Filter:** `sellable_qty > 0` — tranches with sellable_qty = 0 are fully sold, excluded from Portfolio
3. **No fallback.** Without Holdings data, portfolio is empty — we don't guess.
4. Blocked status from Holdings is informational (metadata), not a portfolio filter

### Requirement 7: Currency Toggle (USD / INR)

1. USD/INR toggle, default USD
2. INR values (per row):
   - Current value INR = (sellable_qty x current_price) x current_fx_rate
   - Cost basis INR = (cost_basis x sellable_qty) x vest_fx_rate
   - P&L INR = current_value_inr - cost_basis_inr
3. Reactive — no page reload

### Requirement 8: FMV Source Indicator

1. cost_basis_broker: show as-is (broker-authoritative)
2. vest_fmv fallback: show as-is (actual broker FMV)
3. vest_day_close fallback: show with asterisk (*), tooltip "Market Adjusted Close"
4. No cost basis: show "N/A"

### Requirement 9: FX Disclaimer

1. Subtle footer note: "FX: SBI TT Buying Rate (2020+), RBI Reference Rate (earlier)"

### Requirement 10: Empty State

1. IF no Holdings ingestion exists: show "Upload your ByBenefitType file to view portfolio"
2. IF Holdings ingested but no matching tranches: show "No holdings found"
3. Link to upload page from empty state

### Requirement 11: Snapshot Timestamp

1. THE page SHALL display "Holdings as of: {date}" showing when the Holdings file was uploaded
2. Source: `inserted_at` from the ACTIVE Holdings ingestion record
3. This makes clear the data is a point-in-time snapshot, not live
