# Requirements: M10 Portfolio — UX Fixes (Round 2)

## Introduction

11 UX issues found during multi-user testing. Grouped into 5 categories for implementation.

---

## Category A: Tranche Sub-Table Visual Separation (UX-1)

1. Expanded tranche rows SHALL be rendered inside a `<td colspan>` as a nested sub-table
2. Tranche sub-table SHALL have its own column headers, visually distinct from the grant table
3. Tranche rows SHALL have a different background color (indented, lighter/darker tint)
4. Clear visual boundary (border, padding) between grant row and its tranche detail

## Category B: Grant & Section Level Data Completeness (UX-4, UX-7, UX-11)

### RSU Grant Row Columns
5. RSU grant row SHALL show: Grant#, Grant Date, Granted, Vested, Sellable, Unvested, Current Value, Potential, P&L
6. Sellable = sum of sellable_qty across vested tranches for that grant
7. Grant FMV: not available in Holdings data. Dropped from grant row.

### RSU Section Summary
8. RSU section summary SHALL show share quantities, not just tranche counts: "Vested: X shares (Y sellable) | Unvested: Z shares"

### ESPP Lock-In Price
9. ESPP enrollment row SHALL display Lock-In Price (Grant Date FMV)
10. Strip `$` prefix from `grant_date_fmv` in metadata during Holdings Silver build

### RSU Tranche Row Columns
11. Tranche detail SHALL show 3 quantity columns: Vest Qty, Released Qty, Sellable
12. Unvested tranches: Sellable column shows "—" (not "TBD")

## Category C: Summary Cards (UX-10)

13. Potential Value card SHALL show unvested share count alongside tranche count
14. Format: "X shares (N vests)" or "X unvested shares across N tranches"

## Category D: Filters (UX-8, UX-9)

15. Vested/Unvested filters SHALL hide/show rows in the hierarchical view
16. Profit/Loss filters SHALL hide/show vested tranches and their parent grants
17. Origins with zero visible tranches after filtering SHALL be hidden
18. When all tranches in a section are filtered out, show "No matching holdings"
19. Filters apply to data, not just summary — what you see = what's summarized

## Category E: Sorting (UX-2)

20. Grant/enrollment rows SHALL be sortable by clicking column headers
21. Sortable columns at grant level: Grant Date, Granted Qty, Current Value, P&L
22. Default sort: Grant Date ascending
23. Tranche rows within a grant stay chronological (not sortable independently)
24. Sort indicator (arrow) on active column
