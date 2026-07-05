# Requirements: M21 — Tranche Timeline Builder

## Introduction

Build a per-tranche timeline that determines the state of each lot at any point in time. This is the foundation for Schedule FA (and future tax features) — answering "what did the user hold during CY X?"

Three data sources combined:

| Source | What it tells us | Granularity |
|---|---|---|
| **Holdings** | What's held NOW (current snapshot) | Per tranche (sellable_qty) |
| **G&L** | What was sold RECENTLY (tranche-level) | Per tranche (qty, date, price) |
| **BH** | What vested and when sells happened | Per origin (events) |

**Key principle:** No guessing. Either the data exists for the requested period or the feature is unavailable.

---

## Requirement 1: Data Validation

Before building timeline, validate data completeness:

### V1: Holdings vs Timeline Quantity Match

Compare Holdings snapshot against timeline-derived state (NOT BH directly):

```
For each origin (grant/enrollment):
  held_from_timeline = SUM(tranche.net_quantity - tranche.total_sold) per tranche
  held_from_holdings = SUM(Holdings sellable_qty) per tranche
  
  VALIDATE: held_from_timeline == held_from_holdings
  TOLERANCE: ±1 share (rounding, fractional ESPP shares)
  FAILURE: WARNING — "Grant {X}: timeline says {A} held, Holdings says {B}"
```

**Note:** V1 compares Holdings vs Timeline, not Holdings vs BH. Timeline is the computed state from sell events (G&L allocations for RSU, BH events for ESPP). This avoids cross-granularity comparisons.

### V2: G&L Coverage for CY (per-date check)

```
For a requested CY (RSU only — ESPP uses BH events):
  bh_sell_dates = all BH "Shares sold" event dates for RSU in this CY
  
  IF bh_sell_dates is empty:
    → No RSU sells in this CY. G&L not required. PASS.
  
  IF bh_sell_dates is not empty:
    gl_allocation_dates = all sale_allocation dates from G&L
    
    FOR EACH bh_sell_date:
      VALIDATE: bh_sell_date exists in gl_allocation_dates
    
    missing_dates = bh_sell_dates not found in gl_allocation_dates
    
    IF missing_dates not empty:
      FAILURE: ERROR — "G&L data missing for sell dates: {dates}. Upload G&L for {CY}."
```

**Per-date check, NOT range-based.** Range check would falsely pass when G&L has gaps (e.g., 2023 + 2025 uploaded, 2024 missing).

### V3: No Gaps in G&L Allocations (RSU only)

```
For all BH RSU sell events that have a matching date in G&L:
  Each should have sale_allocations with total qty matching BH sale qty
  
  unallocated = BH RSU sales where matching G&L sale has zero allocations
  
  VALIDATE: unallocated == 0
  FAILURE: WARNING — "{N} RSU sell events have no lot allocation in G&L"

ESPP is excluded from V3 — ESPP timeline uses BH events directly.
```

### Invariant

```
For every tranche in the timeline:
  held_from_timeline = net_quantity - total_sold
  
  IF Holdings exists for this tranche:
    held_from_timeline ≈ held_from_holdings (±1)
  
  This invariant MUST hold after timeline construction.
  Violation = data inconsistency between sources.
```

## Requirement 2: Timeline Construction

For each RSU tranche, build a state timeline:

```
Tranche T (vest_date, net_quantity):

  Events (chronological):
    vest_date: VESTED with net_quantity shares
    sale_date_1: SOLD x shares (from G&L allocation)
    sale_date_2: SOLD y shares (from G&L allocation)
    ...
  
  At any point in time:
    held_qty = net_quantity - SUM(sold before that date)
  
  Current:
    held_qty should match Holdings sellable_qty (V1 validation)
```

### ESPP Timeline

Same as RSU — G&L is the primary source of sell data (has price).

```
Purchase tranche (vest_date = purchase_date, net_quantity):
  Primary: G&L allocations (tranche-level, has sell price)
  Fallback: BH sell events matched by quantity (has date, NO price)
  Holdings provides current state
```

G&L is required for ESPP sells that appear in Capital Gains (need sell price).
BH fallback only determines "sold or not" for Schedule FA — no price available.

## Requirement 3: Schedule FA Query

```
ScheduleFA.build(account_id, calendar_year):

  1. Run validations (V1, V2, V3)
     - If V2 fails (missing G&L) → return {:error, "Upload G&L for {CY}"}
     - If V1/V3 fail → return {:ok, data, warnings}

  2. For each tranche vested on or before Dec 31:
     cy_start = Jan 1
     cy_end = Dec 31
     
     held_at_cy_start = net_quantity - SUM(sells before cy_start)
     held_at_cy_end = net_quantity - SUM(sells on or before cy_end)
     sells_during_cy = SUM(sells between cy_start and cy_end)
     
     IF held_at_cy_start == 0 AND sells_during_cy == 0:
       → Not held during CY. Skip.
     
     ELSE:
       → Include in FA with:
         - quantity_start: held_at_cy_start (or net_qty if vested during CY)
         - quantity_end: held_at_cy_end
         - initial_value, peak_value, closing_value (as before)
         - sale_proceeds: from sells during CY
```

## Requirement 4: Validation UI

1. Show validation results before FA data
2. Errors: block FA generation, show message with action ("Upload G&L for 2024")
3. Warnings: show FA data with warning banner

## Requirement 5: ESPP Handling

1. ESPP BH has per-purchase sell events with quantity — tranche-level timeline is directly available
2. Sell events tagged with `source: :bh` (vs `:gl` for RSU)
3. G&L provides price enrichment but timeline comes from BH
4. **Guard:** If an ESPP sell event cannot be mapped to a specific purchase lot (no parent-child link in BH), emit WARNING: "ESPP sell allocation unclear for {date}". Do not silently proceed with incorrect mapping.
5. V2 (G&L coverage check) applies to RSU only — ESPP doesn't need G&L for timeline
6. V3 (gap check) applies to RSU only — ESPP uses BH events

## Requirement 6: BH Sold Validation (per-origin reconciliation)

Determine sold status of tranches using BH sale totals, with or without Holdings.

### Per-origin reconciliation

```
For each origin (grant/enrollment):
  total_released = SUM(tranche.net_quantity) for all VESTED tranches
  gl_sold        = SUM(G&L allocation quantities) for this origin's tranches
  bh_sold        = SUM(BH sale event quantities) for this origin

  IF bh_sold == total_released:
    → Origin fully sold. Mark tranches without G&L sells as sold (holdings_qty = 0).
  
  IF bh_sold < total_released:
    → Some shares still held. Holdings required to know which tranches.
    → If Holdings uploaded: holdings_qty from Holdings is ground truth.
    → If Holdings NOT uploaded: cannot determine — leave as unknown.
  
  IF bh_sold > total_released:
    → Data error. Emit WARNING: "Grant {X}: BH sold {A} > released {B}"
```

### When Holdings IS uploaded

Additional cross-check available:
```
  held_from_holdings = SUM(Holdings sellable_qty) for this origin (nil → 0)
  expected_sold = total_released - held_from_holdings
  
  VALIDATE: bh_sold ≈ expected_sold (±2 tolerance)
  
  For tranches not in Holdings and without G&L sells:
    → Set holdings_qty = 0 (confirmed sold)
    → Holdings override in held_during_cy excludes them from FA
```

### When Holdings is NOT uploaded

```
  IF bh_sold == total_released:
    → Fully sold. Set holdings_qty = 0 for tranches without G&L sells.
  
  IF bh_sold < total_released:
    → Remaining = total_released - bh_sold
    → Cannot assign to specific tranches without Holdings.
    → Leave holdings_qty = nil (unknown).
```

### ESPP quantity matching

ESPP BH sales are per-purchase with specific quantities. Before BH validation:
```
  For ESPP tranches without G&L allocations:
    Match BH sales to tranches by quantity (net_quantity == sale.total_quantity)
    If matched → use BH sale date as the sell date (source: :bh)
```

## Requirement 7: Timeline Summary (per-symbol reconciliation)

Provide a per-symbol summary for diagnostics and UI display.

```
TrancheTimeline.summary(timelines, bh_sales) → per-symbol map

For each symbol:
  bh_summary:
    total_released:  SUM(net_quantity) of all VESTED tranches
    total_sold_bh:   SUM(BH sale event quantities)
    vested_unsold:   total_released - total_sold_bh
    unvested:        count/qty of tranches with status != VESTED

  holdings_summary (if Holdings uploaded):
    vested_held:     SUM(Holdings sellable_qty)
    
  gl_summary:
    total_sold_gl:   SUM(G&L allocation quantities)

  reconciliation:
    status:          :reconciled | :holdings_needed | :error
    
    :reconciled      → bh_sold == total_released (all sold)
                       OR holdings matches (bh_sold + held == released)
    :holdings_needed → bh_sold < total_released AND no Holdings
    :error           → bh_sold > total_released
```

### Usage

- **Diagnostics:** "Does the data add up?" before generating FA/CG
- **UI:** Show reconciliation status per symbol
- **BH validation:** Use summary to drive sold detection logic

## Out of Scope

- Automatic G&L gap detection across multiple years
- Historical Holdings snapshots (only current snapshot available)
- Inferring which tranche was sold without G&L (no FIFO assumption for per-tranche sell dates)
