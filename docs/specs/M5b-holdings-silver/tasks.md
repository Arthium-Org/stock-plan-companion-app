# Tasks: M5b — Holdings Silver (Own Tables)

## Prerequisites

- M3b: Holdings parser + Bronze writer (done)
- M7a: FX service (done)

---

## Milestone 1: Schema + Migration

- [ ] 1.1 Generate migration: `create table stock_plan_holdings`
- [ ] 1.2 Create schema: `lib/stock_plan/schema/holding.ex`
- [ ] 1.3 Add changeset with required fields: id, ingestion_id, account_id, plan_type, status
- [ ] 1.4 Run migration
- [ ] 1.5 `mix test` — no regressions

## Milestone 2: HoldingsSilverBuilder — RSU

- [ ] 2.1 Create `lib/stock_plan/ingestion/holdings_silver_builder.ex`
- [ ] 2.2 `build(account_id)` — find ACTIVE Holdings ingestion, delete existing holdings, process Bronze
- [ ] 2.3 RSU processing:
  - Group Bronze rows by Grant Number
  - Build Vest Period → Vest Date map from Vest Schedule rows
  - Build Vest Period → Sellable data map from Sellable Shares rows
  - For each Vest Schedule row: create Holdings Silver row
  - Sellable qty logic:
    - Has Sellable Shares → sellable_qty = Sellable Qty + Blocked Share Qty
    - VESTED but no Sellable Shares → sellable_qty = 0 (fully sold)
    - UNVESTED → sellable_qty = nil
- [ ] 2.4 Write tests with SampleUser-2 (RSU only, no Sellable Shares)
- [ ] 2.5 Write tests with SampleUser-3 (RSU with Sellable Shares)
- [ ] 2.6 `mix test` — pass

## Milestone 3: HoldingsSilverBuilder — ESPP

- [ ] 3.1 ESPP processing: one Holdings Silver row per Purchase
- [ ] 3.2 cost_basis = Purchase Date FMV (Indian capital gains)
- [ ] 3.3 purchase_price = Purchase Price (discounted buy price)
- [ ] 3.4 sellable_qty = Sellable Qty + Blocked Qty
- [ ] 3.5 grant_number = hash of "ESPP:{symbol}:{grant_date}"
- [ ] 3.6 Write tests with SampleUser-3 (ESPP + RSU)
- [ ] 3.7 `mix test` — pass

## Milestone 4: FX Enrichment

- [ ] 4.1 After Holdings Silver rows created, enrich with vest_fx_rate
- [ ] 4.2 Use FX.get_rate(vest_date) — previous month's rate
- [ ] 4.3 Write test: verify vest_fx_rate populated
- [ ] 4.4 `mix test` — pass

## Milestone 5: Orchestrator — Wire Holdings Silver

- [ ] 5.1 Update `ingest_holdings/2` to call `HoldingsSilverBuilder.build` instead of `SilverBuilder.build`
- [ ] 5.2 Holdings ingestion no longer triggers BH Silver rebuild
- [ ] 5.3 Remove Phase 5 from SilverBuilder (or make it no-op)
- [ ] 5.4 Write end-to-end test: upload Holdings → Holdings Silver created
- [ ] 5.5 `mix test` — pass

## Milestone 6: Portfolio.build — Read from Holdings Silver

- [ ] 6.1 Add `has_holdings_ingestion?/1` check
- [ ] 6.2 `build_from_holdings/1` — reads stock_plan_holdings, returns hierarchical structure
- [ ] 6.3 `build_from_bh/1` — existing logic (with DHF-1 origin-level sold fix)
- [ ] 6.4 Portfolio returns same hierarchical shape regardless of source
- [ ] 6.5 Write test: Holdings uploaded → portfolio reads from holdings table
- [ ] 6.6 Write test: No Holdings → portfolio falls back to BH
- [ ] 6.7 `mix test` — pass

## Milestone 7: Verification

- [ ] 7.1 `mix format --check-formatted`
- [ ] 7.2 `mix compile --warnings-as-errors`
- [ ] 7.3 `mix test` — all pass
- [ ] 7.4 Manual test: User 2 (BH + Holdings RSU) — Portfolio shows Holdings data
- [ ] 7.5 Manual test: User 3 (BH + Holdings ESPP+RSU) — correct data
- [ ] 7.6 Manual test: User 1 (BH only, no Holdings) — BH fallback, sold grants excluded
- [ ] 7.7 Manual test: Holdings only (no BH) — works independently

---

## Definition of Done

- [ ] `stock_plan_holdings` table created and populated from Holdings Bronze
- [ ] RSU: one row per vest period with correct sellable_qty logic
- [ ] ESPP: one row per purchase with Purchase Date FMV as cost_basis
- [ ] FX rates applied to Holdings Silver
- [ ] Portfolio.build reads from Holdings Silver when available
- [ ] Portfolio falls back to BH with origin-level sold calculation
- [ ] Holdings ingestion is independent of BH
- [ ] Phase 5 enrichment removed from SilverBuilder
- [ ] All tests pass, all 4 users display correctly
