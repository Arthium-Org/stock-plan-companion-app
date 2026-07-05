# Tasks: M10 — Portfolio View (Revised)

## Prerequisites

- M3b: Holdings ingestion (sellable_qty, cost_basis_broker on tranches)
- M7a/M7b: FX + Stock Prices
- M8: Orchestrator
- M9: Upload UI with Holdings upload area

---

## Task 1: Portfolio Context — Rewrite

- [ ] 1.1 Rewrite `lib/stock_plan/portfolio.ex` to read from Holdings-enriched tranches
- [ ] 1.2 Query: tranches WHERE sellable_qty IS NOT NULL OR status = "UNVESTED"
- [ ] 1.3 Join origins for grant_number, plan_type, symbol
- [ ] 1.4 Vested rows: quantity = sellable_qty (from Holdings)
- [ ] 1.5 Unvested rows: quantity = vest_quantity (from BH vest schedule)
- [ ] 1.6 Cost basis priority: cost_basis_broker > vest_fmv > vest_day_close > nil
- [ ] 1.7 ESPP cost basis: cost_basis_broker > buy_price from metadata > nil
- [ ] 1.8 Remove sale_allocation-based available_qty computation
- [ ] 1.9 Return [] if no Holdings data exists
- [ ] 1.10 Rewrite tests: `test/stock_plan/portfolio_test.exs`
  - Vested RSU: quantity = sellable_qty from Holdings
  - Vested RSU: cost_basis = cost_basis_broker (priority 1)
  - Vested RSU: cost_basis falls back to vest_fmv (priority 2)
  - Vested RSU: cost_basis falls back to vest_day_close (priority 3, source = :market_close)
  - ESPP: cost_basis = cost_basis_broker from Holdings
  - Unvested tranche: included, vest_quantity shown
  - Tranche with sellable_qty = 0: excluded (fully sold per broker)
  - No Holdings data: returns []
  - Tax status populated from Holdings
- [ ] 1.11 Run tests — PASS

## Task 2: Summary Computation — Update

- [ ] 2.1 Update `compute_summary/2` — uses sellable_qty for current value
- [ ] 2.2 Current Value = sum(sellable_qty x price) for vested
- [ ] 2.3 Potential Value = sum(vest_quantity x price) for unvested
- [ ] 2.4 Breakdown by plan_type
- [ ] 2.5 Update tests
- [ ] 2.6 Run tests — PASS

## Task 3: PortfolioLive — Update Template

- [ ] 3.1 Add Tax Status column to table (Long Term / Short Term)
- [ ] 3.2 Update empty state: "Upload your ByBenefitType file to view portfolio" with link
- [ ] 3.3 Update FMV indicator: no indicator for :broker source
- [ ] 3.4 Verify summary cards, grouping, filters, sorting still work
- [ ] 3.5 Manual test in browser with Holdings data

## Task 4: Verification

- [ ] 4.1 `mix format --check-formatted`
- [ ] 4.2 `mix compile --warnings-as-errors`
- [ ] 4.3 `mix test` — all pass
- [ ] 4.4 Manual: upload BH + Holdings → portfolio shows sellable qty + broker cost basis
- [ ] 4.5 Manual: upload Holdings only (no BH) → vested rows shown, no unvested
- [ ] 4.6 Manual: no Holdings uploaded → empty state with upload prompt
- [ ] 4.7 Manual: USD/INR toggle works
- [ ] 4.8 Manual: filters + grouping + sorting work
- [ ] 4.9 Manual: responsive on mobile viewport

---

## Definition of Done

- [ ] Portfolio reads from Holdings-enriched tranches only
- [ ] sellable_qty used as vested quantity (not derived from sales)
- [ ] cost_basis_broker is primary cost basis (broker-authoritative)
- [ ] Tax Status column shows Long Term / Short Term
- [ ] Empty state when no Holdings data
- [ ] Summary: Total / Current / Potential from Holdings data
- [ ] All existing UI features preserved (grouping, filters, sorting, USD/INR)
- [ ] All tests pass, no regressions
