# Design: Upload Checks Redesign (BH Metadata)

## Overview

Three independent changes:

1. **BH snapshot**: new column on `stock_plan_ingestions`, computed post-Phase-1.
2. **UploadChecks rewrite**: aggregate BH snapshots, apply per-FY G&L rules, fix portfolio readiness.
3. **Portfolio BH fallback removal**: `Portfolio.build` becomes Holdings-only.

---

## 1. BH Snapshot Column

### Migration

```
add_bh_snapshot_json_to_ingestions.exs
```

```elixir
alter table(:stock_plan_ingestions) do
  add :bh_snapshot_json, :text, null: true
end
```

No index needed — accessed by `ingestion_id` PK lookup only.

### Schema field

`StockPlan.Schema.Ingestion`:
```elixir
field :bh_snapshot_json, :string
```

Serialised form (TEXT in SQLite):
```json
{
  "vested_unsold_origin_count": 5,
  "unvested_count": 10,
  "sale_years": [2021, 2022, 2024, 2025]
}
```

All fields are always present. Empty BH with no vested tranches: `{"vested_unsold_origin_count": 0, "unvested_count": 0, "sale_years": []}`.

### Snapshot computation

New private function in `StockPlan.Ingestions`.

**Key design decision — origin-level sold, not SaleAllocation:**
RSU Phase 1 creates `Sale` records for BH SELL events but does NOT create `SaleAllocation`
records — there is no lot-level linkage in BH for RSU (only G&L provides that). ESPP Phase 1
does create allocations (parent-child structure in BH makes the lot unambiguous), but using
`Sale.total_quantity` at the origin level is simpler and correct for both plan types.
`SaleAllocation` is NOT used here.

```elixir
defp compute_bh_snapshot(ingestion_id) do
  # Sum vested net_quantity per origin
  vested_by_origin = Repo.all(
    from t in Tranche,
      join: o in Origin, on: t.origin_id == o.id,
      where: o.ingestion_id == ^ingestion_id and t.status == "VESTED",
      select: {o.id, t.net_quantity})

  origin_vested =
    vested_by_origin
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {oid, qtys} ->
      {oid, Enum.reduce(qtys, Decimal.new(0), fn q, acc ->
        if q, do: Decimal.add(acc, q), else: acc
      end)}
    end)

  origin_ids = Map.keys(origin_vested)

  # Origin-level sold from BH Sale records
  sold_by_origin = Repo.all(
    from s in Sale,
      join: o in Origin, on: s.origin_id == o.id,
      where: o.ingestion_id == ^ingestion_id,
      select: {s.origin_id, s.total_quantity})
  |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  |> Map.new(fn {oid, qtys} ->
    {oid, Enum.reduce(qtys, Decimal.new(0), fn q, acc ->
      if q, do: Decimal.add(acc, q), else: acc
    end)}
  end)

  # Count origins with unsold vested shares
  vested_unsold_origin_count = Enum.count(origin_ids, fn oid ->
    vested = origin_vested[oid] || Decimal.new(0)
    sold   = sold_by_origin[oid] || Decimal.new(0)
    Decimal.gt?(vested, sold)
  end)

  # Unvested tranche count
  unvested_count = Repo.aggregate(
    from(t in Tranche,
      join: o in Origin, on: t.origin_id == o.id,
      where: o.ingestion_id == ^ingestion_id and t.status == "UNVESTED"),
    :count) || 0

  # Calendar years with BH sale events
  sale_years = Repo.all(
    from s in Sale,
      join: o in Origin, on: s.origin_id == o.id,
      where: o.ingestion_id == ^ingestion_id,
      distinct: true,
      select: fragment("strftime('%Y', ?)", s.sale_date))
  |> Enum.reject(&is_nil/1)
  |> Enum.map(&String.to_integer/1)
  |> Enum.sort()

  Jason.encode!(%{
    vested_unsold_origin_count: vested_unsold_origin_count,
    unvested_count: unvested_count,
    sale_years: sale_years
  })
end
```

### When to call

At the end of `Ingestions.ingest_benefit_history/2`, after the silver builder Phase 1 completes and before returning `{:ok, ingestion}`:

```elixir
snapshot = compute_bh_snapshot(ingestion.ingestion_id)
ingestion
|> Ecto.Changeset.change(bh_snapshot_json: snapshot)
|> Repo.update!()
```

No snapshot for HOLDINGS or GL_EXPANDED ingestions — field stays null.

---

## 2. UploadChecks Rewrite

### BH snapshot aggregation helper

```elixir
defp load_bh_snapshots(account_id) do
  Repo.all(
    from i in Ingestion,
    where: i.account_id == ^account_id and i.status == "ACTIVE"
          and i.category == "BENEFIT_HISTORY"
          and not is_nil(i.bh_snapshot_json),
    select: i.bh_snapshot_json)
  |> Enum.map(&Jason.decode!/1)
end

defp aggregate_snapshots(snapshots) do
  vested_unsold_origins = Enum.sum(Enum.map(snapshots, & &1["vested_unsold_origin_count"]))
  unvested              = Enum.sum(Enum.map(snapshots, & &1["unvested_count"]))
  sale_years            = snapshots |> Enum.flat_map(& &1["sale_years"]) |> Enum.uniq() |> Enum.sort()
  %{vested_unsold_origins: vested_unsold_origins, unvested: unvested, sale_years: sale_years}
end
```

### check/1 flow

```elixir
def check(account_id) do
  has_bh      = ...   # ingestion category == "BENEFIT_HISTORY"
  has_holdings = ...  # ingestion category == "HOLDINGS"
  snapshots = if has_bh, do: load_bh_snapshots(account_id), else: []
  bh = aggregate_snapshots(snapshots)

  has_current_shares = bh.vested_unsold_origins > 0 or bh.unvested > 0

  # G&L: date-based coverage check against actual BH sale event dates
  gl_coverage = if has_bh, do: compute_gl_coverage_gaps(account_id), else: %{uncovered_cy1: [], uncovered_cy: []}

  nudges = []
    |> maybe_add_no_bh(has_bh)
    |> maybe_add_no_holdings(has_bh, has_current_shares, has_holdings)
    |> add_gl_coverage_nudges(gl_coverage)
    |> add_symbol_nudges(account_id, bh_symbols_with_unsold(snapshots))

  readiness = build_readiness(has_bh, has_current_shares, has_holdings, gl_coverage)
  %{nudges: nudges, readiness: readiness}
end
```

### `compute_gl_coverage_gaps/1`

G&L coverage is date-based. A BH sale date is "covered" when a GL allocation exists for that
sale in `stock_plan_sale_allocations` with `sale_price NOT NULL`. (Nil `sale_price` marks a
BH-phase placeholder allocation created during Phase 1 — not a confirmed GL coverage.)

```elixir
defp compute_gl_coverage_gaps(account_id) do
  today     = Date.utc_today()
  cy1_start = Date.new!(today.year - 1, 1, 1)
  cy1_end   = Date.new!(today.year - 1, 12, 31)
  cy_start  = Date.new!(today.year, 1, 1)

  # All BH sales within the relevant window (CY-1 and CY)
  bh_sales = Repo.all(
    from s in Sale,
      where: s.account_id == ^account_id
             and s.sale_date >= ^cy1_start
             and s.sale_date <= ^today,
      select: {s.id, s.sale_date})

  if bh_sales == [] do
    %{uncovered_cy1: [], uncovered_cy: []}
  else
    sale_ids = Enum.map(bh_sales, &elem(&1, 0))

    # Sales that have at least one GL-confirmed allocation (sale_price present)
    covered_ids =
      Repo.all(
        from a in SaleAllocation,
          where: a.sale_id in ^sale_ids and not is_nil(a.sale_price),
          distinct: true,
          select: a.sale_id)
      |> MapSet.new()

    uncovered = Enum.reject(bh_sales, fn {id, _} -> MapSet.member?(covered_ids, id) end)

    %{
      uncovered_cy1: for({id, d} <- uncovered, Date.compare(d, cy1_start) != :lt and Date.compare(d, cy1_end) != :gt, do: {id, d}),
      uncovered_cy:  for({id, d} <- uncovered, Date.compare(d, cy_start) != :lt, do: {id, d})
    }
  end
end
```

### Nudge changes

**Remove** the current global `:no_gl` nudge and the year-based `:gl_coverage_gap` nudge.
**Replace** with `:no_gl_for_dates` nudges — one for CY-1 (warning) and one for CY (info):

```elixir
defp add_gl_coverage_nudges(nudges, %{uncovered_cy1: cy1, uncovered_cy: cy}) do
  nudges
  |> add_cy1_gl_nudge(cy1)
  |> add_cy_gl_nudge(cy)
end

defp add_cy1_gl_nudge(nudges, []), do: nudges
defp add_cy1_gl_nudge(nudges, uncovered) do
  dates   = Enum.map(uncovered, &elem(&1, 1)) |> Enum.sort(Date)
  year    = hd(dates).year
  earliest = hd(dates)
  latest   = List.last(dates)
  [%{
    severity: :warning,
    code: :no_gl_for_dates,
    reason: "G&L missing for #{length(uncovered)} sale event(s) in #{year}",
    impact: "Capital Gains, Schedule FSI, and Schedule FA for #{year} cannot be computed",
    action: "Download G&L Expanded from E*Trade covering #{earliest} to #{latest}"
  } | nudges]
end

defp add_cy_gl_nudge(nudges, []), do: nudges
defp add_cy_gl_nudge(nudges, uncovered) do
  dates    = Enum.map(uncovered, &elem(&1, 1)) |> Enum.sort(Date)
  year     = hd(dates).year
  earliest = hd(dates)
  latest   = List.last(dates)
  [%{
    severity: :info,
    code: :no_gl_for_dates,
    reason: "G&L not yet uploaded for #{length(uncovered)} sale event(s) in #{year}",
    impact: "Capital Gains for #{year} cannot be computed yet",
    action: "Download G&L Expanded from E*Trade covering #{earliest} to #{latest}"
  } | nudges]
end
```

### Readiness: portfolio

```elixir
defp readiness_portfolio(false, _has_current_shares, _has_holdings), do: :blocked
defp readiness_portfolio(true, false, _has_holdings), do: :not_applicable  # fully exited — nothing to show
defp readiness_portfolio(true, true, false), do: :blocked   # mandatory — not uploaded
defp readiness_portfolio(true, true, true), do: :ready
```

`:limited` is removed for Portfolio. `:not_applicable` (grey "N/A" badge) means the user has
fully exited all positions — distinct from `:blocked` (red "Blocked") which means a required
upload is missing.

### Readiness: Capital Gains / Schedule FSI

```elixir
defp readiness_capital_gains(has_bh, gl_coverage) do
  cond do
    not has_bh                          -> :blocked
    gl_coverage.uncovered_cy1 != []     -> :blocked   # CY-1 sales have no GL coverage
    true                                -> :ready
  end
end
```

CY uncovered sales produce only an `:info` nudge — not a readiness block (year in progress).

### Readiness: Schedule FA

```elixir
defp readiness_schedule_fa(has_bh, has_current_shares, has_holdings, gl_coverage) do
  cond do
    not has_bh                          -> :blocked
    gl_coverage.uncovered_cy1 != []     -> :blocked
    has_current_shares and not has_holdings -> :limited   # Holdings improves FA accuracy
    true                                -> :ready
  end
end
```

---

## 3. Portfolio BH Fallback Removal

### `Portfolio.build/1`

Remove the `if has_holdings_ingestion?` branch. After this change:

```elixir
def build(account_id) do
  build_from_holdings(account_id)
end
```

`build_from_holdings` already returns `%{"ESPP" => [], "RSU" => []}` when no Holdings ingestion
exists. No data-returning fallback.

Delete `build_from_bh/1`, `build_bh_holding_row/3`, `origin_sold_map`, `origin_vested_map`,
`fully_sold_origins` — all are BH fallback internals.

### Portfolio page state machine

In `PortfolioLive.mount/3`, derive `portfolio_state` from ingestion presence + BH snapshot:

```elixir
has_bh = Ingestions.any_active_bh?(account_id)
has_holdings = Ingestions.has_active_holdings?(account_id)
bh_has_current_shares = has_bh and Ingestions.bh_has_current_shares?(account_id)

portfolio_state =
  cond do
    not has_bh                         -> :no_data
    not bh_has_current_shares          -> :all_sold
    not has_holdings                   -> :holdings_required
    true                               -> :active
  end
```

Add `Ingestions.bh_has_current_shares?/1`:
```elixir
def bh_has_current_shares?(account_id) do
  Repo.exists?(
    from i in Ingestion,
    where: i.account_id == ^account_id and i.status == "ACTIVE"
          and i.category == "BENEFIT_HISTORY"
          and fragment("json_extract(?, '$.vested_unsold_origin_count')", i.bh_snapshot_json) > 0
          or fragment("json_extract(?, '$.unvested_count')", i.bh_snapshot_json) > 0
  )
end
```

In the Portfolio template, render state-specific banners before the tab content:

| State | Banner |
|---|---|
| `:no_data` | "Upload a Benefit History file to get started" |
| `:all_sold` | "All positions appear to be sold — see History for your transaction record" |
| `:holdings_required` | "Upload a Holdings (ByBenefitType) file to view your portfolio" |
| `:active` | (no banner — render normal content) |

---

## Invariants

- BH snapshot is populated for every ACTIVE BH ingestion that completes Phase 1 successfully.
  Partial build (exception mid-Phase-1) leaves snapshot null — treated as legacy/missing for checks.
- Snapshot reflects the state of Silver AT THE TIME OF INGEST. Re-uploading BH replaces the
  old ingestion (archived) and creates a new ingestion with a fresh snapshot.
- Portfolio readiness `:limited` no longer exists as a state for Portfolio. Existing tests that
  assert `:limited` for portfolio must be updated to `:blocked`.

## 4. Phase 1 ESPP Allocation Removal

**File:** `lib/stock_plan/ingestion/silver_builder.ex`, `process_espp/2`

In the sell events reduce inside `process_espp`, replace the current block:

```elixir
# BEFORE
yahoo_price = try do
  StockPlan.StockPrice.get_close(symbol, sale_date)
rescue
  e -> Logger.warning(...); nil
end

proceeds = if yahoo_price && qty, do: ..., else: nil

sale = insert_sale!(ing, origin, %{
  sale_date: sale_date,
  total_quantity: qty,
  sale_price: yahoo_price,
  proceeds: proceeds
})

create_gl_allocation(sale, tranche, qty, yahoo_price, nil)
{sc2 + 1, ac2 + 1}
```

With:

```elixir
# AFTER
insert_sale!(ing, origin, %{
  sale_date: sale_date,
  total_quantity: qty
})
{sc2 + 1, ac2}
```

Remove the `alloc_count` (`ac2`) accumulator from the inner reduce entirely — ESPP Phase 1
never creates allocations. Remove `alloc_count` from `process_espp` return counts (`ac` in the
outer reduce). The `allocations` field in the count accumulator can remain at 0.

**G&L phase 2 is unchanged.** `create_gl_allocation/5` for ESPP still finds the matching `Sale`
by origin + date + quantity and creates the allocation with confirmed price. The delete-then-insert
guard inside `create_gl_allocation` becomes a no-op (no placeholder to delete) but is harmless.

---

## Backfill transition

After the migration is deployed, existing ACTIVE BH ingestions will have `bh_snapshot_json = null`.
`load_bh_snapshots/1` filters on `not is_nil(bh_snapshot_json)`, so legacy ingestions yield an
empty snapshot list even though `has_bh = true`.

**Handling in `check/1`:**

```elixir
snapshots = if has_bh, do: load_bh_snapshots(account_id), else: []
bh = aggregate_snapshots(snapshots)
legacy_bh = has_bh and snapshots == []
```

When `legacy_bh = true`:
- Skip G&L coverage check (no sale_years available)
- Skip Holdings requirement check (cannot evaluate share state)
- Emit `:bh_snapshot_missing` info nudge: "Re-upload your Benefit History to unlock accurate
  readiness checks"
- Portfolio readiness: `:blocked` (BH present but share state unknown; `:limited` is not a valid
  Portfolio state — the `:bh_snapshot_missing` nudge already explains the situation)

This is a one-time degraded state. Once the user re-uploads BH, the snapshot is populated and
normal logic applies. No automated backfill or migration of Silver data is needed.

---

## Files Affected

| File | Change |
|---|---|
| `priv/repo/migrations/YYYYMMDDNNNNNN_add_bh_snapshot_json.exs` | New migration |
| `lib/stock_plan/schema/ingestion.ex` | Add `:bh_snapshot_json` field |
| `lib/stock_plan/ingestions.ex` | `compute_bh_snapshot/1`, `bh_has_current_shares?/1`, `has_active_holdings?/1` |
| `lib/stock_plan/ingestion/upload_checks.ex` | Full rewrite per design above |
| `lib/stock_plan/portfolio.ex` | Remove `build_from_bh` and internals |
| `lib/stock_plan_web/live/portfolio_live.ex` | Portfolio state machine + state banners |
| `test/stock_plan/ingestion/upload_checks_test.exs` | Update to new nudge codes + readiness |
| `test/stock_plan/portfolio_test.exs` | Remove BH fallback test cases |
