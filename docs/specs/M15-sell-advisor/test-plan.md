# Test Plan: M15 — Sell Advisor

---

## TP-1: Lot Enrichment (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Lot held > 24 months | gain_type = :LTCG |
| TP-1.2 | Lot held ≤ 24 months | gain_type = :STCG |
| TP-1.3 | Gain lot | gain_per_share_inr > 0 |
| TP-1.4 | Loss lot | gain_per_share_inr < 0 |
| TP-1.5 | Nil cost_basis lot | Excluded, warning returned |

## TP-2: Tax Evaluator — Offset Cascade (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | STCG only, no baseline | tax = gain × 31.2% |
| TP-2.2 | LTCG only, no baseline | tax = gain × 13% |
| TP-2.3 | STCL offsets STCG | net_ST reduced, tax lower |
| TP-2.4 | STCL exceeds STCG → cross-offsets LTCG | adj_net_LT reduced |
| TP-2.5 | LTCL offsets LTCG only | net_LT reduced, net_ST unchanged |
| TP-2.6 | LTCL does NOT offset STCG | STCG tax unchanged |
| TP-2.7 | All losses, no gains | tax = 0 |
| TP-2.8 | Baseline STCG + basket STCL | Existing STCG offset by basket loss |
| TP-2.9 | Baseline LTCG + basket LTCL | Existing LTCG offset |
| TP-2.10 | Mixed: STCL + LTCG + baseline STCG | Full cascade: STCL→STCG, leftover STCL→LTCG |

## TP-3: Basket 1 — Exact Target (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | Shares mode: 10 shares | Exactly 10 shares in basket |
| TP-3.2 | Partial lot at end | Last lot qty < lot.sellable_qty |
| TP-3.3 | LTCL used before STCL | When both available, LTCL lots selected first |
| TP-3.4 | STCL preserved for future | STCL lot not selected when LTCL suffices |
| TP-3.5 | LTCG before STCG | Lower tax rate lots preferred for gains |
| TP-3.6 | Existing STCG + basket has STCL | STCL lot gets priority (offsets existing gain) |
| TP-3.7 | USD mode: target $2500 | Proceeds ≥ $2500 |
| TP-3.8 | INR mode: target ₹200000 | Proceeds ≥ ₹200000 |

## TP-4: Basket 2 — Cost Optimized (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | Prefers whole lots | No partial lots in basket |
| TP-4.2 | May exceed target qty | total_shares ≥ target (or close) |
| TP-4.3 | Fewer orders preferred | If tax equal, fewer lots selected |
| TP-4.4 | ESPP + RSU = 2 orders | Charges reflect 2 orders |
| TP-4.5 | All RSU lots | Charges reflect 1 order |
| TP-4.6 | Cost = tax + charges | Ranked by total cost / proceeds |
| TP-4.7 | USD mode: proceeds ≥ target | Constraint enforced |

## TP-5: Offset Value Preservation (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | LTCL + LTCG available | LTCL used to offset LTCG (same bucket) |
| TP-5.2 | STCL + LTCG, LTCL also available | LTCL used first, STCL preserved |
| TP-5.3 | Only STCL, LTCG gain | STCL used (no LTCL alternative) |
| TP-5.4 | No gains, all losses | Loss lots with lowest future value first |

## TP-6: Deduplication (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Baskets identical | Only 1 basket returned |
| TP-6.2 | Baskets differ | 2 baskets returned |

## TP-7: Edge Cases (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | Target > total sellable | fills_target = false, shortfall reported |
| TP-7.2 | Target = total sellable | All lots selected |
| TP-7.3 | No sellable lots | Error returned |
| TP-7.4 | No Holdings data | Error returned |
| TP-7.5 | All same gain type | Baskets may be identical, deduped |
| TP-7.6 | All loss lots | Tax = 0, optimize for charges |
| TP-7.7 | Single lot covers target | Both baskets same |
| TP-7.8 | Zero target | Error returned |
| TP-7.9 | Negative target | Error returned |

## TP-8: Transaction Charges (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.1 | RSU only | 1 order charge |
| TP-8.2 | ESPP only | 1 order charge |
| TP-8.3 | RSU + ESPP | 2 order charges |
| TP-8.4 | Wire fee included | $25 per basket |

## TP-9: LiveView (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-9.1 | GET /sell | Page loads with input form |
| TP-9.2 | Shares mode: 10 | 2 baskets appear |
| TP-9.3 | USD mode: $2500 | Baskets show, proceeds ≥ $2500 |
| TP-9.4 | INR mode: ₹200000 | Baskets show, proceeds ≥ ₹200000 |
| TP-9.5 | Expand basket | Lot detail visible |
| TP-9.6 | Basket 2 has extra shares | "+X shares" note visible |
| TP-9.7 | FY context displayed | Existing STCG/LTCG shown |
| TP-9.8 | Target > available | Shortfall warning |
| TP-9.9 | Invalid input | Error message |
| TP-9.10 | Disclaimer visible | "Estimates only" text |
| TP-9.11 | CSV download | File downloads with correct content |

## TP-10: Worked Example Verification (Manual)

Using the example from Algorithm Design §7:

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-10.1 | 5 lots, target 20 shares | Basket 1 picks D(12) + A(8) — STCL first (offsets existing STCG) |
| TP-10.2 | Same setup | Basket 2 may pick different combo (whole lots, fewer orders) |
| TP-10.3 | Verify offset preservation | LTCL used to offset LTCG, STCL preserved when possible |

---

## Test Approach

- TP-1 through TP-8: Automated (DataCase)
- TP-9, TP-10: Manual browser testing with User 3 data
- Offset cascade tests are critical — must cover all combinations

## Test Count: ~50 (35 automated, ~15 manual)
