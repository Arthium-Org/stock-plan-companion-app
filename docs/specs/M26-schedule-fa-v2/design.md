# Design: M26 — Schedule FA v2

## Architecture

```
Before (M14/M21):
  ScheduleFA.build
    → TrancheTimeline.build
    → validate_cy_coverage (CY-only RSU dates)
    → held_during_cy (net_qty − sells formula + holdings override)
    → build_fa_rows

After (M26):
  ScheduleFA.build
    → P1: check_gl_coverage_for_fa_year/3  ← direct query, no timelines
    → P2: check_holdings_available/2       ← direct DB query, no timelines
    → TrancheTimeline.build                ← runs AFTER P2; holdings_qty = match || 0
    → compute_cy_state/2 (Rules 1–3)
    → exclude start_count == 0
    → build_fa_rows_from_state/2
    → aggregate_by_date
```

### Why P1/P2 must precede TrancheTimeline.build

The previous spec had `TrancheTimeline.build → P1 → P2`. The concrete reason: Cursor's
accepted recommendation was "M21 `TrancheTimeline` unchanged: ✅ Aligned." To detect
whether Holdings were uploaded, P2 was written as:

```elixir
has_holdings = Enum.any?(timelines, &(&1.holdings_qty != nil))
```

`timelines` comes from `TrancheTimeline.build`, so P2 was forced to run after it. The spec
architecture diagram captured this dependency, locking in the wrong sequence.

**The fix:** Check Holdings via direct DB query — `Repo.exists?(from h in Holding, where:
h.account_id == ^account_id)` — no timelines needed. P1/P2 can run first; if they pass,
`TrancheTimeline.build` runs knowing it can safely set `holdings_qty = match || 0`.

`TrancheTimeline.held_during_cy/2` is **retired from the FA path**. It may remain for
History/diagnostics.

---

## `ScheduleFA.build/2`

```elixir
def build(account_id, calendar_year) do
  bh_sales    = load_bh_sales(account_id)
  allocations = load_allocations(account_id)

  with :ok <- check_gl_coverage_for_fa_year(bh_sales, allocations, calendar_year),
       :ok <- check_holdings_available(account_id, bh_sales) do
    {timelines, validation} = TrancheTimeline.build(account_id)

    if timelines == [] do
      {:ok, [], validation.warnings}
    else
      cy_states =
        timelines
        |> compute_cy_state(calendar_year)
        |> Enum.reject(fn s -> Decimal.equal?(s.start_count, Decimal.new(0)) end)

      rows =
        cy_states
        |> build_fa_rows_from_state(calendar_year)
        |> aggregate_by_date()

      case check_meta_coverage(rows) do
        :ok -> {:ok, rows, validation.warnings}
        {:error, missing} -> {:error, {:missing_meta, missing}}
      end
    end
  end
end
```

Both pre-check failures return `{:error, message}` — no timeline construction, no row
construction.

---

## P1: `check_gl_coverage_for_fa_year/3`

Replaces `TrancheTimeline.validate_cy_coverage/3` in the FA path only.

```elixir
defp check_gl_coverage_for_fa_year(bh_sales, allocations, calendar_year) do
  cy_start = Date.new!(calendar_year, 1, 1)

  # All plan types — G&L needed for sale_proceeds_inr regardless of plan type
  gl_dates =
    allocations
    |> Enum.map(& &1.sale_date)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()

  missing =
    bh_sales
    |> Enum.filter(&(Date.compare(&1.sale_date, cy_start) != :lt))
    |> Enum.map(& &1.sale_date)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(gl_dates, &1))
    |> Enum.sort()

  if missing == [] do
    :ok
  else
    dates_str = Enum.map_join(missing, ", ", &Date.to_iso8601/1)

    {:error,
     "G&L missing for sell dates: #{dates_str}. " <>
       "Upload G&L covering sales in or after #{calendar_year}."}
  end
end
```

`TrancheTimeline.validate_cy_coverage/3` is **not deleted** — may be used elsewhere.

---

## P2: `check_holdings_available/2`

**Does not consume timelines.** Uses a direct DB query to detect whether Holdings are
uploaded, then a BH aggregate query if not.

```elixir
defp check_holdings_available(account_id, bh_sales) do
  if holdings_uploaded?(account_id) do
    :ok
  else
    check_origins_resolvable_from_bh(account_id, bh_sales)
  end
end

defp holdings_uploaded?(account_id) do
  Repo.exists?(from h in Holding, where: h.account_id == ^account_id)
end
```

When Holdings are not uploaded, fall back to per-origin BH reconciliation:

```elixir
defp check_origins_resolvable_from_bh(account_id, bh_sales) do
  origins = load_origins_with_tranches(account_id)  # origins with SUM(net_quantity)
  bh_by_origin = Enum.group_by(bh_sales, & &1.origin_id)
  tolerance = Decimal.new(2)

  unresolved =
    Enum.reject(origins, fn {origin_id, total_released} ->
      bh_sold =
        bh_by_origin
        |> Map.get(origin_id, [])
        |> sum_field(:total_quantity)

      Decimal.lt?(Decimal.abs(Decimal.sub(bh_sold, total_released)), tolerance)
    end)

  if unresolved == [] do
    :ok
  else
    grants =
      unresolved
      |> Enum.flat_map(fn {_, ts} -> Enum.map(ts, & &1.grant_number) end)
      |> Enum.uniq()
      |> Enum.join(", ")

    {:error,
     "Holdings unavailable for grants: #{grants}. " <>
       "Upload Holdings (ByBenefitType) or ensure all sales are in Benefit History."}
  end
end
```

---

## TrancheTimeline changes (small)

`match_holding` is updated to return `sellable_qty || Decimal.new(0)`:

```elixir
# Before
holdings_qty = match_holding({grant_number, vest_date})   # nil when not found

# After
holdings_qty = match_holding({grant_number, vest_date}) || Decimal.new(0)
```

`apply_bh_sold_validation_with_holdings` is **removed**. It was added beyond the M21 spec
and introduced the conditional that left `holdings_qty = nil` for tranches with sells but
absent from Holdings. With P2 as a gate (Holdings uploaded or origins fully reconciled via
BH), `match_holding || 0` is always safe: "not in Holdings" means "not currently held".

After this change, `holdings_qty` on every tranche is always a `Decimal`, never `nil`.

**Files changed:** `lib/stock_plan/tax/tranche_timeline.ex` — `match_holding` return,
remove `apply_bh_sold_validation_with_holdings` and its call site.

---

## `compute_cy_state/2`

Single pass over all timelines (RSU + ESPP). `timeline.sells` is populated by
`TrancheTimeline.build/1` for both plan types (G&L for RSU; G&L or BH fallback for ESPP).
`effective_holdings/1` is **unified** — same logic for RSU and ESPP via `holdings_qty`.

```elixir
defp compute_cy_state(timelines, calendar_year) do
  cy_start = Date.new!(calendar_year, 1, 1)
  cy_end   = Date.new!(calendar_year, 12, 31)

  Enum.map(timelines, fn t ->
    cond do
      # Rule 2: vested after CY — excluded
      Date.compare(t.vest_date, cy_end) == :gt ->
        state(t, 0, 0, 0)

      # Rule 1: vested during CY — self-contained, no Holdings needed
      Date.compare(t.vest_date, cy_start) != :lt ->
        cy_sale = sum_sells_in_range(t.sells, cy_start, cy_end)
        state(t, t.net_quantity, Decimal.sub(t.net_quantity, cy_sale), cy_sale)

      # Rule 3: vested before CY — needs Holdings or BH-confirmed zero
      true ->
        cy_sale  = sum_sells_in_range(t.sells, cy_start, cy_end)
        beyond   = sum_sells_after(t.sells, cy_end)
        holdings = effective_holdings(t)
        state(t,
          Decimal.add(Decimal.add(cy_sale, beyond), holdings),
          Decimal.add(beyond, holdings),
          cy_sale)
    end
  end)
end

defp effective_holdings(t), do: t.holdings_qty
```

### Why unified effective_holdings works for ESPP

ESPP tranches in `stock_plan_tranches` are keyed by `{origin_id, vest_date}`. The Holdings
file (ByBenefitType) contains ESPP VESTED rows keyed by `{grant_number, vest_date}` where
`grant_number` = the ESPP enrollment hash and `vest_date` = purchase date — matching the
tranche key exactly.

`match_holding({grant_number, vest_date}) || 0` resolves ESPP lots the same way as RSU:
- Lot in Holdings with `sellable_qty > 0` → `holdings_qty = sellable_qty` (still held)
- Lot not in Holdings → `holdings_qty = 0` (sold out of Holdings)

P2 passes only when Holdings is uploaded OR BH confirms all origins fully exited. Either
way, `holdings_qty = 0` for a lot absent from Holdings is correct — "not in Holdings means
not currently held."

**Rule 1 is self-contained:** only needs `net_quantity` and CY sells — no Holdings, no
beyond-CY sells. `end_count = net_quantity − cy_sale` is correct because for a lot vesting
during CY, all shares started the year as zero (they didn't exist at Jan 1).

**Rule 3 needs Holdings:** pre-CY lots had a balance at Jan 1, reduced by pre-CY sells not
visible in G&L. `holdings_qty` (from Holdings or inferred 0 via P2) is the anchor.

---

## Row builder changes

Rename `build_fa_rows_from_timeline` → `build_fa_rows_from_state`.

| Field | Before | After |
|---|---|---|
| `initial_value_inr` | `cost_basis × held_at_start × vest_fx` | `cost_basis × start_count × vest_fx` |
| Peak intervals | `qty_cy_start` | `start_count`, reduced by CY sells |
| `closing_value_inr` | `qty_dec31` | `end_count` |
| `sale_proceeds_inr` | CY sells from timeline | unchanged (G&L price required for INR) |

Remove the post-aggregate filter that drops rows where `closing == 0 AND sale_proceeds == 0`
— exclusion is now via `start_count == 0` only. Rows sold entirely during CY correctly
have `end_count == 0` but `start_count > 0`.

## `aggregate_by_date`

Groups per-tranche rows into final Schedule FA rows. Grouping key:
`{date_acquired, symbol, cost_basis_per_share}`.

**Why cost_basis, not plan_type:**
- Same date, same plan → same FMV → same cost basis → merged (correct)
- RSU + ESPP on same date → typically different FMVs → different cost basis → separate rows (correct)
- If by coincidence RSU and ESPP share cost basis on same date → merged (acceptable)

In merged rows:
- `cost_basis_per_share` — preserved (all members share the same value by grouping key)
- `plan_type` — join of distinct plan types (e.g. `"RSU"`, `"ESPP/RSU"` in edge case)
- All INR value and quantity fields — summed across members

---

## Upload checks integration

**File:** `lib/stock_plan/ingestion/upload_checks.ex`

```elixir
def schedule_fa_readiness(account_id, calendar_year) do
  # Delegate to ScheduleFA.pre_check/2 (new public function wrapping P1 + P2)
end
```

Replace `readiness_schedule_fa/4` global `uncovered_cy1` block with P1/P2 for CY-1.

Keep `:limited` when `has_current_shares && !has_holdings`.

---

## What is retired from FA path

| Artifact | Fate |
|---|---|
| `held_during_cy` in ScheduleFA | Removed from FA path |
| `format_gl_warning` soft-degrade branch | Removed |
| Row filter `closing=0 AND proceeds=0` | Removed |
| `validate_cy_coverage` in ScheduleFA | Replaced by P1 |
| `apply_bh_sold_validation_with_holdings` in TrancheTimeline | Removed (beyond-spec addition) |
| ESPP-specific `effective_holdings` clause | Removed — unified via `holdings_qty` |

---

## Files

| File | Change |
|---|---|
| `lib/stock_plan/tax/schedule_fa.ex` | P1, P2 (before TrancheTimeline.build), `compute_cy_state`, row builder |
| `lib/stock_plan/tax/tranche_timeline.ex` | `match_holding` returns `|| 0`; remove `apply_bh_sold_validation_with_holdings` |
| `lib/stock_plan/ingestion/upload_checks.ex` | Per-year FA readiness |
| `lib/stock_plan_web/live/tax_centre_live.ex` | Error display (unchanged structurally) |
| `test/stock_plan/tax/schedule_fa_test.exs` | New + updated tests |
| `test/stock_plan/ingestion/upload_checks_test.exs` | Readiness alignment tests |

---

## Example: SampleUser 1, FA 2024, BH only

```
P1: BH sell dates (RSU + ESPP) on/after 2024-01-01 → G&L required for each
    User 1 has ESPP and RSU sells in 2024+ → BLOCK (no G&L uploaded)
    Result: {:error, "G&L missing for sell dates: ..."}
    TrancheTimeline.build never called.
```

No partial FA. After user uploads G&L covering all sell dates in/after 2024:

```
P1: PASS
P2: snapshot fully exited → PASS (no Holdings needed)
TrancheTimeline.build: all holdings_qty = 0 (match_holding returns nil → || 0)
Pre-CY RSU tranches fully sold: start_count=0 → excluded
Lots sold during CY appear with full sale_proceeds_inr from G&L — correct disclosure.
```

Fully-exited RSU history does not appear as false holdings once P1+P2 pass.
