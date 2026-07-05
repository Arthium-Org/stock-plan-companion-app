# Test Plan: M23 — Data Freshness Detection & Re-upload Nudges

## Test surface

| Module / View | What we test |
|---|---|
| `StockPlan.Ingestion.UploadChecks.check/1` | Three new nudges trigger correctly; severity assignment; no false positives |
| `StockPlan.Ingestion.UploadChecks.banner_summary/1` | Age phrase + severity + nudge count are consistent with check/1 |
| `HomeLive` | Routing logic: welcome vs guide vs redirect |
| `UploadStateBanner` (component) | Renders all severity states; clickable; accessible |
| LiveViews that include the banner | `:upload_banner` is assigned in mount + after `{:ingestion_done, _}` |

---

## Unit tests

### `check_past_due_vests/1`

```
1. Empty DB → no nudge
2. Tranche status=UNVESTED, vest_date = today_eastern - 5 days → 1 nudge, severity :warning
3. Tranche status=UNVESTED, vest_date = today_eastern - 1 day → no nudge (within grace_days = 3)
4. Tranche status=UNVESTED, vest_date = today_eastern + 1 day → no nudge
5. Tranche status=VESTED, vest_date=last year → no nudge
6. Two tranches both past cutoff → 1 nudge (aggregated), reason says "2 tranche(s)"
7. Tranche on an ARCHIVED ingestion → no nudge
8. Nudge text says "Please check at E*Trade" — NOT "vests pending" or "data stale"
9. Timezone awareness: stub eastern_today/0 to return 2026-05-01;
   tranche with vest_date=2026-04-29 → no nudge (within grace); vest_date=2026-04-27 → nudge
```

### `check_gl_coverage/1`

```
1. No sales → no nudge
2. Sales in current FY, G&L for current FY uploaded → no nudge
3. Sales in current FY only, no G&L → 1 nudge, severity :warning (deterministic)
4. Sales in previous FY, no G&L → 1 nudge, severity :error (deterministic — no longer
   "depends on recency")
5. Sales in current FY + previous FY, G&L for current FY only → 1 nudge for previous FY,
   severity :error
6. Sales in 2023, 2024, 2025 with G&Ls for 2024 only (current FY = 2025) →
   2 nudges: 2023 :error, 2025 :warning
7. India FY boundary: today = 2026-04-05 (FY 2026 just started, FY 2025 ended);
   sale dated 2026-03-15 (FY 2025) → severity :error if no G&L for 2025
8. Sales from archived ingestion → ignored
9. Multiple G&L files for same year → counted once (deduped)
```

### `check_appraisal_grant_pattern/1`

```
1. No RSU grants → no nudge
2. One RSU grant → no nudge (no pattern)
3. Two RSU grants in March of different years, today in April, no March-current-year grant → nudge, severity :info
4. Two RSU grants in March, today in April, current-year March grant present → no nudge
5. Two RSU grants in March across years, today in February (before this year's expected window) → no nudge

  -- ±1 month window cases --
6. One grant March-2023 + one grant April-2024, today is May-2025 → cluster {anchor=4 or
   anchor=3, dates in ±1 window contain both} produces a nudge
7. One grant March-2023 + one grant May-2024 (2 months apart, NOT in ±1 window of either):
   no cluster meets ≥2 condition → no nudge
8. Three grants March-2022, April-2023, March-2024 → all within March's ±1 window → nudge

  -- Multiple clusters: deterministic tie-breaker --
9. Equal-sized clusters (e.g., March cluster of 2 + October cluster of 2) →
   tie broken by "most recent qualifying cluster wins": whichever cluster
   contains the most recent grant date is selected, exactly one nudge produced
10. Grants spread evenly across all 12 months → no cluster meets ≥2 threshold → no nudge
11. Last appraisal grant within the last 365 days → no nudge (too soon)
```

### `banner_summary/1` — per-category freshness

Return shape under test:
```elixir
%{
  freshness_basis: %{category: atom, uploaded_at: DateTime.t() | nil},
  age_phrase: String.t(),
  severity: :ok | :info | :warning | :error,
  nudge_count: non_neg_integer(),
  primary_action: String.t()
}
```

```
1. No ingestions at all →
   freshness_basis.category = :benefit_history (or whichever required cat is first),
   freshness_basis.uploaded_at = nil,
   severity = :error,
   age_phrase = "No Benefit History uploaded yet" (matches bottleneck category),
   primary_action = "Upload your files →"

2. BH today + Holdings today + G&L today, no nudges →
   freshness_basis.category = :holdings (or :benefit_history; whichever required is older — both today is a tie, deterministic by category iteration order),
   severity = :ok,
   age_phrase = "Holdings — today" (or BH — today),
   primary_action = "All good"

3. BH today + Holdings 6 months ago + G&L today →
   freshness_basis.category = :holdings,
   age_phrase = "Holdings — 6 months ago" (NOT "today"),
   severity = :warning at minimum,
   primary_action describes the action needed (e.g., "Upload Holdings")

4. BH never uploaded + Holdings today + G&L today →
   freshness_basis.category = :benefit_history,
   freshness_basis.uploaded_at = nil,
   severity = :error,
   primary_action = "Upload Benefit History to unblock features →"

5. G&L missing entirely is OK (not required) — does not become the bottleneck unless
   there are :gl_missing_for_year nudges from check/1

6. Severity hierarchy (deterministic): required-missing > :error nudge > :warning nudge > :info nudge > :ok
   - Required-missing should win even with zero nudges in flight.
   - :error nudge wins over :warning nudge.
   - :info nudge produces :info severity if no higher nudges.

7. nudge_count matches length(nudges) from check/1

8. primary_action for a :warning past-due-vest nudge: "Verify {N} pending vests →"

9. primary_action for an :error gl_missing_for_year nudge: "Upload G&L for FY {year} →"

10. age_phrase variants: today / yesterday / N days ago / N weeks ago / N months ago / N years ago
```

---

## LiveView tests

### HomeLive routing

```
1. No profile.json on disk → renders welcome step (input form)
2. Profile exists, no ingestions → renders guide step
3. Profile exists, at least one ACTIVE ingestion → push_navigate to /portfolio
4. Profile exists, only ARCHIVED ingestions → renders guide (treated as no usable data)
```

### Banner rendering across LiveViews

```
1. Mount PortfolioLive with no ingestions → banner not rendered OR rendered with "No data uploaded yet"
   (depending on DESIGN DECISION above)
2. Mount TaxCentreLive with a fresh ingestion → banner renders with green dot + "today"
3. Mount any LiveView with a past-due vest → yellow dot + "1" badge
4. Click banner → push_navigate to /upload
5. After {:ingestion_done, _} message → banner re-evaluates (mock by sending message, assert assigns updated)
```

### UploadStateBanner component

```
1. severity: :ok → green dot + "All good" text
2. severity: :info → blue dot + "Suggestions available"
3. severity: :warning → yellow dot + "Action recommended →"
4. severity: :error → red dot + "Action recommended →"
5. nudge_count > 0 → badge visible with count; ==0 → badge hidden
6. age_phrase rendered verbatim
7. Component is an <a href="/upload"> for accessibility
```

---

## Integration tests

### End-to-end nudge cycle

```
1. Setup: seed fixture with BH that has UNVESTED tranche with vest_date = yesterday
2. Mount UploadLive → assert nudges list includes :past_due_vests
3. Run new BH ingestion that marks the tranche VESTED
4. Receive {:ingestion_done, _}
5. Assert nudges no longer include :past_due_vests
6. Assert banner severity falls from :warning to :ok
```

### G&L gap closure

```
1. Setup: sales in FY 2024, no G&L for 2024 → nudge present (:error)
2. Upload G&L 2024 → nudge gone
3. Banner severity drops accordingly
```

### Appraisal nudge does not double-nudge

```
1. Setup: pattern detected for March; current year is past March, no March grant this year → nudge present
2. Re-fetch UploadChecks.check/1 → same nudge appears once (not duplicated)
3. Upload BH that includes a new March-this-year grant → nudge removed on re-check
```

---

## Manual verification

### Welcome routing
- [ ] Fresh install (no profile, no DB) → welcome screen with name input
- [ ] Profile but no uploads yet → guide screen
- [ ] Existing user with uploads → Portfolio (not guide) on launch from Applications

### Banner UX
- [ ] Banner visible on Portfolio, Tax, Sell Advisor, History
- [ ] NOT visible on `/` (welcome/guide) or `/upload`
- [ ] Severity dot color matches the worst active nudge
- [ ] Click navigates to /upload
- [ ] Age phrase reads naturally for: today, 1 day, 6 days, 2 weeks, 2 months, 1 year

### Nudges on real data
- [ ] Use SampleUser-3 fixture: contains historical grants in a specific month
  → confirm appraisal heuristic produces a sensible nudge if today is past that month
- [ ] Upload BH from Sample-4 with stale data (vest_date in past, status still UNVESTED)
  → past-due nudge appears

### Edge cases
- [ ] Single-grant user → no false-positive appraisal nudge
- [ ] User who uploaded everything today → green banner, zero nudges, age = "Holdings — today" (or whichever is the oldest required category)
- [ ] User with no uploads at all → red banner, "No data uploaded yet", primary action "Upload your files →" (the open question is now resolved)
- [ ] User with BH fresh + Holdings 6 months old → banner explicitly names "Holdings — 6 months ago", not just "6 months ago"
- [ ] Past-due vest nudge wording NEVER asserts "vest happened"; phrasing reads as "please check at the broker"

---

## Non-functional checks

- [ ] `mix compile --warnings-as-errors` clean
- [ ] `mix test` all green
- [ ] Page load latency unchanged within ±10ms (banner adds one indexed query)
- [ ] No new dependencies in `mix.exs`

---

## Risks

| Risk | Mitigation |
|---|---|
| Appraisal heuristic produces false positives that annoy users | `:info` severity, dismissive-friendly banner, clear "if a grant was issued" language; can be feature-flagged off if it's noisy |
| Banner clutters narrow viewports | 32px row is shallow; collapses gracefully on mobile (banner stays single line, age phrase truncates) |
| G&L year detection breaks for files named outside the expected pattern | Fall back to extracting year from sale_date span when filename parse fails |
| Past-due vest detection fires for tranches the user genuinely doesn't care about (e.g., cancelled grants whose status was never updated) | Filter to status=UNVESTED only; cancelled tranches use status=CANCELLED so they're excluded |
