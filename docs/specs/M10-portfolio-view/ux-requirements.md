# Requirements: M10 Portfolio View — UX Rewrite

## Introduction

10 UX issues identified during review. E*Trade "Holdings" and "Benefit History" pages serve as reference (screenshots in `docs/Sample-Data/E-trade Screenshots/`).

---

## Requirement 1: Tab Navigation

Current toggle buttons are ambiguous. Replace with clear tab navigation.

1. THE page SHALL use DaisyUI tabs (`tabs tabs-bordered`) for "By Type" / "By Status" views
2. Active tab SHALL be visually distinct (underlined, bold)
3. "By Type" SHALL be the default active tab

## Requirement 2: Filter Chip Styling

Unselected filters look like floating text.

1. Active filter chips SHALL be colored (current behavior)
2. Inactive filter chips SHALL have a bordered outline (`btn-outline`), not invisible (`btn-ghost`)
3. ALL chips SHALL look like toggleable UI elements regardless of state

## Requirement 3: Collapsible Hierarchy

Current flat table → E*Trade-style expandable hierarchy. Only applies to "By Type" view.

### ESPP Layout

1. **Section header** (always visible): "Employee Stock Purchase Plan (ESPP)" with summary stats (total qty, current value, P&L)
2. **Level 1 — Enrollment rows** (collapsible): One row per enrollment (origin). Columns: Grant Date, Lock-In Price (origin_fmv), Total Qty, Current Value, P&L
3. **Level 2 — Purchase rows** (visible on expand): One row per purchase (tranche). Columns: Purchase Date, Purchase FMV (cost_basis_broker), Purchase Qty, Sellable Qty, Current Market Value
4. ESPP identifier SHALL be the enrollment Grant Date, NOT the system-generated hash

### RSU Layout

5. **Section header** (always visible): "Restricted Stock (RS)" with summary stats (vested count, unvested count, current value, potential value, P&L)
6. **Level 1 — Grant rows** (collapsible): One row per grant (origin). Columns: Grant Number, Grant Date, Granted Qty, Vested Qty, Unvested Qty, Current Value, Potential Value, P&L
7. **Level 2 — Tranche rows** (visible on expand): One row per vest (tranche). Columns: Vest Period #, Vest Date, Vest Qty, Sellable Qty, Cost Basis

### Expand/Collapse Behavior

8. Default state: ALL collapsed
9. Click on Level 1 row toggles expand/collapse
10. Chevron icon: right (▸) when collapsed, down (▾) when expanded

## Requirement 4: Company Name and Price

1. THE header SHALL display company name and symbol: "Adobe (ADBE)"
2. THE header SHALL display current share price prominently: "$XXX.XX"

## Requirement 5: FX Rate Display

1. THE page SHALL display current USD to INR rate: "1 USD = ₹XX.XX"
2. Displayed near the USD/INR toggle button

## Requirement 6: Negative P&L Formatting

1. Negative values SHALL display sign before currency symbol: `-$1,234.56` not `$-1,234.56`
2. ALL monetary values SHALL use comma-separated thousands: `$1,234.56` not `$1234.56`
3. Values rounded to 2 decimal places

## Requirement 7: ESPP Identifier

1. ESPP rows SHALL display the enrollment Grant Date as identifier
2. SHALL NOT display the system-generated hash grant_number
3. Format: date display (e.g., "01-Jul-2022")

## Requirement 8: Consistent Sort Order

1. Grants/enrollments SHALL be sorted by date ascending (oldest first)
2. Tranches SHALL be sorted by vest_date ascending (oldest first) within each grant
3. Matches E*Trade's display order

## Requirement 9: Unvested Value Display

1. Unvested values SHALL be labeled "Potential" to distinguish from vested value
2. Unvested values SHALL be styled differently: lighter/italic text
3. Unvested rows SHALL NOT show P&L (no cost basis yet)

## Requirement 10: Quantity Label Mapping

All UI labels SHALL map to specific backend fields:

| UI Label | Backend Field | Context |
|---|---|---|
| Qty (ESPP enrollment summary) | sum of tranche sellable_qty | What you own now |
| Qty (RSU grant vested) | sum of tranche sellable_qty | What you can sell |
| Qty (RSU grant unvested) | sum of tranche vest_quantity where UNVESTED | Scheduled future vests |
| Vest Qty (tranche row) | vest_quantity | Shares in this vest event |
| Sellable (tranche row) | sellable_qty | Broker-confirmed sellable |
| Cost Basis (ESPP) | cost_basis_broker (= Purchase Date FMV) | Label: "Cost Basis (FMV)" |
| Cost Basis (RSU) | cost_basis_broker (= vest date FMV) | Label: "Cost Basis" |

**Invariant:** All "Current Value" calculations MUST use sellable_qty, not vest_quantity. Potential Value uses vest_quantity for UNVESTED tranches only.

## Requirement 11: Filter Interaction Rules

1. Profit/Loss filters SHALL apply ONLY to vested rows
2. Unvested rows are unaffected by Profit/Loss filter selection
3. If user selects "Unvested + Profit": unvested rows shown, vested rows filtered to profit only

## Requirement 12: Expand State Key

1. Expand/collapse state SHALL use `{plan_type, origin_id}` as key (not origin_id alone)
2. Prevents theoretical collision across plan types

## Requirement 13: Empty Section Stubs

1. ESPP and RSU sections SHALL always be visible (even if no data)
2. Empty sections SHALL show "No current holdings" message
3. When filters hide all tranches in a section, show "No matching holdings"

## Requirement 14: INR P&L Computation

1. Origin-level INR P&L MUST be computed as sum of tranche-level INR P&Ls
2. Each tranche uses its own vest_fx_rate for conversion
3. SHALL NOT convert aggregated USD P&L with a single FX rate
