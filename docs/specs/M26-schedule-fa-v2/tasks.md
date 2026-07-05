# Tasks: M26 — Schedule FA v2

## Prerequisites

- M14: Schedule FA row fields, CSV format, Tax Centre UI
- M21: `TrancheTimeline.build/1` (sells, holdings_qty, BH validation)
- M23/upload-checks-fix: `bh_snapshot_json` on BH ingestions
- Sample fixtures: User 1 (fully sold), User 3 (Holdings + partial sells)

---

## Milestone 1: Pre-checks (before TrancheTimeline)

**Files:** `lib/stock_plan/tax/schedule_fa.ex`, `lib/stock_plan/tax/tranche_timeline.ex`

Pre-checks run BEFORE `TrancheTimeline.build`. Both use direct DB queries — no timelines.

- [ ] 1.1 Add `check_gl_coverage_for_fa_year/3` — all plan types; BH sell dates `>= cy_start` vs G&L allocation dates
- [ ] 1.2 Add `check_holdings_available/2` — direct DB: Holdings rows exist for account? OR per-origin BH reconciliation (`bh_sold ≈ total_released` per origin via aggregate query)
- [ ] 1.3 Add `ScheduleFA.pre_check/2` returning `:ok | {:error, message}` — wraps P1 + P2 (for UploadChecks reuse)
- [ ] 1.4 Update `TrancheTimeline`: `match_holding` returns `sellable_qty || Decimal.new(0)`; remove `apply_bh_sold_validation_with_holdings` and its call site
- [ ] 1.5 Unit tests for P1 and P2 (table-driven, no DB where possible)

## Milestone 2: CY state algorithm

**File:** `lib/stock_plan/tax/schedule_fa.ex`

- [ ] 2.1 Implement `compute_cy_state/2` — Rules 1, 2, 3
- [ ] 2.2 Add `sum_sells_in_range/3`, `sum_sells_after/2`
- [ ] 2.3 Add `effective_holdings/1` — single clause: `t.holdings_qty` (unified RSU + ESPP; never nil after TrancheTimeline)
- [ ] 2.4 Unit tests for Rules 1–3 and exclusion (`start_count == 0`)

## Milestone 3: Wire `build/2`

**File:** `lib/stock_plan/tax/schedule_fa.ex`

Order in `build/2`: P1 → P2 → `TrancheTimeline.build` → `compute_cy_state` → rows.

- [ ] 3.1 Replace `held_during_cy` path with `compute_cy_state` pipeline
- [ ] 3.2 Remove soft-degradation branch (`format_gl_warning` + build on `{:error}`)
- [ ] 3.3 Remove post-aggregate row filter (`closing=0 AND proceeds=0`)
- [ ] 3.4 Rename/refactor `build_fa_rows_from_timeline` → `build_fa_rows_from_state`
- [ ] 3.5 Fix `initial_value_inr` and peak to use `start_count`
- [ ] 3.6 Update existing `schedule_fa_test.exs` — tests expecting soft warning must expect `{:error}` or empty per new rules

## Milestone 4: Upload readiness

**File:** `lib/stock_plan/ingestion/upload_checks.ex`

- [ ] 4.1 Add `schedule_fa_readiness/2` delegating to `ScheduleFA.pre_check/2`
- [ ] 4.2 Replace `uncovered_cy1` global block with P1/P2 for CY-1
- [ ] 4.3 Update `upload_checks_test.exs` — User 1 BH-only: FA readiness reflects P1 for CY-1, not blanket block on all 2025 sales when evaluating wrong year
- [ ] 4.4 Document: Upload badge = CY-1; Tax Centre = selected year

## Milestone 5: Regression fixtures

- [ ] 5.1 User 1 BH only — FA 2024 returns `{:error, _}` (P1 blocks); P2 would pass if G&L present
- [ ] 5.2 User 1 BH + 2024 G&L — FA 2024 builds; pre-CY RSU with only 2024 sells correct `start_count`
- [ ] 5.3 User 1 BH + 2025 G&L only — FA 2024: P1 may block OR show tranches held on Dec 31 2024 (document expected)
- [ ] 5.4 User 3 Holdings + G&L — Rule 3 uses Holdings for pre-CY tranches (R3.3 case)
- [ ] 5.5 `mix test` — pass, 0 warnings

- [ ] 5.6 User 2 BH + G&L + zero Holdings — FA CY 2025 returns no phantom ESPP closing rows (no row with `closing_value > 0` and `proceeds == 0` for pre-2024 lots)
- [ ] 5.7 Manual test: fully-exited account (snapshot `vested_unsold=0, unvested=0`) — FA output has zero closing-only rows; assert not vacuously zero

## Milestone 6: Docs cleanup

- [ ] 6.1 Update M14 FA-4 to reference M26 for data dependencies
- [ ] 6.2 Close DHF-16 in `data-handling-fixes.md` with pointer to M26
- [ ] 6.3 Mark regression-test-fixes R1 as superseded by M26
