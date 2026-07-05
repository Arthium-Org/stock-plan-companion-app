# Requirements: M15 — Sell Advisor

## Introduction

Sell Advisor helps users decide which lots to sell to minimize tax + transaction cost. User provides a sell target (shares, USD, or INR), and the system generates 2 recommended baskets with different optimization strategies.

**Data sources:** Holdings Silver (sellable lots) + Capital Gains context (FY baseline) + current stock price + FX rate

---

## Requirement 1: Sell Target Input

1. User SHALL provide sell target in ONE of three modes:
   - **Shares:** "I want to sell X shares"
   - **USD:** "I want to receive ~$Y"
   - **INR:** "I want to receive ~₹Z"
2. For shares mode: fill exactly X shares (partial lot allowed)
3. For USD/INR mode: fill closest value **at or above** the target (user needs at least that amount)
4. Scope: all sellable holdings across all grants

## Requirement 2: Sellable Lots

1. Only lots with `sellable_qty > 0` from Holdings Silver are eligible
2. Lots with nil cost_basis: excluded from baskets (cannot compute gain). Show warning.
3. Per lot, system computes:
   - Gain type: STCG (≤ 24 months) or LTCG (> 24 months)
   - Gain per share in INR: (current_price × current_fx) - (cost_basis × vest_fx_rate)
   - Tax cost per share based on gain type and applicable rate

## Requirement 3: FY Context

1. System SHALL load existing realized gains/losses in the current FY
2. Source: Capital Gains context (realized STCG, STCL, LTCG, LTCL for current FY)
3. FY context affects lot selection priority (see Algorithm Design)

## Requirement 4: Transaction Costs

1. E*Trade does NOT allow ESPP and RSU to be mixed in a single sell order
2. Each plan type = separate order = separate charges
3. Transaction costs per sell:
   - Wire transfer fee: $25 per outgoing transfer
   - Brokerage: TBD (per order)
   - Other charges: TBD
4. Fewer lots in same plan type = same order count. But ESPP + RSU = always 2+ orders.

## Requirement 5: Two Baskets

### Basket 1: Exact Target
1. Fills the user's exact share count (partial lot at the end if needed)
2. For USD/INR: fills to closest value at or above target
3. Optimized for minimum tax using offset cascade
4. Preserves future offset value (use LTCL before STCL — see Algorithm Design §9)

### Basket 2: Cost Optimized
1. Allows flexibility on quantity — may sell more than target
2. Prefers whole lots (avoids partial lot sells)
3. Optimizes total cost: tax + transaction charges
4. Prefers fewer orders (may favor single plan type if tax difference is small)
5. For USD/INR: proceeds must be ≥ target amount
6. Quantity within reasonable range of target (±30% for shares, ≥ target for amounts)

## Requirement 6: Tax Rules

1. STCG rate: 31.2% (30% + 4% cess) — conservative slab estimate
2. LTCG rate: 13% (12.5% + 4% cess)
3. Tax on losses: 0 (no negative tax)
4. Offset cascade (Indian tax rules):
   - STCL offsets STCG first, then LTCG (cross-offset)
   - LTCL offsets LTCG only
5. FY baseline gains/losses factored into offset computation
6. These are estimates — user should consult tax advisor

## Requirement 7: Future Offset Value Preservation

1. STCL is more valuable than LTCL (can offset both STCG + LTCG)
2. When loss lots can offset gains: prefer using LTCL to offset LTCG (same bucket)
3. Preserve STCL for future use when LTCL suffices for current need
4. This rule applies to Basket 1 sorting priority

## Requirement 8: Basket Output

Per basket, show:
- Basket name and strategy description
- List of lots: Plan Type, Grant#, Vest Date, Qty to Sell, Cost Basis, Current Price, Gain Type, Est. Gain (INR), Est. Tax (INR)
- Summary: Total shares, Proceeds (USD + INR), Total tax (INR), Net proceeds (INR)
- Order count and estimated charges
- STCG/LTCG breakdown
- If Basket 2 sells more than target: show "+X shares" note with reason

## Requirement 9: UI

1. Route: `/sell`
2. Input: radio buttons (Shares/USD/INR) + numeric input + "Advise" button
3. Current price + FX rate displayed
4. FY context displayed (existing STCG/LTCG)
5. Results: 2 basket cards, each expandable to show lot detail
6. Download CSV per basket
7. Disclaimer: "Estimates only. Consult your tax advisor."
8. Nav: "Sell Advisor" in nav bar

## Requirement 10: Download

1. CSV per basket
2. Columns: Plan Type, Grant#, Vest Date, Qty to Sell, Cost Basis, Current Price, Gain Type, Est. Gain (INR), Est. Tax (INR)
3. Summary row at bottom
4. Filename: `Sell_Advisor_{basket_name}_{date}.csv`

## Out of Scope (Phase 1)

- Slab-based STCG tax computation (uses flat 30%)
- Surcharge calculation
- Exact brokerage charges (TBD — hardcode estimate)
- Wash sale rules
- Broker order generation
- Multi-symbol support
- User-configurable tax rates
