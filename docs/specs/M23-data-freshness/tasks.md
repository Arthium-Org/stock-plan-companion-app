# Tasks: M23 — Data Freshness Detection & Re-upload Nudges

## Prerequisites

- M9 upload UX wire-up (FileDetector + UploadChecks) — already shipped
- M21 tranche timeline — already shipped (UploadChecks uses it)

---

## Milestone 1: Welcome-screen routing fix

**File:** `lib/stock_plan_web/live/home_live.ex`

- [ ] 1.1 Add private `has_ingestions?/1` helper using
  `Repo.exists?` against `stock_plan_ingestions`.
- [ ] 1.2 Update `mount/3`: if profile present AND
  `has_ingestions?(@account_id)` → `push_navigate` to `/portfolio`.
- [ ] 1.3 No other render-path changes (welcome and guide rendering
  stay as-is for the other branches).
- [ ] 1.4 Unit test (LiveView): when an ACTIVE ingestion exists, mount
  redirects to `/portfolio`; when none exists, renders the guide.

## Milestone 2: Past-due-vests check

**File:** `lib/stock_plan/ingestion/upload_checks.ex`

- [ ] 2.1 Add `defp check_past_due_vests/1` (see design.md for
  signature + query).
- [ ] 2.2 Wire into the existing `check/1` nudge accumulator.
- [ ] 2.3 Add `:past_due_vests` to the documented nudge codes.
- [ ] 2.4 Tests: fixture with one `status=UNVESTED` tranche whose
  `vest_date` is yesterday → nudge present; future vest → no nudge.

## Milestone 3: G&L-coverage-by-year check

**File:** `lib/stock_plan/ingestion/upload_checks.ex`

- [ ] 3.1 Confirm where the G&L ingestion records its tax year
  (`metadata_json` key or column). Add a private accessor `gl_year/1`
  that takes an `Ingestion` row and returns the year.
- [ ] 3.2 Add `defp check_gl_coverage/1` — compute sale years from
  Silver `stock_plan_sales` rows, compare against years covered by
  ACTIVE `GL_EXPANDED` ingestions.
- [ ] 3.3 Nudge severity (deterministic): `:warning` for current FY,
  `:error` for any past FY.
- [ ] 3.4 Tests: BH with sales in 2024 + 2025, G&L for 2025 only →
  one nudge for 2024 with severity `:error`.

## Milestone 4: Appraisal-grant heuristic

**File:** `lib/stock_plan/ingestion/upload_checks.ex`

- [ ] 4.1 Add private `grant_month_clusters/1` that returns
  `[{month_integer, [date, ...]}]` sorted by count desc, filtered
  to clusters with ≥2 entries.
- [ ] 4.2 Add private `has_recent_grant_in_window?/3`.
- [ ] 4.3 Add `defp check_appraisal_grant_pattern/1` implementing the
  algorithm in design.md.
- [ ] 4.4 Severity `:info`. Action: link to `/upload`.
- [ ] 4.5 Tests:
  - Two grants in March across different years, today is in April,
    no March grant this year → nudge.
  - Two grants in March, today is in April but a March grant this
    year exists → no nudge.
  - Only one grant total → no nudge (no pattern).
  - No RSU grants → no nudge.

## Milestone 5: Banner summary API (per-category freshness)

**File:** `lib/stock_plan/ingestion/upload_checks.ex`

- [ ] 5.1 Add `banner_summary/1` returning the struct in design.md
  (`freshness_basis`, `age_phrase`, `severity`, `nudge_count`,
  `primary_action`).
- [ ] 5.2 Add private `freshness_by_category/1` — one ACTIVE
  ingestion's `inserted_at` per category (BH, Holdings, G&L), nil
  if never uploaded.
- [ ] 5.3 Add private `oldest_required_category/1` — picks the
  bottleneck (required category that's either missing or has the
  oldest upload).
- [ ] 5.4 Add private `compute_severity/2` — explicit hierarchy:
  required-missing > error nudge > warning nudge > info nudge > ok.
- [ ] 5.5 Add private `compute_primary_action/2` — derives
  call-to-action text from the highest-severity nudge, missing
  required category, or "All good".
- [ ] 5.6 Add `age_phrase/1` helper (today / yesterday / N days ago /
  N weeks ago / N months ago / N years ago).
- [ ] 5.7 Add `bottleneck_age_phrase/1` — prefixes the category name
  (e.g., "Holdings — 6 months ago").
- [ ] 5.8 Tests covering each branch of age_phrase, severity
  hierarchy, primary action variants, and the bottleneck
  identification with mixed-freshness inputs.

## Milestone 6: Sticky banner component + layout integration

**Files:**
- `lib/stock_plan_web/components/upload_state_banner.ex` (new)
- `lib/stock_plan_web/components/layouts/root.html.heex`
- All LiveViews that render below the navbar (Portfolio, Tax, Sell,
  History, Upload)

- [ ] 6.1 Create the `upload_state_banner/1` component (heex above).
- [ ] 6.2 Add an `assign_upload_banner/1` helper in
  `StockPlanWeb.LiveView` (or wherever shared LV helpers live).
- [ ] 6.3 Each LiveView calls `assign_upload_banner/1` in its
  `mount/3`. Also re-call after each `{:ingestion_done, _}`.
- [ ] 6.4 Root layout: render the banner if `@upload_banner` is
  assigned. Hide on `/` (welcome path) and `/upload` (nudges already
  shown inline).
- [ ] 6.5 Click target on the whole banner → `/upload`.
- [ ] 6.6 Visual styling: 32px tall, color-coded background (DaisyUI
  `bg-success/10`, `bg-warning/10`, `bg-error/10`, `bg-info/10`,
  default `bg-base-200`).

## Milestone 7: Tests + verification

- [ ] 7.1 Integration test: upload a fixture, navigate to Portfolio,
  assert banner renders with "today" + green dot.
- [ ] 7.2 Integration test: fixture with a past-due vest, navigate to
  Tax, assert banner renders with yellow dot + count 1, click goes
  to `/upload`.
- [ ] 7.3 `mix compile --warnings-as-errors` clean.
- [ ] 7.4 `mix test` all pass (existing + new). Target: previous count
  + ~12 new tests.

## Milestone 8: Polish

- [ ] 8.1 Banner: subtle hover state (slightly darker background).
- [ ] 8.2 Banner: keyboard-focusable (it's already an `<a>` so default
  focus styles apply; double-check).
- [ ] 8.3 Manual: re-launch the app after an upload — confirm landing
  on Portfolio, not the welcome guide.
- [ ] 8.4 Manual: with a real BH fixture that has sales in 2024 only
  and no 2024 G&L → banner shows error, nudge text is correct.

---

## Definition of Done

- [ ] User who has uploaded data sees Portfolio on relaunch (not
  welcome/guide).
- [ ] Three new nudges produced by UploadChecks: past-due vests,
  missing G&L year, appraisal-grant heuristic.
- [ ] Sticky banner on Portfolio / Tax / Sell / History / Upload, with
  last-upload age, severity dot, and nudge count.
- [ ] Banner click → `/upload`.
- [ ] All checks recompute after each ingestion (via
  `{:ingestion_done, _}` handle_info).
- [ ] No new dependencies, no migrations.
- [ ] `mix test` green.

## Invariants

```
For every page under the browser pipeline (except / and /upload):
  banner is rendered
  banner.severity = max severity over current nudges (or :ok)
  banner.age_phrase reflects DateTime.diff(now, latest_ingestion.inserted_at)

For UploadChecks.check/1:
  result.nudges is a list of valid nudge structs
  result.nudges is recomputed on every call (no internal caching)

For UploadChecks.banner_summary/1:
  freshness_basis identifies the oldest required category (BH or Holdings)
  age_phrase prefixes the bottleneck category name
  severity hierarchy: required_missing > error nudge > warning nudge > info nudge > ok
  primary_action derived from highest-severity nudge or missing-category state
```
