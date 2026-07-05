# Design — Regression Test Fixes

---

## Fix 1: Schedule FA graceful degradation (FA-1)

**File:** `lib/stock_plan/tax/schedule_fa.ex`

### Change

In `build/2`, replace the hard-error arm from `validate_cy_coverage` with a soft warning that proceeds to build rows:

```elixir
# Before
case TrancheTimeline.validate_cy_coverage(bh_sales, allocations, calendar_year) do
  {:error, msg} ->
    {:error, msg}

  :ok ->
    ...
end

# After
case TrancheTimeline.validate_cy_coverage(bh_sales, allocations, calendar_year) do
  {:error, _msg} ->
    # validate_cy_coverage returns {:error, binary} — compute warning locally
    # by diffing BH sales vs allocation dates for the requested CY
    warning = format_gl_warning(bh_sales, allocations, calendar_year)
    cy_holdings = TrancheTimeline.held_during_cy(timelines, calendar_year)
    rows = build_fa_rows_from_timeline(cy_holdings, calendar_year)
    aggregated = aggregate_by_date(rows)
    {:ok, aggregated, [warning | validation.warnings]}

  :ok ->
    cy_holdings = TrancheTimeline.held_during_cy(timelines, calendar_year)
    rows = build_fa_rows_from_timeline(cy_holdings, calendar_year)
    aggregated = aggregate_by_date(rows)
    case check_meta_coverage(aggregated) do
      :ok -> {:ok, aggregated, validation.warnings}
      {:error, missing} -> {:error, {:missing_meta, missing}}
    end
end
```

Need to check the exact shape of the `{:error, _}` returned by `validate_cy_coverage` to extract dates and year for the warning message.

### Warning message format

```
"G&L data not available for [year]. Sales on [date1], [date2], … are not covered — 
upload G&L Expanded for [year] to generate a complete Schedule FA."
```

Private helper `format_gl_warning/2` in `schedule_fa.ex`.

---

## Fix 2: Capital Gains — skip uncovered FY (CG-1)

**File:** `lib/stock_plan/tax/capital_gains.ex`

### Change

After fetching sales and allocations, detect coverage before building rows:

```elixir
def build(account_id, fy_start_year) do
  fy_start = Date.new!(fy_start_year, 4, 1)
  fy_end   = Date.new!(fy_start_year + 1, 3, 31)

  sales = fetch_sales(account_id, fy_start, fy_end)

  if sales == [] do
    {[], zero_summary()}
  else
    allocs = fetch_allocations(Enum.map(sales, & &1.id))
    # fetch_allocations returns %{sale_id => [alloc, ...]} (grouped map)
    # A sale is covered iff ∃ allocation with sale_price NOT NULL or sale.sale_price NOT NULL
    sales_by_id = Map.new(sales, &{&1.id, &1})

    covered_ids =
      MapSet.new(
        Enum.filter(allocs, fn {sale_id, alloc_list} ->
          sale = Map.get(sales_by_id, sale_id)
          Enum.any?(alloc_list, fn a -> a.sale_price != nil end) ||
            (sale != nil && sale.sale_price != nil)
        end),
        fn {sale_id, _} -> sale_id end
      )

    {covered_sales, uncovered_sales} =
      Enum.split_with(sales, fn s -> MapSet.member?(covered_ids, s.id) end)

    warning =
      if uncovered_sales != [] do
        dates = uncovered_sales |> Enum.map(& &1.sale_date) |> Enum.uniq() |> Enum.sort() |> Enum.join(", ")
        "G&L data not available for #{length(uncovered_sales)} sale(s) on #{dates}. Upload G&L to compute these gains."
      end

    if covered_sales == [] do
      # No G&L coverage at all for this FY
      {[], %{zero_summary() | warning: warning}}
    else
      rows = build_rows(covered_sales, allocs)
      summary = compute_summary(rows) |> Map.put(:warning, warning)
      {rows, summary}
    end
  end
end
```

### Summary map change

Add `warning: nil` to `zero_summary/0`. The LiveView checks `summary.warning` and renders it above the table when non-nil.

---

## Fix 3: Sell Advisor early-exit check (SA-2)

**File:** `lib/stock_plan/tax/sell_advisor_v2.ex`

### Change

Extract `symbol` from opts first, then load lots *before* any price fetch:

```elixir
def advise(account_id, target, opts \\ []) do
  today = Keyword.get(opts, :today, Date.utc_today())
  explicit_symbol = Keyword.get(opts, :symbol)

  # Early exit: no point fetching price if there's nothing to sell
  lots_check = SellAdvisor.load_sellable_lots(account_id, explicit_symbol)
  if lots_check == [] do
    {:error, :no_sellable_lots}
  else
    current_price = ...
    current_fx = ...
    symbol = explicit_symbol || resolve_default_symbol(account_id)
    ...
    # existing with-chain, but load_sellable_lots call uses lots_check (already loaded)
  end
end
```

To avoid double-querying `load_sellable_lots`, pass `lots_check` into the `with` body or replace the inner `load_sellable_lots` call with it.

---

## Validate_cy_coverage return shape

Need to verify the exact `{:error, _}` shape returned by `TrancheTimeline.validate_cy_coverage/3` before implementing FA-1.

If it returns `{:error, message_string}` (not a structured tuple), the warning formatter will parse the string. Prefer extracting dates and year from the structured data at the source.
