# Data Handling Fixes

Living spec — tracks data issues found during multi-user testing. Updated as issues are found and fixed.

---

## Issue DHF-7: G&L sale matching architecture (REDESIGN)

**Found:** User 3 — Sep 23 sale. G&L has 3 rows (4+2+2 shares across 2 tranches, same order). BH has 2 sell events (4+4 shares, origin-level).

**Root Cause:** Phase 2 tries to merge BH sales with G&L data by matching origin+date. This is fundamentally wrong:

1. BH sales are origin-level (no tranche info, just "grant X sold Y shares on date Z")
2. G&L rows are tranche-level (specific vest lot, specific qty, specific price)
3. When multiple BH sells exist on same date, matching is arbitrary
4. If 2 BH sells have different prices (different orders), can't aggregate
5. Trying to update BH sale with G&L tranche_id doesn't work

**Correct Architecture:**

BH sales and G&L allocations are two different views of the same events at different granularity:

| Source | Granularity | Purpose |
|---|---|---|
| BH Sales | Origin-level (grant + date + qty) | Portfolio BH fallback (origin-level sold totals) |
| G&L Sales | Tranche-level (vest lot + qty + price) | Capital Gains (Tax Centre) |

**They should NOT be merged into one record.**

**Proposed Fix:**

1. **BH Phase 1:** Creates sales as now (origin-level, from sell events). These have: origin_id, sale_date, total_quantity. May NOT have sale_price.

2. **G&L Phase 2:** Creates its OWN sale records with allocations. Does NOT try to match/update BH sales. Each G&L row creates:
   - A sale (or matches to existing G&L sale by order_number)
   - An allocation linking sale → tranche

3. **Distinguish sale source:** Add `source` field to sales: `"BH"` or `"GL"`. Or use separate queries based on whether allocations exist.

4. **Capital Gains:** Reads from G&L-sourced sales (those with allocations + price)

5. **Portfolio BH fallback:** Reads from BH-sourced sales (origin-level totals for sold calculation)

6. **G&L enrichment of BH tranches:** Still happens (vest_fmv fill). Only the sale matching changes.

**Impact:**
- `find_or_create_gl_sale` → renamed to `create_gl_sale` (no matching)
- G&L sales grouped by order_number (same order = same sale)
- BH sales untouched by Phase 2
- `reconcile_sale_quantities` and `remove_orphan_bh_sales` → removed (no longer needed)
- Capital Gains query: filter to sales with allocations (G&L-sourced)
- Portfolio BH fallback: sum BH sales for origin-level sold

**Status:** Specced — needs implementation

---

## Issue DHF-16: Schedule FA shows sold lots for users without G&L

**Found:** User 1 — quit Adobe, sold all shares. No Holdings. Schedule FA for 2024 shows all old tranches as "held" because it only checks sale_allocations (G&L). Without G&L, it has no tranche-level sell data.

**Root Cause:** `ScheduleFA.build` computes `held_qty = net_quantity - sum(sale_allocations)`. Without G&L, sale_allocations is empty, so held_qty = full net_quantity for every tranche.

**Fix:** Same approach as Portfolio BH fallback (DHF-1): use origin-level sold totals from BH sales.

```
For each origin on the FA date:
  origin_sold = SUM(sales.total_quantity WHERE origin_id AND sale_date <= CY end)
  origin_vested = SUM(tranches.net_quantity WHERE status = VESTED AND vest_date <= CY end)
  
  If origin_sold >= origin_vested → entire grant sold, skip all tranches
  If origin_sold > 0 but < vested → partially sold (show reduced qty)
```

This is the BH-level approximation — not tranche-level accurate, but prevents showing fully-sold grants.

**Status:** Open

---

## Issue DHF-1: Portfolio shows sold grants as available (User 1)

**Found:** User 1 — all shares sold, no Holdings XLSX. Portfolio shows RSU grants as current holdings.

**Root Cause:** Portfolio.build BH fallback checks tranche-level sale_allocations. Without G&L, RSU allocations don't exist.

**Fix:** BH fallback uses origin-level sold from BH sales (sum total_quantity per origin).

**Status:** Fixed in Portfolio.build (build_from_bh path)

---

## Issue DHF-2: Holdings uploaded but not used as Portfolio source (User 2)

**Found:** User 2 — Holdings uploaded but 0 tranches enriched. Portfolio shows BH-derived data.

**Root Cause:** Phase 5 enrichment model (now replaced by M5b Holdings Silver).

**Status:** Fixed by M5b (Holdings Silver as separate table)

---

## Issue DHF-3: ESPP quantities doubled (User 3)

**Found:** ESPP sellable_qty = Sellable Qty + Blocked Qty was double-counting.

**Fix:** ESPP: sellable_qty = Sellable Qty only (Blocked is a subset, not additive).

**Status:** Fixed

---

## Issue DHF-4: Schedule FA — closing value zero

**Fixed:** Was showing current CY (incomplete). Now only shows completed CYs.

**Status:** Fixed

---

## Issue DHF-5: Schedule FA — sale proceeds zero

**Fixed:** Pro-rata fallback when sale_price nil.

**Status:** Fixed

---

## Issue DHF-6: Schedule FA — future lots in current CY

**Fixed:** Only completed CYs shown.

**Status:** Fixed

---

## Issue DHF-8: Schedule FA should not show current CY

**Status:** Fixed

---

## Issue DHF-9: Remove Load button from Tax Centre

**Status:** Fixed

---

## Issue DHF-10: Sell Advisor — tax includes baseline instead of marginal

**Found:** Shows total FY tax instead of marginal tax impact from this sale.

**Fix:** Show: existing FY tax, FY tax after sale, tax saved/added.

**Status:** Open

---

## Issue DHF-11: Sell Advisor — STCL not picked to offset existing STCG

**Status:** Fixed (Decimal comparison bug — Erlang struct ordering ≠ numeric)

---

## Issue DHF-12: Sell Advisor — picks both ESPP + RSU unnecessarily

**Status:** Fixed in V2 (plan_penalty tiebreaker)

---

## Issue DHF-13: Sell Advisor — STCG/LTCG used for loss lots

**Status:** Fixed (4-way classification: STCG/STCL/LTCG/LTCL)

---

## Issue DHF-14: Sell Advisor — ESPP shows hash, RSU missing vest number

**Status:** Open

---

## Issue DHF-15: Sell Advisor — charges in USD, proceeds in INR

**Status:** Open

---

## Tracked Assumptions (Unverified)

All sample data has company blackout (full block). These assumptions need verification with open trading window data:

| # | Assumption | Risk if wrong |
|---|---|---|
| A-1 | RSU partial block: Sellable + Blocked = total (additive) | Wrong sellable_qty if overlapping |
| A-2 | ESPP partial block: Sellable stays total, Blocked < Sellable | Wrong sellable_qty if Sellable drops |
| A-3 | ESPP unblocked: Sellable = total, Blocked = 0 | Minor — would still work |

---

## Testing Matrix

| User | BH | G&L | Holdings | Portfolio | Tax Centre | Status |
|---|---|---|---|---|---|---|
| User 1 | Yes | 2023-2025 | No | BH fallback (all sold = empty) | CG works | Tested |
| User 2 | Yes | 2025-2026 | Yes (RSU) | Holdings Silver | Not tested | Partial |
| User 3 | Yes | 2025-2026 | Yes (ESPP+RSU) | Holdings Silver | CG + FA works | Tested |
| User 4 | TBD | TBD | TBD | TBD | TBD | Not tested |
