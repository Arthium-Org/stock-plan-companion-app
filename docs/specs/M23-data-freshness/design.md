# Design: M23 — Data Freshness Detection & Re-upload Nudges

## Approach

Mostly an extension of existing modules. No new tables, no migrations,
no schema change.

1. Three new checks added to `StockPlan.Ingestion.UploadChecks`.
2. New `StockPlan.Ingestion.UploadChecks.banner_summary/1` that returns
   the data the sticky banner needs (last upload time + severity).
3. New `<.upload_state_banner>` LiveView component rendered in the
   root layout for pages that need it.
4. Routing tweak in `HomeLive.mount/3` to skip the guide when data is
   present.
5. New PubSub topic / payload only if existing one isn't already
   sufficient (check first — re-use is preferred).

---

## Module changes

### `StockPlan.Ingestion.UploadChecks`

Existing API (today):
```elixir
@spec check(account_id :: String.t()) :: %{
  nudges: [nudge()],
  readiness: readiness()
}
```

Add:
```elixir
@spec banner_summary(account_id :: String.t()) :: %{
  last_upload_at: DateTime.t() | nil,
  age_phrase: String.t(),       # "2 days ago" / "today" / "3 weeks ago"
  severity: :ok | :info | :warning | :error,
  nudge_count: non_neg_integer()
}
```

Add three new nudge producers inside `check/1`:
- `check_past_due_vests/1`
- `check_gl_coverage/1`
- `check_appraisal_grant_pattern/1`

Internal structure stays the same — just more entries appended to the
existing nudge list.

### New nudge codes

```elixir
@type code ::
  | :past_due_vests
  | :gl_missing_for_year
  | :appraisal_grant_likely
  | ...existing codes
```

Severity assignment:
- `:past_due_vests` → `:warning`
- `:gl_missing_for_year` → `:warning` (current FY) or `:error` (vital tax filing year)
- `:appraisal_grant_likely` → `:info`

The banner's overall severity = max severity of any nudge produced by
`check/1`, with `:ok` if there are no nudges.

---

## Detection algorithms

### 1. Possibly-due vests (timezone- and grace-aware)

```elixir
@grace_days 3

defp check_past_due_vests(account_id) do
  cutoff = eastern_today() |> Date.add(-@grace_days)

  count =
    from(t in Tranche,
      join: i in Ingestion, on: i.ingestion_id == t.ingestion_id,
      where: i.account_id == ^account_id and i.status == "ACTIVE",
      where: t.status == "UNVESTED" and t.vest_date <= ^cutoff,
      select: count(t.id))
    |> Repo.one() || 0

  if count > 0 do
    [%{
      severity: :warning,
      code: :past_due_vests,
      reason: "#{count} tranche(s) had scheduled vest dates on or before #{Date.to_string(cutoff)}",
      impact: "If these have vested at the broker, Vesting Schedule and Portfolio may be stale",
      action: "Check at E*Trade; if vested, upload fresh Benefit History and Holdings",
      metadata: %{cutoff_date: cutoff, count: count}
    }]
  else
    []
  end
end

defp eastern_today do
  # America/New_York handles DST correctly
  DateTime.now!("America/New_York") |> DateTime.to_date()
end
```

**Why eastern_today and grace_days:**
- E*Trade processes vests during US business hours. A user in IST
  checking at 10am could see `vest_date = yesterday` while the broker
  is still mid-day yesterday Eastern — the vest may not have run yet.
- Weekends + US bank holidays + broker delays routinely shift actual
  vest execution by 1-3 business days from the scheduled date.
- A 3-day grace eliminates the noisy near-the-boundary cases.

**Why this is NOT replaced with a "timeline freshness" lookup
(per GPT feedback):** `tranche.status` IS the timeline state after
Silver rebuild. The current logic correctly identifies tranches whose
scheduled date has passed but whose status hasn't transitioned to
VESTED — exactly the case where the user might need to upload fresh
data. What changed is the **framing**: this is not "data is stale" — it
is "the schedule date passed, please verify at the broker." The
softer language is what GPT was rightly worried about (false
confidence in data state); the underlying query is correct.

Requires `Tzdata` for timezone resolution. If not yet in deps,
add it (one line in `mix.exs`). For dev/test without timezone DB,
fall back to UTC and document.

### 2. G&L coverage for sale years

```elixir
defp check_gl_coverage(account_id) do
  # Distinct calendar years with sales recorded
  sale_years =
    from(s in Sale,
      join: i in Ingestion, on: i.ingestion_id == s.ingestion_id,
      where: i.account_id == ^account_id and i.status == "ACTIVE",
      where: not is_nil(s.sale_date),
      select: fragment("strftime('%Y', ?)", s.sale_date),
      distinct: true)
    |> Repo.all()
    |> Enum.map(&String.to_integer/1)

  # Years with G&L coverage
  gl_years =
    from(i in Ingestion,
      where: i.account_id == ^account_id and i.category == "GL_EXPANDED" and i.status == "ACTIVE",
      select: i.metadata_json)
    |> Repo.all()
    |> Enum.flat_map(&extract_gl_year/1)
    |> Enum.uniq()

  missing = sale_years -- gl_years
  current_fy = current_fy_year()

  for year <- Enum.sort(missing) do
    severity = if year == current_fy, do: :warning, else: :error

    %{
      severity: severity,
      code: :gl_missing_for_year,
      reason: "Sales found in FY #{year}, no G&L Expanded uploaded",
      impact: "Capital Gains and Schedule FA for #{year} cannot be computed",
      action: "Download G&L Expanded for #{year} from E*Trade and upload",
      metadata: %{year: year}
    }
  end
end

# India FY runs Apr-Mar; US tax CY = calendar year. Pick one — we use
# India FY here since Schedule FA filing is the primary use case.
defp current_fy_year do
  today = Date.utc_today()
  if today.month >= 4, do: today.year, else: today.year - 1
end
```

`extract_gl_year/1` parses the G&L ingestion's stored year metadata
(set during ingestion from filename or sheet content; check current
ingestion code for the field name).

### 3. Appraisal-cycle grant heuristic (±1 month window)

```elixir
defp check_appraisal_grant_pattern(account_id) do
  rsu_grants =
    from(o in Origin,
      join: i in Ingestion, on: i.ingestion_id == o.ingestion_id,
      where: i.account_id == ^account_id and i.status == "ACTIVE",
      where: o.plan_type == "RSU",
      select: o.origin_date)
    |> Repo.all()

  case dominant_cluster_with_window(rsu_grants) do
    {anchor_month, cluster_dates} when length(cluster_dates) >= 2 ->
      most_recent = Enum.max(cluster_dates, Date)
      days_since = Date.diff(Date.utc_today(), most_recent)

      cond do
        days_since < 365 ->
          []

        has_grant_in_cluster_window?(rsu_grants, anchor_month, Date.utc_today().year) ->
          []

        true ->
          [%{
            severity: :info,
            code: :appraisal_grant_likely,
            reason: "Your appraisal-cycle grants typically land around #{month_name(anchor_month)}.",
            impact: "If a new grant was issued this cycle, the app may be missing it",
            action: "Upload latest Benefit History to capture any new grant",
            metadata: %{anchor_month: anchor_month}
          }]
      end

    _ ->
      []
  end
end

# Cluster grants by ±1 month window around each candidate anchor month;
# return the anchor with the most dates in its window.
# Tie-breaker: most recent qualifying cluster wins — when two clusters
# have the same count, the user's current cycle is the more recent one
# (e.g., they switched employer / appraisal cycle).
defp dominant_cluster_with_window([]), do: nil
defp dominant_cluster_with_window(dates) do
  1..12
  |> Enum.map(fn anchor ->
    in_window = Enum.filter(dates, fn d -> month_distance(d.month, anchor) <= 1 end)
    {anchor, in_window}
  end)
  |> Enum.filter(fn {_anchor, dates} -> length(dates) >= 2 end)
  |> case do
    [] ->
      nil

    candidates ->
      # Sort by (count desc, most_recent_date desc). The compound key
      # makes the tie-breaker deterministic.
      candidates
      |> Enum.sort_by(fn {_anchor, dates} ->
        most_recent = Enum.max(dates, Date)
        {-length(dates), Date.to_erl(most_recent) |> :calendar.date_to_gregorian_days() |> Kernel.-()}
      end)
      |> List.first()
  end
end

# 1-2 = 1, 12-1 = 1 (year wrap), 1-3 = 2, 12-2 = 2, etc.
defp month_distance(a, b) do
  diff = abs(a - b)
  min(diff, 12 - diff)
end

defp has_grant_in_cluster_window?(grants, anchor_month, year) do
  Enum.any?(grants, fn d ->
    d.year == year and month_distance(d.month, anchor_month) <= 1
  end)
end
```

**Why ±1 window over top-2 clusters (per GPT feedback):** top-2
risks double-nudging the same appraisal cycle (e.g., a company that
issues some grants in March and some in April for the same cycle —
top-2 would produce both a March and April nudge for the same
real-world event). The ±1 window collapses them into one cluster
identified by the most popular anchor month.

**Why only one nudge (not iterating all clusters):** appraisal cycle
nudging is informational; multiple appraisal nudges would clutter
the banner. The dominant cluster captures the user's primary cycle.
If a user has a genuine second cycle (rare), a follow-up milestone
can extend.

### Banner summary — per-category freshness

```elixir
@spec banner_summary(String.t()) :: map()
def banner_summary(account_id) do
  freshness = freshness_by_category(account_id)
  %{nudges: nudges} = check(account_id)

  bottleneck = oldest_required_category(freshness)
  severity = compute_severity(freshness, nudges)
  primary_action = compute_primary_action(freshness, nudges)

  %{
    freshness_basis: %{
      category: bottleneck.category,
      uploaded_at: bottleneck.uploaded_at
    },
    age_phrase: bottleneck_age_phrase(bottleneck),
    severity: severity,
    nudge_count: length(nudges),
    primary_action: primary_action
  }
end

# Latest ACTIVE ingestion per category. nil if category never uploaded.
defp freshness_by_category(account_id) do
  [
    {:benefit_history, "BENEFIT_HISTORY", true},
    {:holdings,        "HOLDINGS",        true},
    {:gl_expanded,     "GL_EXPANDED",     false}  # G&L: optional for some users
  ]
  |> Enum.map(fn {atom, db_cat, required?} ->
    inserted_at =
      from(i in Ingestion,
        where: i.account_id == ^account_id and i.status == "ACTIVE" and i.category == ^db_cat,
        order_by: [desc: i.inserted_at],
        limit: 1,
        select: i.inserted_at)
      |> Repo.one()

    %{category: atom, uploaded_at: inserted_at, required: required?}
  end)
end

# The bottleneck = the required category whose latest upload is oldest.
# If a required category has never been uploaded, that's the bottleneck.
defp oldest_required_category(freshness) do
  required = Enum.filter(freshness, & &1.required)
  case Enum.find(required, &is_nil(&1.uploaded_at)) do
    nil ->
      Enum.min_by(required, fn %{uploaded_at: t} -> DateTime.to_unix(t) end)
    missing ->
      missing
  end
end

defp compute_severity(freshness, nudges) do
  required_missing? = Enum.any?(freshness, fn f -> f.required and is_nil(f.uploaded_at) end)

  cond do
    required_missing?                                  -> :error
    Enum.any?(nudges, &(&1.severity == :error))        -> :error
    Enum.any?(nudges, &(&1.severity == :warning))      -> :warning
    Enum.any?(nudges, &(&1.severity == :info))         -> :info
    true                                               -> :ok
  end
end

# Severity precedence (explicit so reviewers don't miss it):
#
#   1. Required dataset missing (BH or Holdings has zero ACTIVE rows ever)  → :error
#   2. Any nudge of severity :error                                          → :error
#   3. Any nudge of severity :warning                                        → :warning
#   4. Any nudge of severity :info                                           → :info
#   5. Otherwise                                                             → :ok
#
# The first branch (required missing) outranks even an empty nudge list — a
# fresh install with no data should show a red banner even though no
# nudges have fired yet. This matches the empty-state decision in
# requirements R5.

# Derive a specific call-to-action from the highest-severity nudge,
# or "Upload your files →" / "All good" for the boundary cases.
defp compute_primary_action(freshness, nudges) do
  cond do
    Enum.empty?(freshness |> Enum.filter(& &1.uploaded_at)) ->
      "Upload your files →"

    missing = Enum.find(freshness, fn f -> f.required and is_nil(f.uploaded_at) end) ->
      "Upload #{category_label(missing.category)} to unblock features →"

    top = highest_severity_nudge(nudges) ->
      nudge_to_action(top)

    true ->
      "All good"
  end
end

defp bottleneck_age_phrase(%{uploaded_at: nil, category: cat}),
  do: "No #{category_label(cat)} uploaded yet"

defp bottleneck_age_phrase(%{uploaded_at: dt, category: cat}) do
  "#{category_label(cat)} — #{age_phrase(dt)}"
end

defp category_label(:benefit_history), do: "Benefit History"
defp category_label(:holdings),        do: "Holdings"
defp category_label(:gl_expanded),     do: "G&L Expanded"

defp age_phrase(%DateTime{} = dt) do
  case Date.diff(Date.utc_today(), DateTime.to_date(dt)) do
    0 -> "today"
    1 -> "yesterday"
    n when n < 7 -> "#{n} days ago"
    n when n < 31 -> "#{div(n, 7)} weeks ago"
    n when n < 365 -> "#{div(n, 30)} months ago"
    n -> "#{div(n, 365)} years ago"
  end
end
```

**Why per-category, not global latest (per GPT feedback):** a user who
uploaded G&L today but Holdings 6 months ago would see "Updated today"
under the old design — falsely reassuring. The bottleneck approach
surfaces the oldest required dataset and identifies it by name in the
phrase, so the user knows exactly which file is stale.

**Empty state — no ingestions at all:** banner severity is `:error`,
age phrase is "No data uploaded yet", primary action is "Upload your
files →". This was flagged as a design decision in the earlier test
plan; now committed.

---

## Banner component

Update existing function `StockPlanWeb.Layouts.upload_banner/1` (added
in V1.4) to consume the richer `banner_summary` map.

```elixir
attr :summary, :map, required: true

def upload_banner(assigns) do
  ~H"""
  <a
    href="/upload"
    class={"flex items-center justify-between gap-3 px-4 py-1.5 text-sm " <> severity_bg(@summary.severity)}
    role="status"
  >
    <span class="flex items-center gap-2 min-w-0">
      <span class={"inline-block w-2 h-2 rounded-full shrink-0 " <> dot_class(@summary.severity)}></span>
      <span class="truncate">{@summary.age_phrase}</span>
      <%= if @summary.nudge_count > 0 do %>
        <span class={"badge badge-xs shrink-0 " <> badge_class(@summary.severity)}>
          {@summary.nudge_count}
        </span>
      <% end %>
    </span>
    <span class="text-xs opacity-80 shrink-0">{@summary.primary_action}</span>
  </a>
  """
end
```

The whole banner is the click target → `/upload`. No hover popover —
the `primary_action` text on the right already gives direction. If
hover detail becomes valuable later, add as a follow-up.

### Where the banner is mounted

Add to the root layout (`root.html.heex`) so it appears on every page
under the browser pipeline. Conditional render: hide on the welcome
screen (`/` when no profile) and on the upload page itself (where
nudges are already shown inline).

Banner data flow:
- The root layout doesn't have LiveView state. So either:
  1. Each LiveView assigns `@upload_banner` in its mount; root layout
     renders it.
  2. Use a hook LiveView in the layout that subscribes to PubSub and
     re-fetches summary on each ingestion broadcast.

Option 1 is simpler. Each LiveView calls
`UploadChecks.banner_summary(@account_id)` in `mount/3` and assigns
to `:upload_banner`. The root layout pulls from `@upload_banner` (or
falls back to nil if not set — render nothing).

A small `assign_upload_banner/1` helper in `StockPlanWeb`'s LiveView
helper module avoids duplication.

---

## HomeLive routing tweak

```elixir
def mount(_params, _session, socket) do
  profile = load_profile()
  cond do
    is_nil(profile) ->
      {:ok, socket |> assign(step: :welcome) |> ...}

    has_ingestions?(@account_id) ->
      {:ok, push_navigate(socket, to: "/portfolio")}

    true ->
      {:ok, socket |> assign(step: :guide, profile: profile) |> ...}
  end
end
```

`has_ingestions?/1` is a 1-query check:
```elixir
defp has_ingestions?(account_id) do
  Repo.exists?(
    from i in Ingestion,
      where: i.account_id == ^account_id and i.status == "ACTIVE"
  )
end
```

This is < 1ms in SQLite. No caching needed.

---

## Performance / cost

All checks combined: ≤ 4 small indexed queries against tables with
at most a few thousand rows. UploadChecks already runs on every page
load via the nudge panel (where present). Adding banner_summary
adds one more lightweight query (`latest_ingestion_inserted_at`).
Aggregate cost: <10ms on any realistic dataset.

Cache option, if pages get noticeably slower:
- Memoize via `:persistent_term`, key = `{account_id, max_ingestion_id}`.
- Invalidate when any new ingestion happens.

Skip caching for v1 unless metrics show a need.

---

## Open questions

1. **G&L year metadata** — verify which field on the Ingestion row
   stores the G&L's calendar year. Today, the parser stamps it
   somewhere in `metadata_json`. Confirm the key before relying on it.
2. **Banner color choice** — green/yellow/red is the obvious mapping
   but might clash with DaisyUI's existing alert classes. Use the
   project's existing `badge-success/-warning/-error` palette for
   consistency.
3. **Single banner for both Mac and Windows builds** — yes; the banner
   is web UI, runs identically wherever the BEAM is running.
4. **Welcome → Portfolio redirect: is the existing profile creation
   flow ever re-entered?** No (profile is set once). The redirect is
   safe to apply unconditionally.
