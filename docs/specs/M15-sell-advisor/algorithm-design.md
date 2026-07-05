# Sell Advisor — Algorithm Design (v2)

**Status:** Draft — review before implementation
**Reference:** Tax harvest MCKP algorithm in `wealth-management-direct-equity/docs/new-app/tax-harvest/algorithm-design.md`

---

## 1. Problem Reframing

**Goal:** Minimize total FY tax liability (existing baseline + this sale).

**User input is a CONSTRAINT, not the goal:**
1. Sell exactly X shares
2. Sell ≥ $Y worth
3. Sell ≥ ₹Z worth
4. No constraint — pure tax loss harvest

The algorithm optimizes for minimum tax, subject to the user's constraint.

---

## 2. Key Differences from Indian Equity Tax Harvest

| Aspect | Equity Tax Harvest | Stock Plan Sell Advisor |
|---|---|---|
| Companies | Multiple | Single (ADBE) |
| FIFO constraint | Yes | No — specific lot selection allowed |
| Transaction costs | Brokerage, STT, DP | Wire fee + brokerage, ESPP/RSU separate orders |
| Re-buy | Yes (harvest) | No (actual exit) |
| LTCG exemption | ₹1.25L — optimize to fill | Not applicable (user is selling, not harvesting) |
| Goal | Reduce tax / book gains within exemption | Minimize total FY tax |
| User input | Mode selection (loss/gain/full) | Constraint: qty, amount, or none |

### What IS reused
- 2-stage approach (offset gains → fill constraint)
- Tax offset cascade (STCL → STCG+LTCG, LTCL → LTCG)
- Cost justification (tax saved > charges)
- TaxEvaluator logic

---

## 3. Tax Offset Cascade

Indian tax offset rules (mandatory sequence):

```
Step 1: Net ST position
  net_ST = (baseline_st_gain + basket_st_gain) - (baseline_st_loss + basket_st_loss)
  leftover_ST_loss = max(0, -net_ST)

Step 2: Cross-offset STCL → LTCG
  net_LT = (baseline_lt_gain + basket_lt_gain) - (baseline_lt_loss + basket_lt_loss)
  adj_net_LT = net_LT - leftover_ST_loss

Step 3: Compute tax
  st_tax = max(0, net_ST) × 0.312    # 30% + 4% cess
  lt_tax = max(0, adj_net_LT) × 0.13  # 12.5% + 4% cess
  total_tax = st_tax + lt_tax
```

### Offset value hierarchy
- **STCL** can offset STCG (saves 31.2%) AND LTCG (saves 13%) — high value
- **LTCL** can offset LTCG only (saves 13%) — lower value

---

## 4. Two-Stage Algorithm

### Stage 1: Offset Existing FY Gains (Tax Loss Harvesting)

**Goal:** Reduce existing FY tax liability to zero (or as low as possible).

```
Input: FY baseline (realized_st_gain, realized_st_loss, realized_lt_gain, realized_lt_loss)
       sellable_lots (enriched with gain_type, gain_per_share_inr)

Step 1a: Offset baseline STCG with STCL lots
  IF baseline net_ST > 0 (taxable STCG exists):
    target_st_offset = baseline_st_gain - baseline_st_loss
    Pick STCL lots sorted by:
      Primary: cost justification (tax_saved > charges_for_this_lot)
      Secondary: smallest |loss_per_share| first (preserve bigger losses for future)
    Until: accumulated STCL >= target_st_offset OR no more cost-justified STCL lots

Step 1b: Offset baseline LTCG with LTCL lots (+ STCL cross-offset)
  Compute remaining STCL from Step 1a (excess STCL cross-offsets LTCG)
  IF baseline taxable LTCG > remaining STCL cross-offset:
    remaining_lt_target = baseline_lt_gain - baseline_lt_loss - leftover_stcl
    Pick LTCL lots sorted by:
      Primary: cost justification
      Secondary: smallest |loss_per_share| first
    Until: accumulated LTCL >= remaining_lt_target OR no more cost-justified LTCL lots

Output: Set of lots committed for tax offset + remaining uncommitted lots
```

**Cost justification per lot:**
```
tax_saved = evaluate_tax(current_basket, baseline) - evaluate_tax(current_basket + lot, baseline)
charges_for_lot = marginal charge (wire fee amortized, brokerage if new plan type order)
cost_justified = tax_saved > charges_for_lot
```

### Stage 2: Fill Remaining Constraint

**Goal:** Fill user's constraint with remaining lots, minimizing additional tax.

```
IF constraint = :none (pure harvest):
  Stage 2 does nothing. Return Stage 1 result only.

IF constraint is shares/USD/INR:
  remaining_target = constraint - shares_already_committed_in_stage1
  
  IF remaining_target <= 0:
    Stage 1 already meets constraint. Done.
  
  ELSE:
    Fill from uncommitted lots using incremental marginal evaluation:
      For each remaining lot:
        Compute marginal_tax_per_share via TaxEvaluator
        (includes offset cascade with Stage 1 lots already in basket)
      Pick lot with lowest marginal_tax_per_share
      
      Sort key: {marginal_tax_per_share_float, is_gain, future_cost_float}
      (Use floats for comparison — Decimal struct ordering is NOT numeric)
    
    Until: constraint met OR no more lots
```

---

## 5. Four Modes

### Mode 1: Sell X Shares
```
Stage 1: Offset gains (commits some lots, may partially fill target)
Stage 2: Fill remaining to exactly X shares (partial lot OK at end)
```

### Mode 2: Sell ≥ $Y / ≥ ₹Z
```
Stage 1: Offset gains
Stage 2: Fill remaining to meet proceeds ≥ target, minimize overshoot
```

### Mode 3: Pure Tax Loss Harvest (no user constraint)
```
Stage 1 only: Pick minimum lots to offset existing FY gains
  Each lot must be cost-justified (tax_saved > charges)
Stage 2: Not applicable
Output: "Sell these X lots to save ₹Y in tax this FY"
```

### Mode 4: Tax Loss Harvest + Sell X Shares
```
Stage 1: Offset gains
Stage 2: Fill remaining shares from uncommitted lots
Combined: "Sell these lots — saves ₹Y in tax AND meets your sell target"
```

---

## 6. Transaction Charges

```
Wire transfer: $25 per outgoing transfer (fixed, once per sell event)
Brokerage: TBD per order
ESPP and RSU: separate orders (E*Trade constraint)

Charge model:
  1 plan type (all RSU or all ESPP): $25 wire + 1× brokerage
  2 plan types (RSU + ESPP): $25 wire + 2× brokerage

Cost justification:
  First lot of a plan type: bears the full order setup cost (wire amortization + brokerage)
  Subsequent lots of same plan type: zero marginal charge
  First lot of SECOND plan type: bears brokerage for new order
```

### Impact on Stage 1
A lot is cost-justified for tax offset only if:
```
tax_saved_by_this_lot > marginal_charges_for_this_lot
```

If all remaining STCL lots are in ESPP and we already committed RSU lots, adding an ESPP lot incurs a new order charge. The lot must save more tax than that charge.

### Impact on Stage 2
When filling constraint with equal-tax lots, prefer lots of already-committed plan type (avoids new order charge).

---

## 7. Two Baskets

### Basket 1: Exact (2-stage, partial lots OK)
```
Stage 1: offset existing gains
Stage 2: fill exactly to constraint
Partial lot at end: YES
Net = proceeds - tax - charges
```

### Basket 2: Cost Optimized (2-stage, whole lots)
```
Stage 1: offset existing gains (whole lots)
Stage 2: fill to constraint using whole lots only
  May overshoot constraint (avoids partial lot)
  Prefers fewer orders (same plan type)
Net = proceeds - tax - charges
Show "+X shares to avoid partial lot" if overshoots
```

### Pure Harvest Mode
Single basket only:
```
Stage 1 output: minimum lots to offset gains, cost-justified
No Stage 2
Summary: "Sell X lots to save ₹Y this FY. Charges: ₹Z"
```

### Deduplication
If Basket 1 and Basket 2 have identical lot selections → show only Basket 1.

---

## 8. Display: Marginal Tax Impact

**Critical UX fix:** Show marginal tax impact, not total FY tax.

```
tax_before_sale = evaluate_tax([], baseline)           # existing FY tax
tax_after_sale = evaluate_tax(basket_entries, baseline) # FY tax after this sale
marginal_impact = tax_after_sale - tax_before_sale      # negative = tax saving

Display:
  "This sale saves ₹2,159 in FY tax" (if marginal < 0)
  "This sale adds ₹0 in FY tax" (if marginal = 0)
  "This sale adds ₹1,500 in FY tax" (if marginal > 0)
  
  Existing FY tax: ₹2,349
  FY tax after sale: ₹190
  Tax saved: ₹2,159
```

---

## 9. Classification Terminology

Use 4-way classification throughout code and display:

| Holding Period | Direction | Code | Display |
|---|---|---|---|
| ≤ 24 months | Gain | :STCG | Short Term Gain |
| ≤ 24 months | Loss | :STCL | Short Term Loss |
| > 24 months | Gain | :LTCG | Long Term Gain |
| > 24 months | Loss | :LTCL | Long Term Loss |

**Never use :STCG or :LTCG for loss lots.** The gain/loss direction is part of the classification.

```elixir
defp classify(vest_date, gain_per_share_inr, today) do
  long_term = Date.compare(today, Date.shift(vest_date, year: 2)) == :gt
  loss = Decimal.negative?(gain_per_share_inr)
  
  case {long_term, loss} do
    {true, true}   -> :LTCL
    {true, false}  -> :LTCG
    {false, true}  -> :STCL
    {false, false}  -> :STCG
  end
end
```

---

## 10. Future Offset Value Preservation

Within each stage, when multiple lots have equal marginal tax impact:

**Loss lots:** smallest |loss_per_share| first — preserve bigger losses for future FYs.
**Gain lots:** smallest gain_per_share first — least tax.
**Plan type preference:** prefer lots of already-committed plan type — fewer orders.

---

## 11. Edge Cases

### 11.1 All lots are loss-making
Stage 1 offsets whatever baseline gains exist. Stage 2 fills with losses (zero additional tax). Optimize for charges only (single plan type preferred).

### 11.2 No existing FY gains
Stage 1 does nothing (nothing to offset). Stage 2 fills constraint starting with lowest-tax lots.

### 11.3 Target exceeds total sellable
Fill all lots. Report shortfall. Stage 1 still runs (offset gains regardless).

### 11.4 Stage 1 already meets constraint
Skip Stage 2. The tax offset lots happen to also fill the sell target.

### 11.5 Pure harvest: no cost-justified lots
All lots' tax savings < their charges. Return empty basket with explanation: "No cost-justified tax loss harvesting available."

### 11.6 ESPP + RSU mix
Two orders = higher charges. Stage 1 may skip a low-value lot from the second plan type if charges exceed tax savings.

### 11.7 Zero or nil cost_basis
Exclude from baskets. Show warning.

### 11.8 Decimal comparison
**CRITICAL:** Erlang term ordering does NOT compare Decimal structs numerically. All Enum.min_by/sort_by on Decimals MUST convert to float first: `Decimal.to_float(d)`.

---

## 12. Worked Example

### Setup
```
Current price: $250, Current FX: ₹85

FY Baseline: STCG ₹7,530, LTCG ₹0

Sellable lots:
  A: ESPP vest 2022-12-30, qty 15, cost $337, LTCL (loss -₹55K)
  B: RSU  vest 2023-02-15, qty 5,  cost $376, LTCL (loss -₹34K)
  C: RSU  vest 2025-10-15, qty 2,  cost $333, STCL (loss -₹11K)
  D: RSU  vest 2024-08-15, qty 5,  cost $550, STCL (loss -₹29K)
  E: RSU  vest 2025-04-15, qty 4,  cost $351, STCL (loss -₹12K)

User constraint: sell 20 shares
```

### Stage 1: Offset Existing STCG (₹7,530)

Pick STCL lots to offset ₹7,530:
- Lot C: 2 shares, STCL ₹11K per share × 2 = ₹22K offset. Tax saved: ₹7,530 × 31.2% = ₹2,349. Charges: $25 wire + brokerage (RSU order). Cost justified? ₹2,349 > ~₹2,125 ($25 × 85) → YES.
- ₹7,530 fully offset with just lot C (2 shares). STCG tax → ₹0.
- Excess STCL: ₹22K - ₹7,530 = ₹14,470 → cross-offsets LTCG (none exists, carries as loss).

No baseline LTCG → Stage 1b skipped.

**Stage 1 committed:** Lot C (2 shares). Tax saved: ₹2,349. Remaining target: 18 shares.

### Stage 2: Fill Remaining 18 Shares

Uncommitted lots: A (15), B (5), D (5), E (4)
All are losses → marginal tax = 0 for all.
Tiebreak: prefer RSU (already committed, no new order charge) → D, E, B first.
Then ESPP if needed (new order charge).

Fill:
- D: 5 shares (RSU, same order as C) → 13 remaining
- E: 4 shares (RSU) → 9 remaining
- B: 5 shares (RSU) → 4 remaining
- A: 4 partial (ESPP, new order) → 0 remaining

**Basket 1 result:**
```
Lots: C(2) + D(5) + E(4) + B(5) + A(4 partial) = 20 shares
Tax impact: saves ₹2,349 (STCG eliminated)
Orders: 2 (RSU + ESPP partial)
Charges: $25 wire + 2× brokerage
```

### Basket 2: Cost Optimized (whole lots)

Same Stage 1: Lot C (2 shares).
Stage 2 (whole lots only): D(5) + E(4) + B(5) = 16. Total = 18.
Need 2 more → A is 15 (whole lot = overshoot to 33).
Or skip A → shortfall of 2.

Better: accept 18 shares (shortfall 2) to avoid ESPP order charge.

**Basket 2 result:**
```
Lots: C(2) + D(5) + E(4) + B(5) = 16 shares (shortfall 4)
OR: C(2) + D(5) + E(4) + B(5) + A(15) = 31 shares (overshoot 11)
Pick based on cost/proceeds ratio.
```

---

## 13. Implementation Notes

- **Decimal comparison:** ALL `Enum.min_by`/`sort_by` on Decimals MUST use `Decimal.to_float()`. Erlang struct ordering ≠ numeric ordering. This was a confirmed production bug.
- **TaxEvaluator is authoritative.** Heuristic scores are for documentation only.
- **Both baskets include charges in summary.** Net = proceeds - marginal_tax_impact - charges.
- **Show marginal tax impact**, not total FY tax.
- **4-way classification:** :STCG, :STCL, :LTCG, :LTCL. Never use :STCG for a loss lot.
- **Stage 1 uses cost justification.** Stage 2 uses incremental marginal evaluation.
- **Plan type preference:** prefer same plan type to minimize orders.
- Phase 1: flat tax rates (STCG 31.2%, LTCG 13%). Phase 2: slab-based.
