# Tasks: M29 — FX Sync API (Subscribers Only)

## Prerequisites

- M28 auth API live (JWT + entitlements)
- Desktop `StockPlan.FX` and `FxMonthlyRate` schema as reference
- FX seed data file available

---

## Milestone 1: Portal FX Schema & Seed

**Dir:** `portal/priv/repo/migrations/`, `portal/lib/portal/schema/fx_monthly_rate.ex`

- [ ] 1.1 Migration: `portal_fx_monthly_rates` (mirror desktop columns)
- [ ] 1.2 Unique index on `{year_month, currency_pair}`
- [ ] 1.3 Copy/adapt `fx_seed_data.exs` for portal
- [ ] 1.4 Mix task `portal.fx.seed` — idempotent upsert
- [ ] 1.5 Verify row count matches desktop seed (~333 rows)
- [ ] 1.6 `mix test` — pass

## Milestone 2: FX Context Module

**File:** `portal/lib/portal/fx.ex`

- [ ] 2.1 `previous_month_key/1` — same logic as desktop
- [ ] 2.2 `pick_best_rate/1` — tt_buying → standard_end → avg
- [ ] 2.3 `get_rate/1` for transaction date
- [ ] 2.4 `current_rate/0`
- [ ] 2.5 `list_monthly/2` with range validation (max 120 months)
- [ ] 2.6 `sync_status/0`
- [ ] 2.7 Unit tests mirroring `test/stock_plan/fx_test.exs` cases
- [ ] 2.8 `mix test` — pass

## Milestone 3: FX API Controller

**File:** `portal/lib/portal_web/controllers/api/fx_controller.ex`

- [ ] 3.1 `RequireFxEntitlement` plug
- [ ] 3.2 `GET /api/v1/fx/current` (optional diagnostic)
- [ ] 3.3 `GET /api/v1/fx/monthly?from=&to=`
- [ ] 3.4 `GET /api/v1/fx/sync-status`
- [ ] 3.5 Decimal → string serialization
- [ ] 3.6 Controller tests with entitled vs expired user
- [ ] 3.7 `mix test` — pass

## Milestone 4: Rate Limiting

- [ ] 4.1 FX-specific rate limit (100/hour/user)
- [ ] 4.2 429 response with Retry-After
- [ ] 4.3 Test rate limit trigger

## Milestone 5: Admin Import

**File:** `portal/lib/mix/tasks/portal.fx.import.ex`

- [ ] 5.1 CLI import for new monthly rate
- [ ] 5.2 Document monthly ops runbook in portal README
- [ ] 5.3 Manual test: import row, verify via API

## Milestone 6: Documentation

- [ ] 6.1 Add FX sync section to `getting-started.md` (M27)
- [ ] 6.2 API reference page on portal (optional `/docs/fx-api` for subscribers — or internal doc only)
- [ ] 6.3 Cross-reference M30 desktop sync behavior

---

## Definition of Done

- Subscriber JWT can fetch monthly bulk rates
- Expired trial gets 403 on all FX endpoints
- Portal FX lookup matches desktop for sample dates (spot check 10 dates)
- Seed data loaded in production
