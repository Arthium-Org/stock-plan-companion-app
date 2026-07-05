# Tasks: M15 — Sell Advisor

## Prerequisites

- M5b: Holdings Silver (sellable lots)
- M14: Capital Gains context (FY baseline)
- M7a/M7b: FX + Stock prices
- Algorithm design reviewed and approved

---

## Milestone 1: Sell Advisor Context — Core

**File:** `lib/stock_plan/tax/sell_advisor.ex`

- [ ] 1.1 Create `StockPlan.Tax.SellAdvisor` module
- [ ] 1.2 Load sellable lots from Holdings Silver (sellable_qty > 0)
- [ ] 1.3 Filter out lots with nil cost_basis (warn)
- [ ] 1.4 Enrich lots: gain_type (STCG/LTCG via Date.shift year:2), gain_per_share_inr, tax_cost
- [ ] 1.5 Target resolution: {:shares, n} | {:usd, amount} | {:inr, amount}
- [ ] 1.6 Load FY baseline from CapitalGains.build
- [ ] 1.7 Tax rates: STCG 31.2%, LTCG 13%

## Milestone 2: Tax Evaluator (Offset Cascade)

- [ ] 2.1 Implement offset cascade: STCL → STCG, leftover STCL → LTCG, LTCL → LTCG
- [ ] 2.2 Combine basket gains/losses with FY baseline
- [ ] 2.3 Compute: net_ST, leftover_ST_loss, adj_net_LT, st_tax, lt_tax, total_tax
- [ ] 2.4 Write tests: offset cascade with various gain/loss combinations
- [ ] 2.5 `mix test` — pass

## Milestone 3: Basket 1 — Exact Target

- [ ] 3.1 Sort lots by tax efficiency with offset value preservation:
  - LTCL offsetting existing LTCG (same bucket, preserve STCL)
  - STCL offsetting existing STCG (same bucket)
  - LTCL general (low future value, use first)
  - STCL general (high future value, preserve)
  - LTCG gains (lower tax: 13%)
  - STCG gains (higher tax: 31.2%)
- [ ] 3.2 Fill exactly to target (partial lot at end for shares mode)
- [ ] 3.3 USD/INR mode: fill to closest value ≥ target
- [ ] 3.4 Run TaxEvaluator on assembled basket
- [ ] 3.5 Compute transaction charges (ESPP/RSU separate orders)
- [ ] 3.6 Write tests
- [ ] 3.7 `mix test` — pass

## Milestone 4: Basket 2 — Cost Optimized

- [ ] 4.1 Enumerate whole-lot combinations near target quantity
- [ ] 4.2 For small lot count (≤ 15): enumerate combos within ±30% of target
- [ ] 4.3 For larger: greedy with whole-lot rounding
- [ ] 4.4 Per combo: compute total_cost = TaxEvaluator.tax + transaction_charges
- [ ] 4.5 Rank by cost_efficiency = total_cost / proceeds
- [ ] 4.6 Pick best combo
- [ ] 4.7 USD/INR constraint: proceeds ≥ target
- [ ] 4.8 Write tests
- [ ] 4.9 `mix test` — pass

## Milestone 5: Deduplication + Output

- [ ] 5.1 Compare basket entries — if identical, show only Basket 1
- [ ] 5.2 Basket summary: total shares, proceeds, tax, charges, net, STCG/LTCG breakdown
- [ ] 5.3 If Basket 2 sells more: "+X shares to avoid partial lot" note
- [ ] 5.4 Write tests
- [ ] 5.5 `mix test` — pass

## Milestone 6: LiveView

**File:** `lib/stock_plan_web/live/sell_advisor_live.ex`

- [ ] 6.1 Rewrite SellAdvisorLive to match new 2-basket design
- [ ] 6.2 Route: `/sell`, nav link
- [ ] 6.3 Input: radio (Shares/USD/INR) + numeric + Advise button
- [ ] 6.4 Current price + FX display
- [ ] 6.5 FY context display
- [ ] 6.6 2 basket cards with summaries + expand/collapse lot detail
- [ ] 6.7 Order count + charges per basket
- [ ] 6.8 CSV download per basket
- [ ] 6.9 Disclaimer footer
- [ ] 6.10 Input validation

## Milestone 7: Verification

- [ ] 7.1 `mix format --check-formatted`
- [ ] 7.2 `mix compile --warnings-as-errors`
- [ ] 7.3 `mix test` — all pass
- [ ] 7.4 Manual: User 3 — sell 10 shares, verify 2 baskets differ
- [ ] 7.5 Manual: sell by USD amount (≥ target)
- [ ] 7.6 Manual: sell by INR amount
- [ ] 7.7 Manual: target > available → shortfall warning
- [ ] 7.8 Manual: all loss lots → tax = 0, baskets optimize for charges
- [ ] 7.9 Manual: verify offset preservation (LTCL used before STCL)
- [ ] 7.10 Manual: CSV download

---

## Definition of Done

- [ ] 2 baskets: Exact Target + Cost Optimized
- [ ] Tax offset cascade correctly implemented
- [ ] STCL preserved over LTCL when possible
- [ ] Transaction costs factored (ESPP/RSU separate orders)
- [ ] Partial lot in Basket 1, whole lots in Basket 2
- [ ] USD/INR mode: proceeds ≥ target
- [ ] Dedup when baskets identical
- [ ] FY context integrated
- [ ] All tests pass
