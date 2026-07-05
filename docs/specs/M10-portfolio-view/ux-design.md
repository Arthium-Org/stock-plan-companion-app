# Design: M10 Portfolio View — UX Rewrite

> **Reference:** E*Trade screenshots in `docs/Sample-Data/E-trade Screenshots/`

## Architecture

### Data Flow

```
Portfolio.build(account_id)
  → Hierarchical: %{"ESPP" => [origin_groups], "RSU" => [origin_groups]}

PortfolioLive
  mount:
    → Portfolio.build → @hierarchical
    → StockPrice.current_price → @current_price
    → FX.current_rate → @current_fx
  assigns:
    @hierarchical      — nested: plan_type → origins → tranches
    @expanded  — MapSet of {plan_type, origin_id} tuples for expanded rows
    @current_price     — live stock price
    @current_fx        — current FX rate
    @currency          — "USD" | "INR"
    @active_tab        — "type" | "status"
    @filters           — %{vested: bool, unvested: bool, pnl: nil | :profit | :loss}
    @summary           — totals computed from flat holdings
```

### Portfolio.build/1 — New Return Structure

```elixir
%{
  "ESPP" => [
    %{
      # Origin fields
      origin_id: "abc123",
      plan_type: "ESPP",
      grant_number: "hash...",     # not displayed — use origin_date
      origin_date: ~D[2022-07-01], # enrollment date (display as ESPP identifier)
      symbol: "ADBE",
      origin_fmv: Decimal,         # Grant Date FMV = lock-in price
      total_quantity: nil,         # nil for ESPP origins
      origin_fx_rate: Decimal,
      discount_percent: "15",      # from metadata_json

      # Pre-computed summaries
      total_qty: Decimal,          # sum of tranche quantities
      vested_qty: Decimal,
      unvested_qty: Decimal,
      vested_count: integer,
      unvested_count: integer,

      # Nested tranches (sorted vest_date ascending)
      tranches: [
        %{
          tranche_id, vest_date, status, quantity,
          cost_basis_per_share, cost_basis_source,
          vest_fx_rate, origin_fx_rate,
          # ESPP-specific from metadata:
          buy_price: Decimal         # discounted purchase price
        },
        ...
      ]
    },
    ...  # more enrollments, sorted origin_date ascending
  ],
  "RSU" => [
    %{
      origin_id: "def456",
      plan_type: "RSU",
      grant_number: "RU359625",    # broker-assigned, displayed
      origin_date: ~D[2021-11-15],
      symbol: "ADBE",
      origin_fmv: nil,
      total_quantity: Decimal,     # total granted shares
      origin_fx_rate: Decimal,

      total_qty: Decimal,
      vested_qty: Decimal,
      unvested_qty: Decimal,
      vested_count: integer,
      unvested_count: integer,

      tranches: [
        %{
          tranche_id, vest_date, status, quantity,
          cost_basis_per_share, cost_basis_source,
          vest_fx_rate, origin_fx_rate,
          sellable_qty: Decimal     # from Holdings enrichment
        },
        ...
      ]
    },
    ...
  ]
}
```

## Page Layout

```
┌──────────────────────────────────────────────────────────────────┐
│  Portfolio                                                       │
│                                                                  │
│  Adobe (ADBE)  $252.71                         [USD] [INR]      │
│                                             1 USD = ₹94.80      │
├──────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │ Total Value   │  │   Current    │  │  Potential    │           │
│  │  $45,213.00   │  │  $12,540.00  │  │  $32,673.00  │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
├──────────────────────────────────────────────────────────────────┤
│  ┃ By Type ┃  By Status                                          │
│                                                                  │
│  [Vested] [Unvested]  │  [Profit] [Loss]                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ▾ Employee Stock Purchase Plan (ESPP)                           │
│    Total Qty: 60.95  Current Value: $15,470  P&L: -$3,200       │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Grant Date    Lock-In    Qty     Value      P&L           │  │
│  │ ▸ 01-Jul-22   $368.48   30.63   $7,770    -$1,570        │  │
│  │ ▸ 03-Jan-23   $336.92   15.00   $3,800      -$650        │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ▾ Restricted Stock (RS)                                         │
│    Vested: 48  Unvested: 36  Value: $12,190  Potential: $9,130  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Grant#     Date       Granted Vested Unvest Value  Potentl│  │
│  │ ▸ RU359625 15-Nov-21   107    107     0    $12,190   —    │  │
│  │ ▸ RU385073 24-Jan-23    93     60    33     $7,640  $4,200│  │
│  │ ▸ RU444827 24-Jan-25    60     10    50     $2,540  $6,360│  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Expanded RSU Grant:                                             │
│  ▾ RU359625  15-Nov-2021  107  107  0  $12,190  —              │
│    ┌────────────────────────────────────────────────────────┐    │
│    │ #   Vest Date    Vest Qty  Sellable  Cost Basis       │    │
│    │ 1   15-Nov-2022    27        9       $347.19          │    │
│    │ 2   15-Feb-2023     6        6       $375.77          │    │
│    │ 3   15-May-2023     7        7       $341.51          │    │
│    │ ...                                                    │    │
│    └────────────────────────────────────────────────────────┘    │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  * Market Adjusted Close (actual FMV unavailable)                │
│  FX: SBI TT Buying Rate (2020+), RBI Reference Rate (earlier)   │
└──────────────────────────────────────────────────────────────────┘
```

## Component Details

### Tabs
```html
<div class="tabs tabs-bordered">
  <a class={"tab #{if @active_tab == "type", do: "tab-active"}"}>By Type</a>
  <a class={"tab #{if @active_tab == "status", do: "tab-active"}"}>By Status</a>
</div>
```

### Filter Chips
```html
<!-- Active: btn-success/btn-info. Inactive: btn-outline -->
<button class={"btn btn-xs #{if active, do: "btn-success", else: "btn-outline"}"}>
  Vested
</button>
```

### Expand/Collapse Row
```html
<tr class="cursor-pointer hover:bg-base-200" phx-click="toggle_expand" phx-value-origin-id={origin.origin_id}>
  <td>
    <span class="mr-1">{if expanded, do: "▾", else: "▸"}</span>
    {display_name}
  </td>
  ...
</tr>
<!-- Children rendered conditionally -->
<%= if origin.origin_id in @expanded do %>
  <%= for tranche <- origin.tranches do %>
    <tr class="bg-base-200/50 text-sm">...</tr>
  <% end %>
<% end %>
```

### Number Formatting
```elixir
# format_number(Decimal.new("1234567.89")) → "1,234,567.89"
# format_currency(Decimal.new("-119184.40"), "INR") → "-₹1,19,184.40"
# format_currency(nil, "USD") → "—"
```

### Unvested Styling
```html
<td class="text-right font-mono text-xs italic text-base-content/50">
  {format_currency(potential_value, @currency)}
</td>
```

### Empty Section
```html
<div class="text-center py-6 text-base-content/40">
  No current holdings
</div>
```

## "By Status" View

Flat table (no hierarchy). Two sections: VESTED → UNVESTED. Each section is a simple table with columns: Grant#/Date, Vest Date, Qty, Cost Basis, Value, P&L. Sorted by vest_date ascending within each section.

## Implementation Notes

- `Portfolio.build/1` is the only change to the context module. LiveView handles all display logic.
- Expand/collapse state (`@expanded`) is a MapSet of `{plan_type, origin_id}` tuples — no DB involved.
- "By Status" view reuses the same hierarchical data, just flattens and re-groups by status.
- INR P&L at origin level: sum of tranche-level INR P&Ls (each tranche may have different vest_fx_rate).
- ESPP `total_quantity` is nil on origin → compute from sum of tranche quantities.
