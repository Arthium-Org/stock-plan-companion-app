# UX Fixes

Living spec — tracks UI/UX issues found during multi-user testing. Updated as issues are found and fixed.

---

## Issue UX-1: Expanded tranche rows visually merge with grant rows

**Found:** User 1 — expanding RSU grant shows tranche rows that align with grant columns above. No visual separation.

**Problems:**
- Tranche column headers align under grant column headers — confusing since they have different fields
- No color/background differentiation between grant row and child tranche rows
- No border or indentation to show parent-child hierarchy
- Field names from grant header row appear to label tranche data

**Fix:**
- Tranche sub-table should be visually indented (left padding or nested inside a cell spanning full width)
- Distinct background color for tranche rows (e.g., slightly darker or tinted)
- Tranche sub-table should have its own header row, clearly separated from the grant table
- Consider rendering tranche rows inside a `<td colspan="N">` with an inner table, rather than as sibling `<tr>` rows

**Status:** Open

---

## Issue UX-2: No sorting available

**Found:** User 1 — no ability to sort grant rows or tranche rows.

**Sortable fields (to decide):**

| Level | Field | Default Sort | Sortable? |
|---|---|---|---|
| ESPP enrollment | Grant Date | Ascending | Yes |
| ESPP purchase (tranche) | Purchase Date | Ascending | No (few rows) |
| RSU grant | Grant Date | Ascending | Yes |
| RSU grant | Granted Qty | — | Yes |
| RSU grant | Current Value | — | Yes |
| RSU grant | P&L | — | Yes |
| RSU tranche | Vest Date | Ascending | No (within grant, keep chronological) |

**Recommendation:** Sort at grant/enrollment level only. Tranches stay chronological within their parent.

**Status:** Open

---

## Testing Matrix

| Issue | User 1 | User 2 | User 3 | User 4 |
|---|---|---|---|---|
| UX-1 | Found | — | — | — |
| UX-2 | Found | — | — | — |

---

## Issue UX-4: ESPP Lock-In Price blank at enrollment level

**Found:** User 3 — ESPP enrollment row shows blank for Lock-In Price column.

**Root Cause:** Two issues:
1. `build_origin_group_from_holdings` hardcodes `origin_fmv: nil` — doesn't extract from data
2. Grant Date FMV is stored in `metadata_json` as `grant_date_fmv` with `$` prefix (e.g., `"$368.48"`) — needs `VN.clean_number` to strip `$`

**Fix:** 
- Store Grant Date FMV as a cleaned number in Holdings Silver (either a new field or extract from metadata in Portfolio.build)
- Strip `$` during HoldingsSilverBuilder ESPP processing

**Status:** Open

---

## Issue UX-3: Missing Sellable count at RSU grant level

**Found:** User 3 — RSU grant row shows Granted, Vested, Unvested but no Sellable. Current Value is based on sellable count, so user can't verify the math without expanding.

**Fix:** Add Sellable column at grant level = sum of sellable_qty across vested tranches for that grant.

**Status:** Open

---

## Issue UX-7: RSU grant row should show 4 quantity fields

**Found:** User 3 — RSU grant row shows Granted, Vested, Unvested but missing Sellable. Need all 4:

| Field | Source | Meaning |
|---|---|---|
| Granted | origin.total_quantity | Total shares in the grant |
| Vested | sum(vested tranches qty) | Shares that have vested |
| Sellable | sum(sellable_qty for vested tranches) | Currently owned (after sells) |
| Unvested | sum(unvested tranches qty) | Scheduled future vests |

Current Value is computed from Sellable, so it must be visible at grant level for the math to make sense. Grant FMV (Award Price) provides context for the original value.

**Fix:** RSU grant row columns:

```
Grant#  Grant Date  Grant FMV  Granted  Vested  Sellable  Unvested  Value  Potential  P&L
```

- Grant FMV: not currently stored in Holdings Silver. Available in BH origin (origin_fmv) or from Holdings Grant row ("Award Price" or computable from grant-level data). Needs investigation.
- Sellable: sum of sellable_qty across vested tranches.

**Note:** Supersedes UX-3 (which only asked for Sellable). This defines all fields explicitly.

**Status:** Open

---

## Issue UX-5: Unvested sellable shows "TBD" instead of "—"

**Found:** User 3 — unvested tranches show "TBD" in Sellable column. Should show "—" since unvested shares are by definition not sellable.

**Root Cause:** `format_qty(nil)` returns "TBD". For sellable column on unvested rows, nil means "not applicable", not "to be determined".

**Fix:** Use "—" for sellable on unvested rows. Either a separate formatter or check status in template.

**Status:** Open

---

## Issue UX-6: Tranche row should show all 3 quantities

**Found:** User 3 — tranche rows show Vest Qty and Sellable but not Released Qty (net after tax). Three distinct quantities exist in Holdings Silver:

| Field | Meaning | Example |
|---|---|---|
| vested_qty | Gross shares vested | 27 |
| released_qty | Net after tax withholding | 27 (or less if tax withheld in shares) |
| sellable_qty | Currently sellable (after sells) | 9 |

All 3 are stored in `stock_plan_holdings`. The tranche row should show all 3 so user can see the tax deduction and sold difference.

**Fix:** Add Released Qty column to tranche detail rows.

**Status:** Open

---

## Issue UX-11: RSU section summary missing Sellable qty

**Found:** User 3 — RSU section header shows "Vested: 22  Unvested: 36" but no Sellable count. These are tranche counts, not share quantities. User needs to see total sellable shares at section level since that drives the Current Value.

**Fix:** RSU section summary should show: "Vested: X shares (Y sellable)  Unvested: Z shares  Value: $V  Potential: $P"

**Status:** Open

---

## Issue UX-10: Potential Value card should show unvested share qty

**Found:** User 3 — Potential Value summary card shows "36 unvested tranches" but not the total unvested share count. User needs to know how many shares are scheduled to vest.

**Fix:** Show both: "{X} unvested shares across {N} tranches" or "{X} shares ({N} vests)"

**Status:** Open

---

## Issue UX-9: Vested/Unvested filters don't work either

**Found:** User 3 — toggling Vested or Unvested filter off doesn't hide rows. Same root cause as UX-8.

**Root Cause:** Same as UX-8 — filters apply at flat level but the hierarchical view always shows all origins and their tranches. The `@filtered_by_type` assign is computed from filtered data, but the origin groups retain all tranches.

**Confirmed:** Filters work in "By Status" tab (flat view uses filtered_flat directly). Only "By Type" (hierarchical) is broken.

**Fix:** Same fix as UX-8. The `build_filtered_hierarchical` function should properly filter tranches within each origin, and hide origins that have zero visible tranches after filtering.

**Status:** Open — sub-agent implementation did not fix this

---

## Issue UX-8: Profit/Loss filter doesn't filter visible data

**Found:** User 3 — clicking Profit or Loss filter changes summary values but the table data doesn't change. All grants/tranches remain visible.

**Root Cause:** Profit/Loss filter works at the flat tranche level in `apply_filters`, but `build_filtered_hierarchical` groups filtered tranches back into origins. The origin rows always show because they have at least some tranches. The filter hides individual tranches but the hierarchical view doesn't propagate this to the grant-level display.

**Expected behavior:** When "Loss" is selected:
- Only show grants that have loss-making vested tranches
- Within each grant, only show the loss-making vested tranches (on expand)
- Unvested tranches unaffected by P&L filter
- Summary reflects filtered data

**Purpose:** User wants to identify loss-making lots to pick for tax-loss harvesting (sell losses to offset gains).

**Fix:** The filtered hierarchical view must propagate P&L filtering down to visible tranches. Origins with zero matching vested tranches (after P&L filter) should be hidden.

**Status:** Open

---

## Issue UX-12: By Status view — "Grant / Date" column misleading

**Found:** User 3 — By Status tab has column header "Grant / Date". For RSU it shows grant number, for ESPP it shows enrollment date. Confusing hybrid label.

**Fix:** Column header = "Grant #". Show grant_number for RSU, blank ("—") for ESPP.

**Status:** Open

---

## Issue UX-13: By Status view — Qty field should clarify it's sellable

**Found:** User 3 — By Status view has single "Qty" column. Confirmed it shows sellable_qty (quantity field from holding row, which is sellable for vested). Label is fine as-is since sellable is the relevant quantity for portfolio context. No change needed.

**Status:** Not a bug — confirmed correct.

---

## Issue UX-14: Schedule FA — show peak price detail columns

**Found:** User 3 — FA table shows Peak Value (INR) but no breakdown. User needs to verify the calculation.

**Fix:** Add informational columns to FA preview table:
- Peak Price (USD)
- Peak Price Date
- Peak FX Rate (used for conversion)

These help user verify: Peak Value INR = Peak Price × Qty × Peak FX Rate

**Status:** Open

---

## Issue UX-15: Tax Centre currency toggle — remove or justify

**Found:** Tax Centre has USD/INR toggle. Schedule FA is INR-only (Indian tax filing). Capital Gains also reports in INR for tax purposes.

**Question:** Is USD toggle useful anywhere in Tax Centre?

**Use cases for toggle:**
- Capital Gains table: showing USD gain alongside INR gain helps user reconcile with broker G&L statement (which is in USD)
- Schedule FA: no use — always INR for ITR filing

**Recommendation:** Keep toggle only on Capital Gains tab (USD column for reference). Remove from Schedule FA tab — display INR only.

**Status:** Open — awaiting user decision

---

## Issue UX-16: No sorting on any table

**Found:** Portfolio, Schedule FA, Capital Gains — no column sorting anywhere. Portfolio had sorting implemented but doesn't seem to work. Other tables have no sorting at all.

**Fix:** 
- Every table must have sortable columns defined in requirements
- Default sort column defined per table
- Portfolio: sort by Grant Date ASC (default), sortable: Date, Granted, Value, P&L
- Schedule FA: sort by Date Acquired ASC (default), sortable: Date, Qty, Initial, Peak, Closing
- Capital Gains: sort by Sale Date DESC (default), sortable: Date, Qty, Gain/Loss
- Click column header toggles asc/desc

**Status:** Open

---

## Issue UX-17: Gain/loss color too faint

**Found:** Gain values look greyed-out green. Loss should be clearly red, gain clearly green.

**Fix:** Use stronger colors. Replace `text-success` (DaisyUI default) with explicit `text-green-600` / `text-red-600` or increase opacity.

**Status:** Open

---

## Issue UX-18: Portfolio — By Status should be default tab

**Found:** "By Type" is default. User prefers "By Status" as default and first tab.

**Fix:** 
- Swap tab order: "By Status" first, "By Type" second
- Default: By Status
- Vested section: collapsible, open on load
- Unvested section: collapsible, collapsed on load

**Status:** Open

---

## Issue UX-19: Navigation — move to left rail

**Found:** Portfolio, Tax, Sell Advisor, History are in top nav. User wants left rail navigation.

**Fix:** Replace top nav links with left sidebar rail. Keep Upload in top or as first rail item.

**Status:** Open

---

## Issue UX-20: Schedule FA column headers — remove "(INR)" suffix

**Found:** "Peak (INR)" should be "Peak Value". "Closing (INR)" should be "Closing Value". INR data should not have rupee symbol but USD has $.

**Fix:** 
- Rename: "Peak (INR)" → "Peak Value", "Closing (INR)" → "Closing Value", "Initial (INR)" → "Initial Value"
- Remove ₹ symbol from INR values in FA table (all values are INR, no need to repeat)
- Keep $ for USD values

**Status:** Open

---

## Issue UX-21: ESPP synthetic grant number shown in FA and CG

**Found:** Schedule FA and Capital Gains show system-generated ESPP hash (e.g., "4a2ca5c36b26aaf0"). Should be blank or enrollment date.

**Fix:** Same as DHF-14 — ESPP Grant# = "—" or enrollment date. Apply to FA and CG tables (not just Sell Advisor).

**Status:** Open

---

## Issue UX-22: Stock price and FX rate not refreshing

**Found:** ADBE price and USD/INR rate don't update. Seem stale from first load.

**Root Cause:** Need to verify — is StockPrice.current_price called on mount only? Is the ETS cache stale? Is the Yahoo API call failing?

**Fix:** Investigate. Ensure current_price and current_fx are fetched on page mount (not cached across sessions).

**Status:** Open — needs investigation

---

## Issue UX-23: Capital Gains — missing benefit type column

**Found:** User 4 — CG table has RSU and ESPP rows but no plan type column. User can't distinguish.

**Fix:** Add "Type" column showing RSU/ESPP badge (same as Schedule FA).

**Status:** Open

---

## Issue UX-24: Capital Gains — group by sale date

**Found:** User 4 — Oct 22 has 33 rows. Hard to scan. Should group rows by sale date with a header.

**Fix:** Group rows by sale_date. Show date as section header, not repeated in each row.

**Status:** Open

---

## Issue UX-25: Capital Gains — blank INR for ESPP rows without sale price

**Found:** User 4 — some ESPP sells have nil sale_price (G&L didn't provide it). Shows `₹—` for sale price INR and gain/loss.

**Root Cause:** BH creates the sale, G&L should enrich with price. Some ESPP G&L rows may not have matched.

**Fix:** Show "N/A" with tooltip "Sale price unavailable — upload G&L for this year" instead of blank ₹—.

**Status:** Open

---

## Future Issues

(Add new UX-N entries as issues are found during testing)
