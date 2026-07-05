# Requirements: M23 — Data Freshness Detection & Re-upload Nudges

## Introduction

Today the app silently shows whatever data was last uploaded. After a
vest happens, a sale is executed, or a new grant is issued, the
Portfolio / Tax / Sell Advisor pages keep showing stale numbers until
the user remembers to re-upload fresh files.

For the CA use case especially — where the user is the CA, not the
share-holder — there's no day-to-day awareness of their client's
broker activity. The app needs to detect data staleness from what it
already knows about the uploaded data and prompt for the right files.

This milestone adds three freshness checks and a sticky banner that
makes upload age visible from every page.

---

## Requirement 1: Skip welcome screen when data already exists

**Today (the bug):**
After a fresh install, the welcome flow correctly asks for the user's
name and shows the upload guide. After files are uploaded, on the
*next launch* (e.g., after closing the browser and reopening from the
Applications icon), the landing page still shows the welcome / guide
content. The user has to click through to Portfolio manually.

**Required:**
- If a profile exists AND at least one ingestion exists,
  `/` redirects to `/portfolio`.
- If a profile exists AND no ingestions exist, `/` continues to show
  the existing upload guide.
- If no profile exists, `/` continues to show the welcome name input.

No new pages — just routing logic in `HomeLive.mount/3`.

---

## Requirement 2: Possibly-due vest detection

**Trigger:** any `stock_plan_tranches` row with
`status = "UNVESTED"` and `vest_date <= today_eastern - grace_days`,
where `today_eastern` is today in `America/New_York` timezone and
`grace_days = 3` (covers weekends and US bank holidays where the
broker's actual vest may run a day or two late).

**Meaning:** the scheduled vest date is past. The broker MAY have
already vested those shares (and our data is stale), OR the broker
may still be processing (delay due to holiday / weekend / corporate
action / blackout). We can't tell the difference without hitting the
broker's API, so we **soften the nudge to a verification ask**, not
an assertion.

**Important framing:** never tell the user "X vests happened — your
data is stale." We don't know that. Tell them "the scheduled date
for these tranches has passed; please check at the broker and upload
fresh files if vesting has completed."

**Nudge text:**
> {N} tranche(s) had scheduled vest dates on or before {date}.
> Please check at E*Trade whether these have vested and, if so,
> upload fresh Benefit History and Holdings files.

**Severity:** warning.

**Action:** link to `/upload`.

**Why timezone matters:** E*Trade processes vests in US business hours.
A user in IST checking the app at 10am today might see `vest_date =
yesterday`, but in US it's still yesterday afternoon — the vest may
not have run yet. Comparing against `America/New_York` time prevents
nudging for vests that aren't actually due yet from the broker's
perspective.

**Why grace_days:** weekends, US federal holidays, and broker-specific
blackouts routinely shift vest execution by 1-3 business days.
Nudging within the grace window would mostly produce false positives.

**Where shown:**
- In the existing `UploadChecks` nudge list (Upload page) + sticky banner
- Banner primary action: "Verify {N} pending vests" → `/upload`

---

## Requirement 3: New-sale-needs-G&L detection

**Trigger:** any BH-derived sale event (`stock_plan_sales` rows where
`sale_date` falls in a calendar year for which the user has NOT
uploaded a G&L Expanded ingestion).

**Meaning:** the broker recorded a sale, but the lot-level G&L data
needed for Capital Gains and Schedule FA isn't loaded for that year.

**Nudge text:**
> Sales detected in FY {year} but no G&L Expanded file uploaded
> for that year. Capital Gains and Schedule FA will be limited until
> you upload it.

**Severity:** deterministic by year, no exceptions:
- **Current FY** (FY containing today's date): `:warning` — user has
  time to obtain and upload G&L before filing.
- **Any past FY**: `:error` — filing window is either close (last
  completed FY) or already overdue (older). Either way, blocks
  Schedule FA / Capital Gains for that year.

The earlier draft said "warning OR error depending on recency" — that
contradicted the design.md table. Resolved to the deterministic rule
above.

**Action:** link to `/upload`.

**Detection nuance:**
- "G&L coverage" is per-calendar-year. We already track this for
  Schedule FA's V2 validation — reuse the existing coverage logic.
- Only flag years where actual sales exist. Years with no sales need
  no G&L.

---

## Requirement 4: Appraisal grant heuristic

**Trigger:** based on the user's historical grant pattern, prompt
around the typical annual-grant time of year.

**Heuristic:**
- From `stock_plan_origins` rows with `plan_type = "RSU"`.
- Group `origin_date` by month-of-year, then **broaden the cluster to
  ±1 month** so March / April grants count as one cycle. A "cluster"
  is now `{anchor_month, [grants whose month ∈ anchor_month ± 1]}`.
- If a single cluster contains two or more grants across different
  years, that cluster is treated as the user's appraisal cycle.
- The cycle is identified by the anchor month (the median of the
  cluster's months).
- If `today` is at least 30 days past the most recent occurrence in
  that cluster AND the user has no grant whose month falls in the
  cluster within the current year: nudge.

Choosing ±1 over a top-2-clusters approach: top-2 risks double-nudging
the same real-world cycle (March + April issues for the same
appraisal would each produce a nudge). The ±1 window collapses them
into one nudge while still catching spread-out appraisal cycles.

**Tie-breaker (deterministic):** when two clusters have the same
grant count, the cluster whose most recent grant is more recent
wins. This biases toward the user's current cycle (e.g., if they
changed employers and the new employer issues in October while
the old one issued in March, October wins as their current pattern).

**Nudge text:**
> Your previous appraisal-cycle grants landed in {month}.
> If you received a new grant this year, upload a fresh
> Benefit History to capture it.

**Severity:** info (it's a guess, not a known gap).

**Action:** link to `/upload`.

**Edge cases:**
- Less than 2 grants in any single month → no appraisal pattern
  detected → don't nudge.
- Multiple grant clusters (e.g., March + October consistently) → only
  use the most prominent cluster (more occurrences); ignore the
  secondary. Don't double-nudge.
- User just joined a new employer / has only one grant → no pattern
  → no nudge.

**Why this is heuristic only:** we can't reliably know whether an
appraisal grant was actually issued. False positive (nudge when no
grant happened) is annoying; false negative (no nudge when a grant
happened) is the status quo. Bias toward fewer false positives —
this is an info-level nudge, not a blocking error.

---

## Requirement 5: Sticky upload-state banner

**Where:** top of every page in the app's main layout (everything
under the existing browser pipeline except `/`, `/upload`, and
`/guide`).

**Freshness metric: per-category, not global**

> Earlier draft used `latest_ingestion_inserted_at` (most recent
> upload across any category). That's misleading: a user who uploaded
> G&L today but Holdings 6 months ago saw "Updated today" — falsely
> reassuring.

Compute freshness as the **oldest ACTIVE ingestion among required
categories**:

```
required_categories = [:benefit_history, :holdings, :gl_expanded]
oldest_required_at = min(latest_active_per_category for each required cat)
banner.age_phrase = relative_phrase(oldest_required_at)
banner.freshness_basis = the category whose ingestion is oldest
```

If a required category has no ACTIVE ingestion at all (e.g., no
Holdings ever uploaded), that's treated as infinite age → forces
banner into `:error` state and identifies the missing category.

Single-symbol G&L missing for years with sales: handled by R3's nudge
codes; banner reflects via severity.

**What it shows (always-visible row):**
- Age phrase based on the oldest required category — e.g.,
  *"Holdings 6 months ago — refresh recommended"* (not just "6 months
  ago" — name the bottleneck category).
- Severity dot:
  - `:ok` (green) — all required categories present, no active nudges.
  - `:info` (blue) — only `:info`-severity nudges (e.g., appraisal heuristic).
  - `:warning` (yellow) — any `:warning` nudge.
  - `:error` (red) — any `:error` nudge OR a required category is missing entirely.
- **Primary action** text on the right side — derived from the
  highest-severity nudge (or "Upload {missing_category}" when one is
  fully absent). Examples:
  - `"Upload G&L for FY 2024 →"`
  - `"Verify 2 pending vests →"`
  - `"Upload Holdings to enable Sell Advisor →"`
  - `"All good"` (when severity is `:ok`).

**On hover / focus:** no popover for v1 — the primary action text
above gives direction. Hover popover can be a follow-up.

**Click target:** the whole banner is clickable → goes to `/upload`.

**Empty state — no ingestions at all:** severity is `:error`. Age
phrase is "No data uploaded yet". Primary action is "Upload your
files →". This drives the first upload — banner is the most likely
place a CA who just opened a fresh tenant lands.

**Dismissibility:** banner is NOT dismissible. Always-on awareness is
the point.

**Layout:** a single horizontal row, 32px tall, sits between the navbar
and the page content. Color-coded background tint matching severity
(subtle).

---

## Requirement 6: All freshness logic flows through UploadChecks

The existing `StockPlan.Ingestion.UploadChecks` module already
produces nudges and readiness status after upload. Extend it — don't
introduce a parallel `FreshnessChecks` module — so the same nudge
shape is used everywhere and the banner has one source of truth.

New nudge codes added to UploadChecks:
- `:past_due_vests`
- `:gl_missing_for_year`
- `:appraisal_grant_likely`

The banner queries UploadChecks on mount and re-evaluates on each
`{:ingestion_done, _}` PubSub message (the existing upload-completed
broadcast).

---

## Out of scope

- Automated E*Trade API integration — these checks only operate on
  what's already in the local DB.
- Push notifications, email reminders, calendar entries.
- ML-based pattern detection — only the simple heuristics above.
- Multi-user / shared dashboards (still single-tenant).
- Persisting "user dismissed this nudge until tomorrow" state — every
  nudge is computed fresh on each page load.
- Detecting stock splits / corporate actions / ticker changes
  (out of scope for this milestone; multi-symbol M22 handles tickers).

---

## Definition of Done

- [ ] User who has already uploaded files no longer sees the welcome /
  guide page on relaunch; lands on `/portfolio`.
- [ ] Vesting check, sales check, appraisal check all produce nudges
  via `UploadChecks.check/1`.
- [ ] Sticky banner renders on Portfolio, Tax Centre, Sell Advisor,
  History, with last-upload age + severity dot.
- [ ] Banner hover shows the active nudges; click goes to `/upload`.
- [ ] Banner re-evaluates after each ingestion.
- [ ] `mix compile` 0 warnings, `mix test` all pass + new fixtures.
