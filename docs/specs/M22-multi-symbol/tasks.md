# Tasks: M22 — Multi-Symbol Support

## Prerequisites

- M21 (tranche timeline) — Schedule FA rows must carry `symbol` field (verify before starting)
- M9 (upload UX) — wire-up complete or in progress; coordination only

---

## Milestone 1: StockMeta module

**Files:** `lib/stock_plan/stock_meta.ex`, `priv/stock_meta.json`, `test/stock_plan/stock_meta_test.exs`

- [ ] 1.1 Create `priv/stock_meta.json` with one entry (ADBE) — full metadata block
- [ ] 1.2 Create `StockPlan.StockMeta` module: `get/1`, `get!/1`, `all/0`, `known?/1`
- [ ] 1.3 Load + cache via `:persistent_term` on first call
- [ ] 1.4 Write unit tests: known symbol, unknown symbol, raise behavior
- [ ] 1.5 `mix test` — pass

## Milestone 2: Symbol universe + per-symbol totals

**File:** `lib/stock_plan/portfolio.ex`

- [ ] 2.1 Add `held_symbols(account_id)` — distinct symbols **currently held** (held qty > 0 after sale allocations). Used by Portfolio + Sell Advisor. Source: Silver origins/tranches/sales aggregation.
- [ ] 2.2 Add `owned_symbols(account_id)` — distinct `origins.symbol` across ACTIVE ingestions, including symbols the user has fully exited. Used by History + Tax Centre + Schedule FA.
- [ ] 2.3 Add `symbol_summaries(account_id, current_prices)` — one summary tile per held symbol (held qty, cost basis, current value, P&L) in USD + INR.
- [ ] 2.4 Tests:
  - Single-symbol user → both helpers return `["ADBE"]`.
  - User5 fixture (CRM holdings + ADBE sold out): `held_symbols` = `["CRM"]`; `owned_symbols` = `["ADBE", "CRM"]`.
  - All-exited user → `held_symbols` = `[]`; `owned_symbols` = full history.
- [ ] 2.5 `mix test` — pass

## Milestone 3: Replace hardcoded current_price("ADBE") scalars

**Files:** `portfolio_live.ex`, `sell_advisor_live.ex`, `tax/sell_advisor.ex`, `tax/sell_advisor_v2.ex`

- [ ] 3.1 `portfolio_live.ex`: replace scalar `current_price` with `@current_prices` map keyed by symbol
- [ ] 3.2 `portfolio_live.ex` template: per-row lookup `@current_prices[row.symbol]`; remove hardcoded "Adobe (ADBE)" label (line 369); replace with row's symbol + StockMeta display name
- [ ] 3.3 `sell_advisor_live.ex`: load `@symbol` (default to largest holding), use `current_price(@symbol)`
- [ ] 3.4 `tax/sell_advisor.ex` + `sell_advisor_v2.ex`: accept symbol parameter, no implicit ADBE fallback
- [ ] 3.5 Grep: no `current_price("ADBE")` remains anywhere outside test files + the metadata JSON
- [ ] 3.6 `mix test` — pass; `mix compile --warnings-as-errors` clean

## Milestone 4: Portfolio UI — multi-symbol header + grouping

**File:** `lib/stock_plan_web/live/portfolio_live.ex` (+ template)

- [ ] 4.1 Header: if `length(symbols) > 1`, render a per-symbol summary tile row at top; else inline single symbol
- [ ] 4.2 Grant grouping: outer group by symbol (when >1), inner group by plan_type (existing)
- [ ] 4.3 USD/INR toggle unchanged
- [ ] 4.4 Visual test: existing user with only ADBE sees no clutter
- [ ] 4.5 `mix test` — pass

## Milestone 5: Sell Advisor — symbol selector

**Files:** `sell_advisor_live.ex` (+ template), `tax/sell_advisor.ex`

- [ ] 5.1 Add `@symbol` to socket assigns, default to symbol with most held shares
- [ ] 5.2 Add `<select phx-change="select_symbol">` in template, hidden when only 1 symbol
- [ ] 5.3 `handle_event("select_symbol", ...)` updates `@symbol`, re-runs lot pick
- [ ] 5.4 All lot loads filter by `@symbol`
- [ ] 5.5 Tests for switching symbol, multi-symbol fixture
- [ ] 5.6 `mix test` — pass

## Milestone 6: Schedule FA — per-symbol rows from metadata

**File:** `lib/stock_plan/tax/schedule_fa.ex`

- [ ] 6.1 Verify `Schedule FA` row struct carries `symbol` (it should from M21; assert in code)
- [ ] 6.2 `row_to_csv/1`: look up `StockMeta.get!(row.symbol)`, fill country, code, legal name, address, zip, nature from metadata
- [ ] 6.3 `build/2` pre-validates: collect all symbols, verify every one has metadata, return `{:error, {:missing_meta, [symbols]}}` if any missing
- [ ] 6.4 Update test fixtures to include a second symbol; assert CSV has correct per-symbol fields
- [ ] 6.5 `mix test` — pass

## Milestone 7: Tax Centre UI — per-symbol blocks + combined CSV

**File:** `lib/stock_plan_web/live/tax_centre_live.ex`

- [ ] 7.1 Schedule FA tab: render stacked per-symbol blocks when >1 symbol, else current layout
- [ ] 7.2 Combined CSV download: concatenate all symbol blocks into one download (this is the user's goal)
- [ ] 7.3 Schedule FSI: same per-symbol structure
- [ ] 7.4 Capital Gains: already per-tranche; verify symbol shown in header/rows
- [ ] 7.5 Missing-metadata error displayed inline (red callout) with the offending symbol(s) and remediation: "Add metadata for ABC in priv/stock_meta.json"
- [ ] 7.6 `mix test` — pass

## Milestone 8: Per-symbol ingestion + explicit ACTIVE semantics (revised)

**Files:** `lib/stock_plan/schema/ingestion.ex`, new migration, `lib/stock_plan/ingestions.ex`, `lib/stock_plan/ingestion/xlsx_parser.ex`, `lib/stock_plan/ingestion/holdings_parser.ex`, `lib/stock_plan_web/live/upload_live.ex`, `lib/stock_plan/ingestion/upload_checks.ex`

### Ingestions context: explicit per-symbol helpers (new)

- [ ] 8.0a Add `active_bh(account_id, symbol)` → `Ingestion | nil`.
- [ ] 8.0b Add `active_holdings(account_id, symbol)` → `Ingestion | nil`.
- [ ] 8.0c Add `active_bh_symbols(account_id)` → `[symbol]`.
- [ ] 8.0d Add `active_holdings_symbols(account_id)` → `[symbol]`.
- [ ] 8.0e Add `any_active_bh?(account_id)` → boolean. Make `validate_active_bh/1` a thin wrapper.
- [ ] 8.0f Remove `get_active_holdings/1` (single-row return is no longer meaningful). Migrate all call-sites — grep for callers and update each to the per-symbol form.

- [ ] 8.1 Migration: add nullable `dominant_symbol :: text` column to `stock_plan_ingestions` + index on `(account_id, category, dominant_symbol, status)`.
- [ ] 8.2 Add field `:dominant_symbol` to `StockPlan.Schema.Ingestion`.
- [ ] 8.3 Helper `Ingestions.extract_file_symbol(rows)` — returns `{:ok, "ADBE"}` for BH/Holdings rows, `{:error, :no_symbol}` if no row has a non-empty `Symbol`. (Renamed from earlier draft `extract_dominant_symbol` — function name now reflects intent; column name stays `dominant_symbol` because it remains defensive for any future multi-symbol broker exports.)
- [ ] 8.4 `ingest_benefit_history/2`: call extractor after parse, pass symbol into `create_ingestion` + `archive_previous_bh`.
- [ ] 8.5 `ingest_holdings/2`: same pattern.
- [ ] 8.6 Rewrite `archive_previous_bh/1` → `archive_previous_bh/2` taking symbol; scope WHERE by `dominant_symbol == ^symbol`. Same for holdings.
- [ ] 8.7 G&L ingestion unchanged (no archiving, no symbol scoping).
- [ ] 8.8 Backfill task in `Application.start/2`: one-shot pass that fills `dominant_symbol` for existing rows whose value is null. Safe to skip if all rows already populated.
- [ ] 8.9 UploadLive: bump `max_entries` for `:benefit_history` and `:holdings` from 1 to 5.
- [ ] 8.10 UploadLive per-file status: extend `summary_line/2` so BH/Holdings `:done` rows include the detected symbol.
- [ ] 8.11 Silver builder: verify it doesn't have a `limit: 1` on the BH/Holdings ingestion source query. Drop if found.
- [ ] 8.12 UploadChecks: add per-symbol coverage block (BH ✓/✗ · Holdings ✓/✗) to the readiness output.
- [ ] 8.12a UploadChecks: add `check_symbol_consistency/1` producing `:bh_without_holdings` (`:info`) and `:holdings_without_bh` (`:warning`) nudges. Reuses the new `active_bh_symbols/1` and `active_holdings_symbols/1` helpers.
- [ ] 8.13 Tests:
  - Upload ADBE BH + CRM BH → both ACTIVE, both Silver-rebuilt.
  - Re-upload ADBE BH → only ADBE archived; CRM stays ACTIVE.
  - Upload Holdings for ADBE only → CRM has Origins but no Holdings; downstream queries don't blow up.
  - Extract dominant symbol from real SampleUser-5 BH files.
- [ ] 8.14 `mix test` — pass.

## Milestone 9: Test fixtures + integration

- [ ] 9.1 Add `docs/Sample-Data/SampleUser - 5/` BH + Holdings to a fixtures harness (or a fixtures-friendly subset if files are too large to commit).
- [ ] 9.2 Integration test: load both BH files, both Holdings files (well, the one that exists), and the G&L → Silver has expected origin/tranche counts per symbol → Portfolio query returns 2 symbols → both have summaries.
- [ ] 9.3 Schedule FA integration test with SampleUser-5 → assert CSV contains correct blocks for both symbols (CRM with full metadata; ADBE with empty Holdings still emits historical FA rows for years held).
- [ ] 9.4 `mix test` — pass; total test count up by ≥15.

## Milestone 10: Polish + verification

- [ ] 10.1 `mix compile --warnings-as-errors` clean
- [ ] 10.2 `mix test` all pass
- [ ] 10.3 Manual: existing single-symbol install on macOS DMG still works identically
- [ ] 10.4 Manual: forge a multi-symbol test install, walk the full UI flow
- [ ] 10.5 Add 1–2 more symbols to `priv/stock_meta.json` based on what friends actually hold

---

## Definition of Done

- [ ] Zero hardcoded "ADBE" / "Adobe" outside `priv/stock_meta.json` and tests
- [ ] User with multiple symbols sees correct per-symbol totals, prices, and tax exports
- [ ] User with single symbol sees zero UX regression
- [ ] Schedule FA emits per-symbol blocks with correct legal name/address from metadata
- [ ] Sell Advisor scoped to one symbol via selector
- [ ] All tests pass, including new multi-symbol fixtures

## Invariants

```
For every UI/data display:
  uses_actual_symbol(component) = true
  hardcoded_adbe_fallback(component) = false

For every Schedule FA row:
  row.symbol ∈ keys(StockMeta.all())  # else build returns {:error, {:missing_meta, _}}

For Sell Advisor:
  every lot considered for a sell decision has lot.symbol == @symbol
```
