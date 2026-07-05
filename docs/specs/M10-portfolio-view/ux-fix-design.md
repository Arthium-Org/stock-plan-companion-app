# Design: M10 Portfolio — UX Fixes (Round 2)

## Category A: Tranche Sub-Table

### Current (broken)
```html
<!-- Grant and tranche rows are sibling <tr> in the same table -->
<tr>Grant row: Grant# | Date | Granted | Vested | Unvested | Value | Potential | P&L</tr>
<tr>Header:    #      | Date | Vest Qty| Sellable| Cost Basis</tr>  <!-- aligns with wrong columns -->
<tr>Tranche:   1      | ...  | ...     | ...     | ...</tr>
```

### Fixed
```html
<tr>Grant row: ▸ | Grant# | Date | FMV | Granted | Vested | Sellable | Unvested | Value | Potential | P&L</tr>
<!-- On expand: -->
<tr>
  <td></td>
  <td colspan="10">
    <table class="table table-xs ml-6 bg-base-200/30 border border-base-300 rounded">
      <thead>
        <tr>#  |  Vest Date  |  Vest Qty  |  Released  |  Sellable  |  Cost Basis</tr>
      </thead>
      <tbody>
        <tr>1  |  15-Nov-2022  |  27  |  27  |  9  |  $347.19</tr>
        ...
      </tbody>
    </table>
  </td>
</tr>
```

Key CSS:
- Inner table: `ml-6` (left indent), `bg-base-200/30` (subtle tint), `border border-base-300 rounded`
- Inner table uses `table-xs` (smaller than parent `table-sm`)
- Clear visual nesting through indentation + background + border

## Category B: Data Fields

### RSU Grant Row (updated columns)
```
▸ | Grant# | Grant Date | Grant FMV | Granted | Vested | Sellable | Unvested | Value | Potential | P&L
```

**Grant FMV source:** Verified — Holdings RSU Grant row does NOT have Award Price / Grant FMV. Not available from Holdings data.

**Decision:** Don't fetch from BH. Keep Portfolio source clean (Holdings only). Drop Grant FMV column from RSU grant row for now.

### RSU Tranche Row (updated columns)
```
# | Vest Date | Vest Qty | Released Qty | Sellable | Cost Basis
```

### RSU Section Summary
```
Restricted Stock (RS)    Vested: 48 shares (22 sellable) | Unvested: 158 shares | Value: $X | Potential: $Y
```

### Sellable Aggregation Rule

```
sellable_qty per tranche:
  nil  → ignore (unvested, not applicable)
  0    → include in sum (vested but fully sold)
  > 0  → include in sum (vested, owns shares)

sum only vested tranches: filter(status == "VESTED" AND sellable_qty != nil)
```

Helpers needed:
```elixir
defp compute_origin_sellable(origin) do
  origin.tranches
  |> Enum.filter(fn t -> t.status == "VESTED" and t.sellable_qty != nil end)
  |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.sellable_qty) end)
end
```

### ESPP Lock-In Price Fix

Promote `grant_date_fmv` from metadata to a dedicated field on `stock_plan_holdings`:

1. Add `grant_fmv` field to Holding schema (SafeDecimal, nullable)
2. In `HoldingsSilverBuilder.process_espp`: `grant_fmv = VN.clean_number(data["Grant Date FMV"])` (strips `$`)
3. In `Portfolio.build_origin_group_from_holdings`: `origin_fmv = first_tranche.grant_fmv`

No metadata parsing needed in template. Clean field path like cost_basis.

### Unvested Sellable
Replace `format_qty(t.sellable_qty)` with:
```elixir
{if t.status == "UNVESTED", do: "—", else: format_qty(t.sellable_qty)}
```

## Category C: Summary Card
```
Potential Value
$69,273.02
158 unvested shares (36 vests)
```

Add `unvested_shares` to `compute_summary`:
```elixir
unvested_shares: sum_qty(unvested),
```
Already exists as field but not displayed in template.

## Category D: Filters

### Deterministic Filter Logic

```
For each tranche:
  VISIBLE if:
    (status filter passes: vested ON/OFF, unvested ON/OFF)
    AND (P&L filter passes OR tranche is UNVESTED)

  P&L filter evaluation (VESTED only):
    nil filter  → pass
    :profit     → compute_pnl > 0
    :loss       → compute_pnl < 0

  UNVESTED tranches ALWAYS pass P&L filter.

For each origin:
  VISIBLE if ANY child tranche is visible.
  HIDDEN if zero children visible.

For each section (ESPP / RSU):
  If zero origins visible → show "No matching holdings"
```

### Hide Empty Origins Rule

```
Origin is hidden from portfolio if:
  sum(sellable_qty for VESTED tranches) == 0
  AND no UNVESTED tranches exist

This applies BEFORE filters. Filters further reduce from this set.
```

### Debug

Current `build_filtered_hierarchical` creates filtered structure. Verify:
1. `assign_filtered` sets `filtered_by_type` correctly
2. Template reads from `@filtered_by_type` via `@espp_origins` / `@rsu_origins`
3. If data correct but UI doesn't update — LiveView reactivity issue

## Category E: Sorting

Add to LiveView state:
```elixir
:grant_sort — {field, :asc | :desc}  # default {:grant_date, :asc}
```

New event:
```elixir
def handle_event("sort_grants", %{"field" => field}, socket) do
  ...
end
```

Apply sort in `assign_filtered` after building hierarchical data — sort origins within each plan type.

Sortable columns: grant_date, total_quantity, current_value (computed), pnl (computed).
For computed sorts (value, pnl): need to compute per-origin in the sort function using current_price.

## Files Modified

- `lib/stock_plan_web/live/portfolio_live.ex` — template rewrite + sort + filter fix
- `lib/stock_plan/portfolio.ex` — add unvested_shares to summary
- `lib/stock_plan/ingestion/holdings_silver_builder.ex` — clean grant_date_fmv
- `lib/stock_plan/schema/holding.ex` — possibly add grant_fmv field
