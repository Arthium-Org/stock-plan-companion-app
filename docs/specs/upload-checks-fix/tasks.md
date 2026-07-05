# Tasks: Upload Checks Redesign (BH Metadata)

## Prerequisites

- M22 `dominant_symbol` migration must be applied (branch `feature/m22-multi-symbol`)
- All existing tests pass before starting

---

## Task 1 — Migration: add `bh_snapshot_json` column

**File:** new migration in `priv/repo/migrations/`

- [ ] 1.1 `mix ecto.gen.migration add_bh_snapshot_json_to_ingestions`
- [ ] 1.2 `alter table(:stock_plan_ingestions) do add :bh_snapshot_json, :text, null: true end`
- [ ] 1.3 Add field `:bh_snapshot_json, :string` to `StockPlan.Schema.Ingestion`
- [ ] 1.4 `mix ecto.migrate` — verify column exists
- [ ] 1.5 `mix test` — confirm nothing breaks

---

## Task 2 — BH snapshot computation

**File:** `lib/stock_plan/ingestions.ex`

- [ ] 2.1 Add private `compute_bh_snapshot(ingestion_id)` — returns JSON string
  - Count origins with VESTED shares where `origin-level net_quantity > origin-level sold`
    (using `Sale.total_quantity` per origin — NOT `SaleAllocation`)
  - Count UNVESTED tranches
  - Collect distinct sale years from Sale records for this ingestion
  - Encode as `Jason.encode!(%{vested_unsold_origin_count:, unvested_count:, sale_years:})`
- [ ] 2.2 Call `compute_bh_snapshot` at end of `ingest_benefit_history/2` and persist via
  `Repo.update!` on the ingestion changeset
- [ ] 2.3 Add `bh_has_current_shares?(account_id) :: boolean` — queries `bh_snapshot_json`
  via `json_extract` for any active BH ingestion where vested_unsold > 0 OR unvested > 0
- [ ] 2.4 Add `has_active_holdings?(account_id) :: boolean` (thin `Repo.exists?` wrapper,
  mirrors `any_active_bh?`)
- [ ] 2.5 Unit tests in `test/stock_plan/ingestion/silver_builder_test.exs` or new file:
  - After ingest_benefit_history, ingestion has non-null `bh_snapshot_json`
  - Fully-sold user: `vested_unsold_origin_count == 0`, `unvested_count == 0`
  - User with active holdings: `vested_unsold_origin_count > 0`
  - Sale years match BH SELL events

---

## Task 3 — Remove Phase 1 ESPP allocations and Yahoo proxy price

**File:** `lib/stock_plan/ingestion/silver_builder.ex`

Must run before Task 4 — `compute_gl_coverage_gaps` relies on `sale_price NOT NULL` to detect
G&L coverage. Phase 1 Yahoo prices on ESPP allocations would fool that check.

- [ ] 3.1 In `process_espp/2`, inside the sell_events reduce:
  - Remove the `yahoo_price` fetch block (`StockPlan.StockPrice.get_close` try/rescue)
  - Remove the `proceeds` computation
  - Change `insert_sale!` attrs to `%{sale_date: sale_date, total_quantity: qty}` (no price/proceeds)
  - Remove `create_gl_allocation(sale, tranche, qty, yahoo_price, nil)` call
  - Remove `ac2` (alloc accumulator) from the inner reduce — ESPP Phase 1 creates 0 allocations
- [ ] 3.2 Remove the outer `alloc_count` accumulator from `process_espp` (`ac` in the purchase
  groups reduce) — it will always be 0 and is no longer meaningful
- [ ] 3.3 `mix compile --warnings-as-errors` — confirm no unused variable warnings
- [ ] 3.4 `mix test` — confirm Phase 1 tests still pass; ESPP sale records exist, allocations do not

---

## Task 4 — UploadChecks rewrite

**File:** `lib/stock_plan/ingestion/upload_checks.ex`

- [ ] 4.1 Add `load_bh_snapshots/1` — loads and JSON-decodes all active BH ingestions' snapshots
- [ ] 4.2 Add `aggregate_snapshots/1` — sums vested_unsold_origins, unvested; unions sale_years
- [ ] 4.3 Add `compute_gl_coverage_gaps/1` — compares BH sale dates (CY-1 and CY window)
  against GL-confirmed allocations (`sale_price NOT NULL`). Returns
  `%{uncovered_cy1: [{id, date}], uncovered_cy: [{id, date}]}`. Works whether G&L is absent
  entirely or only partially covers the date range — same code path for both.
- [ ] 4.4 Rewrite `check/1` per design — use snapshot for `has_current_shares`; use
  `compute_gl_coverage_gaps` for G&L nudges and readiness
- [ ] 4.5 Replace global `no_gl` nudge + year-based `gl_coverage_gap` nudge with
  `add_gl_coverage_nudges` — one `:warning` nudge for CY-1 uncovered dates, one `:info` nudge
  for CY uncovered dates. Code `:no_gl_for_dates` for both.
- [ ] 4.6 Update `maybe_add_no_holdings` — Holdings nudge severity is `:error` (not `:info`)
  when current shares detected and no Holdings uploaded
- [ ] 4.7 Rewrite `build_readiness`:
  - Portfolio: `:ready` (Holdings + current shares), `:blocked` (otherwise)
  - Capital Gains / FSI: `:blocked` if `gl_coverage.uncovered_cy1 != []`; else `:ready`
  - Schedule FA: same CY-1 block; additionally `:limited` if no Holdings
  - Vesting / Sell Advisor: unchanged
- [ ] 4.8 Remove `compute_symbols_with_holdings/1` — replaced by snapshot-derived
  `bh_symbols_with_unsold` (symbols where per-ingestion `vested_unsold_origin_count > 0`)
- [ ] 4.9 Remove `load_bh_sales/1`, `load_allocations/1`, `check_gl_coverage/2`,
  `maybe_add_no_gl/4` — all replaced by `compute_gl_coverage_gaps`
- [ ] 4.10 Update `check_symbol_consistency/2` — second arg becomes `bh_symbols_with_unsold`
  MapSet derived from per-ingestion snapshots; no live DB query needed
- [ ] 4.11 Handle `legacy_bh` path in `check/1` — when `has_bh = true` but `snapshots = []`,
  skip G&L/Holdings checks; emit `:bh_snapshot_missing` info nudge; set portfolio to `:limited`
- [ ] 4.12 `mix test test/stock_plan/ingestion/upload_checks_test.exs` — all pass

---

## Task 5 — Update upload checks tests

**File:** `test/stock_plan/ingestion/upload_checks_test.exs`

- [ ] 5.1 Update "User 1: BH + G&L, no Holdings" — portfolio readiness is now `:blocked`
  (was `:limited`). Schedule FA remains `:limited` (no Holdings but G&L covers CY-1)
- [ ] 5.2 Update "BH only, no G&L" describe block:
  - Remove `capital_gains is :blocked without G&L` (already blocked — stays)
  - Update `schedule_fa is :blocked` — now blocked via CY-1 check (same result, different reason)
  - Add test: `no_gl_for_dates` nudge fires for CY-1 (2025) when BH has 2025 sales
  - Add test: global `no_gl` nudge is GONE (replaced by per-dates nudge)
- [ ] 5.3 Add test: "BH only, no sales" — no G&L nudges; Capital Gains / FSI / Schedule FA `:ready`
- [ ] 5.4 Add test: "BH only, fully sold" — Portfolio `:blocked` (no current shares, nothing to show)
- [ ] 5.5 Add test: "BH with current shares, no Holdings" — Portfolio `:blocked`, Holdings nudge
  has `:error` severity
- [ ] 5.6 Add test: "ESPP BH only, no G&L" — `:no_gl_for_dates` fires for ESPP sale dates
  (regression: was silently suppressed by Yahoo proxy price before Task 3)
- [ ] 5.7 `mix test test/stock_plan/ingestion/upload_checks_test.exs`

---

## Task 6 — Portfolio BH fallback removal

**File:** `lib/stock_plan/portfolio.ex`

- [ ] 6.1 Delete `build_from_bh/1` and all private helpers used only by it:
  `build_bh_holding_row/3`, `build_origin_group/2`, `tranche_cost_basis/2`,
  `origin_sold_map`, `origin_vested_map`, `fully_sold_origins` logic
- [ ] 6.2 `build/1` becomes:
  ```elixir
  def build(account_id), do: build_from_holdings(account_id)
  ```
- [ ] 6.3 Remove the `has_holdings_ingestion?/1` branch (keep function if used elsewhere,
  or replace with `Ingestions.has_active_holdings?/1`)
- [ ] 6.4 `mix test test/stock_plan/portfolio_test.exs` — remove/update BH-fallback test cases

---

## Task 7 — Portfolio page state machine

**File:** `lib/stock_plan_web/live/portfolio_live.ex`

- [ ] 7.1 In `mount/3`, compute `portfolio_state` using `Ingestions.any_active_bh?` +
  `Ingestions.bh_has_current_shares?` + `Ingestions.has_active_holdings?`
  (no live Portfolio query for the state check — use ingestion/snapshot flags)
- [ ] 7.2 Remove the interim `all_positions_sold` assign added in the previous fix
- [ ] 7.3 Add `portfolio_state` to socket assigns
- [ ] 7.4 In `render/1`: when `@portfolio_state != :active`, render state-specific banner
  and skip the table/tab content
- [ ] 7.5 State banners:
  - `:no_data` — "Upload a Benefit History file to get started"
  - `:all_sold` — "All positions appear to be sold — see History for your transaction record"
  - `:holdings_required` — "Upload a Holdings (ByBenefitType) file to view your portfolio"
  - `:active` — render existing tabs/tables normally
- [ ] 7.6 Manual test: upload BH only (User 1 fixture) → Holdings Required state shown
- [ ] 7.7 Manual test: upload BH + Holdings → portfolio renders
- [ ] 7.8 Manual test: empty account → no_data state

---

## Task 8 — Final verification

- [ ] 8.1 `mix compile --warnings-as-errors`
- [ ] 8.2 `mix test --max-cases 1`
- [ ] 8.3 Manual end-to-end: upload BH only → upload screen shows blocked portfolio + per-FY G&L
  warnings → upload Holdings → portfolio unblocks → upload G&L → G&L warning clears
- [ ] 8.4 Confirm User 3 (full data) — all features `:ready`, no spurious nudges
- [ ] 8.5 Confirm ESPP user (User 1): no G&L → `:no_gl_for_dates` fires; upload G&L → clears

---

## Sequencing

Tasks must run in this order (each depends on the previous):

```
Task 1 (migration) → Task 2 (snapshot) → Task 3 (ESPP Phase 1 fix) →
Task 4 (checks rewrite) → Task 5 (test updates) → Task 6 (BH fallback removal) →
Task 7 (portfolio page) → Task 8 (verification)
```
