# Tasks: M10 Portfolio — UX Fixes (Round 2)

## Prerequisites

- M5b: Holdings Silver (done)
- Existing Portfolio LiveView with hierarchical view

---

## Milestone A: Tranche Sub-Table (UX-1)

- [ ] A.1 Replace sibling `<tr>` tranche rows with `<td colspan>` containing nested `<table>`
- [ ] A.2 Inner table: `table-xs`, `ml-6`, `bg-base-200/30`, `border border-base-300 rounded`
- [ ] A.3 Apply to both RSU and ESPP expanded sections
- [ ] A.4 Manual test: expand grant, verify columns don't align with parent

## Milestone B: Data Completeness

### B1: RSU Grant Row (UX-7)
- [ ] B1.1 Add Sellable column: sum of sellable_qty across vested tranches
- [ ] B1.2 Update grant row template: Grant# | Date | Granted | Vested | Sellable | Unvested | Value | Potential | P&L

### B2: RSU Tranche Row (UX-6)
- [ ] B2.1 Add Released Qty column between Vest Qty and Sellable
- [ ] B2.2 Tranche columns: # | Vest Date | Vest Qty | Released | Sellable | Cost Basis

### B3: ESPP Lock-In Price (UX-4)
- [ ] B3.1 Clean `$` prefix from `grant_date_fmv` in HoldingsSilverBuilder ESPP processing
- [ ] B3.2 Extract `origin_fmv` from tranche metadata in `build_origin_group_from_holdings`
- [ ] B3.3 Manual test: ESPP enrollment row shows Lock-In Price

### B4: Unvested Sellable (UX-5)
- [ ] B4.1 Unvested tranche rows: Sellable column shows "—" instead of "TBD"

### B5: RSU Section Summary (UX-11)
- [ ] B5.1 Show share quantities: "Vested: X shares (Y sellable) | Unvested: Z shares"
- [ ] B5.2 Add `compute_origin_sellable` helper
- [ ] B5.3 Add `rsu_sellable_qty` section-level helper

## Milestone C: Summary Card (UX-10)

- [ ] C.1 Add `unvested_shares` to summary (sum of unvested quantities)
- [ ] C.2 Potential Value card: "X shares (N vests)" format

## Milestone D: Filters (UX-8, UX-9)

- [ ] D.1 Debug: verify `build_filtered_hierarchical` actually filters tranches
- [ ] D.2 Verify template reads from `@filtered_by_type` not `@hierarchical`
- [ ] D.3 Fix: ensure Vested/Unvested toggle hides/shows rows
- [ ] D.4 Fix: Profit/Loss filter hides tranches and empty parent grants
- [ ] D.5 "No matching holdings" when section has zero visible tranches
- [ ] D.6 Manual test: all 4 filters work independently and combined

## Milestone E: Sorting (UX-2)

- [ ] E.1 Add `:grant_sort` assign — `{field, :asc | :desc}`, default `{:grant_date, :asc}`
- [ ] E.2 Add `"sort_grants"` event handler
- [ ] E.3 Sortable columns: Grant Date, Granted Qty, Current Value, P&L
- [ ] E.4 Sort indicator (↑/↓) on active column header
- [ ] E.5 Apply sort in `assign_filtered` after building hierarchical data
- [ ] E.6 Manual test: click headers, verify sort toggles

## Milestone F: By Status View Fixes (UX-12)

- [ ] F.1 Change column header from "Grant / Date" to "Grant #"
- [ ] F.2 RSU rows: show grant_number
- [ ] F.3 ESPP rows: show "—" (no broker-assigned grant number)

## Milestone G: Verification

- [ ] F.1 `mix format --check-formatted`
- [ ] F.2 `mix compile --warnings-as-errors`
- [ ] F.3 `mix test` — all pass
- [ ] F.4 Manual test: User 3 — ESPP + RSU, expand/collapse, all columns correct
- [ ] F.5 Manual test: User 2 — RSU only, filters work
- [ ] F.6 Manual test: User 1 — empty portfolio (BH fallback)
- [ ] F.7 Manual test: INR toggle with correct formatting

---

## Definition of Done

- [ ] Tranche detail visually nested (sub-table, indented, distinct bg)
- [ ] RSU grant row: 4 qty fields + Grant FMV + Value + Potential + P&L
- [ ] RSU tranche: 3 qty fields (vest, released, sellable) + cost basis
- [ ] ESPP lock-in price visible
- [ ] Unvested sellable shows "—"
- [ ] Section summaries show share quantities with sellable
- [ ] Summary card shows unvested share count
- [ ] All filters work on hierarchical view
- [ ] Grant-level sorting works
- [ ] All tests pass
