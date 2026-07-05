# Design: M24 — Benefit History Analysis Page

## Approach

A single LiveView (`HistoryLive`) replaces the stub. A new `StockPlan.History` context module produces all analysis structs. Charts use lightweight SVG drawn in HEEx — no JS chart library, no new dependencies.

No schema change. No migration. No new external dependency.

---

## Module: `StockPlan.History`

### Public API

```elixir
@spec build(account_id :: String.t()) :: %{
  symbols:            [String.t()],
  prices:             %{String.t() => String.t() | nil},   # symbol => current price string or nil
  prices_fetched_at:  DateTime.t(),
  rsu:                %{String.t() => rsu_analysis()},     # keyed by symbol
  espp:               %{String.t() => espp_analysis()}     # keyed by symbol
}
```

Empty DB returns `%{symbols: [], prices: %{}, prices_fetched_at: DateTime.utc_now(), rsu: %{}, espp: %{}}`.

### `rsu_analysis()` shape

```elixir
%{
  summary: %{
    grant_count:              integer(),
    grant_promise_usd:        Decimal.t(),
    grant_promise_inr:        Decimal.t(),
    income_recognized_usd:    Decimal.t(),
    income_recognized_inr:    Decimal.t(),
    still_to_vest_usd:        Decimal.t() | nil,   # UI-only; nil without current price
    still_to_vest_inr:        Decimal.t() | nil,
    vested_net_shares:        Decimal.t(),
    unvested_gross_shares:    Decimal.t(),
    vest_vs_grant_drift_pct:  Decimal.t() | nil
  },
  grants:                   [grant_row()],          # §G.4 columns; no sold/proceeds/return_pct
  income_by_year:           [%{year: integer(), value_usd: Decimal.t(), value_inr: Decimal.t()}],
  grants_by_year:           [%{year: integer(), value_usd: Decimal.t(), value_inr: Decimal.t()}]
}
# Removed from RSU tab (§G.5): counterfactual, tax_paid_by_year, velocity, yoy, sold/proceeds summary fields
```

### `grant_row()` shape (RSU table)

```elixir
%{
  grant_number:    String.t(),
  grant_date:      Date.t(),
  granted_qty:     Decimal.t(),
  grant_promise_usd: Decimal.t(),
  grant_promise_inr: Decimal.t(),
  recognized_usd:  Decimal.t(),          # Σ(vest_qty × vest_fmv) VESTED
  recognized_inr:  Decimal.t(),
  still_to_vest_usd: Decimal.t() | nil,  # unvested_gross × current_price
  still_to_vest_inr: Decimal.t() | nil,
  vs_promise_pct:  Decimal.t() | nil     # (recognized + still_to_vest) / grant_promise − 1
}
```

### RSU `History` compute functions (§G)

| Function | Role |
|----------|------|
| `compute_rsu_summary/4` | §G.1 — grant_count, grant_promise, income_recognized, still_to_vest, vested_net, unvested_gross, vest_vs_grant_drift_pct |
| `compute_rsu_income_by_year/2` | Chart A — unchanged core; rename map key `income_by_year` in build output |
| `compute_grants_by_year/1` | Chart B — group origins by grant year, sum grant_promise |
| `compute_grant_rows/3` | Table — §G.4 columns only; drop sold/proceeds/return_pct/unrealized |
| ~~`compute_rsu_tax_by_year/2`~~ | **Remove** from build + UI |
| ~~`compute_rsu_counterfactual/4`~~ | **Remove** — no G&L tranche sell truth |
| ~~`compute_vesting_velocity/2`~~ | **Remove** |
| ~~`compute_yoy_growth/1`~~ | **Remove** |

### `espp_analysis()` shape

```elixir
%{
  summary: %{
    gross_purchased:          Decimal.t(),
    net_received:             Decimal.t(),
    tax_withheld:             Decimal.t(),          # tooltip on Net Received tile; not a standalone tile
    purchase_value_usd:       Decimal.t(),          # Σ(gross_shares × buy_price)
    purchase_value_inr:       Decimal.t() | nil,
    currently_held:           Decimal.t(),
    net_discount_usd:         Decimal.t(),          # Σ((vest_fmv − buy_price) × net_shares)
    net_discount_inr:         Decimal.t() | nil,
    realized_proceeds_usd:    Decimal.t() | nil,    # Σ(sale_price × sold_qty)
    realized_proceeds_inr:    Decimal.t() | nil,
    realized_pnl_usd:         Decimal.t() | nil,   # net_buy_price basis
    realized_pnl_inr:         Decimal.t() | nil,
    unrealized_pnl_usd:       Decimal.t() | nil,   # net_buy_price basis
    unrealized_pnl_inr:       Decimal.t() | nil,
    total_pnl_usd:            Decimal.t() | nil,   # realized + unrealized
    total_pnl_inr:            Decimal.t() | nil,
    total_return_pct:         Decimal.t() | nil,   # total_pnl / purchase_value × 100
    sell_on_purchase_usd:     Decimal.t(),          # Σ(vest_fmv × net_quantity) per lot
    sell_on_purchase_inr:     Decimal.t() | nil,
    approximate_xirr:         float() | nil
  },
  current_price:            Decimal.t() | nil,
  lots:                     [espp_lot()],
  sold_lots:                [espp_lot()],    # lots where sold_qty > 0
  unsold_lots:              [espp_lot()],    # lots where held_qty > 0
  qualifying_count:         integer(),
  disqualifying_count:      integer(),
  qualifying_proceeds_usd:  Decimal.t(),
  disqualifying_proceeds_usd: Decimal.t()
}
```

### `espp_lot()` shape

```elixir
%{
  purchase_date:   Date.t(),
  grant_date:      Date.t() | nil,
  lookback_price:  Decimal.t() | nil,    # origins.origin_fmv (not displayed; kept for XIRR/SOP)
  buy_price:       Decimal.t() | nil,    # tranche.metadata_json["buy_price"] — plan quoted price (display)
  net_buy_price:   Decimal.t() | nil,    # tranche.metadata_json["net_buy_price"] — all History P&L math
  purchase_fmv:    Decimal.t() | nil,    # tranches.vest_fmv
  discount_pct:    Decimal.t() | nil,
  gross_shares:    Decimal.t(),          # tranches.vest_quantity
  net_shares:      Decimal.t(),          # tranches.net_quantity
  tax_shares:      Decimal.t() | nil,
  sold_qty:        Decimal.t(),
  held_qty:        Decimal.t(),
  allocs:          [alloc()],            # raw sale allocations — used for XIRR per-alloc inflows
  sale_date:       Date.t() | nil,       # first alloc's date (for table display)
  sale_price:      term() | nil,         # first alloc's price (for table display)
  if_sold_at_purchase: Decimal.t() | nil,  # vest_fmv × net_quantity
  realized_pnl:    Decimal.t() | nil,    # (sale_price − net_buy_price) × sold_qty
  pnl_pct:         Decimal.t() | nil,   # realized_pnl / (net_buy_price × sold_qty) × 100
  unrealized_pnl:  Decimal.t() | nil,   # (current_price − net_buy_price) × held_qty
  total_discount:  Decimal.t() | nil
}
```

---

## Key computation rules

### `net_buy_price` — persisted at ingestion

Computed and stored during ESPP tranche insert in `silver_builder.ex`:

```elixir
net_buy_price =
  if net > Decimal.new(0) and buy_price and gross do
    Decimal.div(Decimal.mult(buy_price, gross), net)
  else
    buy_price   # fallback when gross == net or missing tax split
  end
```

Stored as string in `tranches.metadata_json["net_buy_price"]` (SafeDecimal convention). Recomputed on every Silver rebuild. **History page only** — do not use in Tax Centre, Portfolio, or Sell Advisor.

`build_espp_lots/4` reads `net_buy_price` from tranche metadata; fallback: compute from gross/net/buy when metadata key is missing (old ingestions before this change).

### Purchase Value

`Σ(gross_shares × buy_price)` — total payroll contribution covering all purchased shares, including shares later withheld for tax. Using `net_shares` would undercount the investment.

### Net Discount Value

`Σ((vest_fmv − buy_price) × net_shares)` — discount on shares actually received. Row 2 tile. Distinct from `day1_gain` in SOP (which accounts for paying gross but receiving net).

### ESPP P&L basis

All P&L and return % on the History page use `net_buy_price`:

```
realized_pnl  = Σ(sale_price − net_buy_price) × sold_qty    # per alloc
unrealized_pnl = (current_price − net_buy_price) × held_qty  # per lot
pnl_pct       = realized_pnl / (net_buy_price × sold_qty) × 100
```

### XIRR cashflows

For each lot:

| Flow | Timing | Amount |
|---|---|---|
| Outflow | `purchase_date` | `−(gross_shares × buy_price)` |
| Sale inflows | per alloc, at `alloc.sale_date` | `alloc.sold_qty × alloc.sale_price` |
| Held inflow | `today` | `held_qty × current_price` |

One outflow per lot. Multiple sale inflow entries per lot if the lot was sold in separate sell events (different dates, different prices). One held inflow per lot if `held_qty > 0`.

This correctly models the economics: the employee invested `gross × buy_price`; received proceeds only from the `net` shares they actually got.

### INR variants in ESPP summary

Pre-computed using `current_fx` (an approximation; event-time FX per-lot is not aggregated here). Fields: `purchase_value_inr`, `total_discount_inr`, `realized_pnl_inr`, `unrealized_pnl_inr`, `sell_on_purchase_inr`. These exist so the LiveView can toggle currency without requerying.

### Sell-on-Purchase analysis (derived in LiveView)

Computed in `espp_sop_analysis(summary, currency)` in the LiveView — not stored in the context result. Currency-specific: reads `_inr` or `_usd` variants based on the active currency toggle. All P&L uses `net_buy_price` (see §A.1b).

```elixir
day1_gain          = sell_on_purchase − purchase_value   # net discount
total_pnl          = realized_pnl + unrealized_pnl      # actual outcome
extra_from_holding = total_pnl − day1_gain              # holding vs day-1 exit
holding_better     = extra_from_holding > 0
```

Returns `nil` when `sell_on_purchase` or `purchase_value` is nil.

#### Purpose

Answers: *Was holding (and selling later) better than exiting every lot at purchase-day FMV on the next trading day?* This is a **historical hypothetical** — not “should I sell today.” Current-market context lives in summary row 3, the return strip, and the unsold lots chart.

#### UI structure

```
section title + (?) tooltip
├── context line (one sentence — purchase-day FMV hypothetical)
├── 3 equal cards (bg-base-200)
│   ├── Day-1 gain          — day1_gain, always green
│   ├── Extra from holding  — extra_from_holding, green/red
│   └── Total P&L           — total_pnl, green/red
├── verdict banner (F.5)      — success/warning, full width
└── scope banner (F.6)        — info, full width, **separate block**
```

**Visual hierarchy:** cards are supporting numbers; the two footers carry the message. The scope banner (“not today's stock price”) must be **as prominent as the verdict** — its own bordered info panel, not a muted subline under the verdict.

#### Verdict banner (F.5)

| Condition | Copy |
|---|---|
| `holding_better` | **Holding was worth it** — you are **{extra}** ahead versus selling at purchase-day FMV on the next trading day (on top of **{day1_gain}** day-1 discount). |
| else | **Day-1 exit would have been better** — selling at purchase-day FMV would have left you **{abs(extra)}** more than your actual outcome (day-1 discount was **{day1_gain}**). |

Styles: `text-base`–`text-lg`, `font-semibold`, `py-4 px-5`, `bg-success/15` or `bg-warning/15`. Verdict must not mention current price.

#### Scope banner (F.6)

Separate full-width block below verdict:

- **Title:** Not a comparison to today's stock price
- **Body:** Compares actual realized + unrealized P&L to a purchase-day exit. Does not evaluate selling current holdings at `{current_price}`. Point user to summary row 3, return strip, unsold chart for current-market decisions.
- **Styles:** `border-2 border-info/40 bg-info/10 rounded-xl py-4 px-5`, `text-base font-medium` title

#### `espp_sop_analysis/2` return shape

```elixir
%{
  day1_gain: Decimal.t(),
  extra_from_holding: Decimal.t(),
  total_pnl: Decimal.t(),
  holding_better: boolean()
}
```

Remove `avg_return_pct` from SOP helper (return % lives in return strip + charts).

---

## Data loading strategy

Three queries, no per-symbol loops:

```
1. origins  WHERE ingestion.account_id = ? AND ingestion.status = 'ACTIVE'
2. tranches WHERE origin_id IN (origin_ids)
3. sales + sale_allocations WHERE origin_id IN (origin_ids)
   → joined: sale_allocations JOIN sales, selects tranche_id, sold_qty, sale_price, sale_date, symbol
```

Fan-out by symbol happens in Elixir after all three queries return. `Map.new(symbols, fn s -> ... end)` produces per-symbol slices from the flat lists.

---

## ESPP BH-only mode (no G&L uploaded)

SaleAllocations are only created by G&L ingestion. When only BH has been uploaded, `allocs_by_tranche` is empty for all tranches. Without a fallback, every ESPP lot would show `sold_qty = 0`.

### Fix: BH Sale fallback in `build_espp_lots`

BH SELL events are children of a specific Purchase parent row. The silver builder stores `purchase_date` in each Sale's `metadata_json`:

```elixir
# silver_builder.ex — ESPP BH sale insert
insert_sale!(ing, origin, %{
  sale_date: sale_date,
  total_quantity: qty,
  metadata_json: Jason.encode!(%{purchase_date: Date.to_iso8601(purchase_date)})
})
```

`purchase_date` matches exactly one tranche (`vest_date == purchase_date`). `build_espp_lots` checks allocs first; when empty, sums BH Sale quantities for that tranche:

```elixir
{sold_qty, allocs} =
  if allocs != [] do
    {sum_decimal(allocs, & &1.sold_qty), allocs}
  else
    {bh_sold_qty_for_tranche(bh_sales, t.origin_id, t.vest_date), []}
  end
```

### BH-only field behaviour

| Field | BH only | BH + G&L |
|---|---|---|
| `sold_qty` | from Sale.total_quantity | from SaleAllocation.quantity |
| `held_qty` | net_quantity − sold_qty | net_quantity − sold_qty |
| `realized_pnl` | nil (no sale price) | computed from alloc sale_price |
| `unrealized_pnl` | held_qty × current_price − buy_price | same |
| `sale_date` | nil | from first allocation |
| `sale_price` | nil | from first allocation (COALESCE G&L / Yahoo) |
| XIRR sale inflows | none (empty allocs) | per-alloc |

This is additive: uploading G&L after BH automatically switches to the richer path since SaleAllocations now exist for those tranches.

---

## Yahoo price resilience (two-stage)

### Stage 1 — SilverBuilder (at ingestion time)

```elixir
yahoo_price =
  try do
    StockPlan.StockPrice.get_close(symbol, sale_date)
  rescue
    e ->
      Logger.warning("Yahoo price fetch failed for #{symbol} on #{sale_date}: #{Exception.message(e)}")
      nil
  end
```

`sale_price` stored as `nil` when Yahoo fails. Ingestion proceeds normally.

### Stage 2 — History.build (at history-render time)

`load_espp_allocs_by_tranche/1` retries Yahoo for any allocation where `sale_price` is nil:

```elixir
price = alloc.sale_price || yahoo_price_safe(alloc.symbol, alloc.sale_date)
```

`yahoo_price_safe/2` wraps Yahoo in `try/rescue` and emits `Logger.warning/1` on failure. Returns `nil` on failure — the allocation proceeds with `nil` price, P&L shows "—" in the UI.

---

## XIRR module

`StockPlan.Finance.XIRR` — Newton-Raphson with bisection fallback.

```elixir
@spec xirr([{Date.t(), float()}], guess :: float()) :: {:ok, float()} | {:error, :no_convergence}
```

Returns `{:error, :no_convergence}` on pathological inputs (empty, all same date, no inflows). The caller renders `nil` → "n/a".

---

## Chart components (`lib/stock_plan_web/components/charts.ex`)

Five SVG components, all `viewBox="0 0 600 200"`. Grid lines `#F3F4F6`, axis labels `#9CA3AF`.

| Component | Attrs | Use |
|---|---|---|
| `bar_chart` | `labels, values, currency, color` | ESPP / generic bars (RSU uses `line_chart` per §2.3) |
| `stacked_bar_chart` | `labels, series, currency` | Multi-series stacked bars (currently unused but available) |
| `line_chart` | `categories, series, fill` | RSU vest income by year; RSU new grant value by year |
| `pnl_bar_chart` | `lots` | ESPP sold lots P&L — green/red bars with % label |
| `cost_basis_chart` | `lots, current_price` | ESPP unsold lots — dots with SVG `<title>` hover tooltip |

### `pnl_bar_chart` specifics

- **Y-axis = return %** (not dollar P&L) — `pnl_pct` per lot is the bar height
- Bars colored `#10B981` (green) / `#F43F5E` (red) based on sign of `pnl_pct`
- Bar width varies by density tier (≤12: `slot × 0.5`; 13–24: `slot × 0.4`; >24: `slot × 0.35`)
- `pnl_pct` label: `+12.3%` above positive bars, `-8.1%` below negative bars
- Zero baseline dashed line (distinct from solid X-axis)
- Solid X-axis and Y-axis lines on plot bounds
- Y-axis domain: always includes 0; scaled to data; mixed sign → symmetric ±max
- Currency toggle affects **hover proceeds/P&L** only; Y-axis stays %
- Hover: purchase date · sold qty · held qty if partial · net buy price · avg sale price · proceeds · dollar P&L · return %

### `cost_basis_chart` specifics (renamed: open lots chart)

- **Dots at `net_buy_price`** (not raw `buy_price`)
- Dot radius by density tier (≤12: `r=6`; 13–24: `r=5`; >24: `r=4`)
- **No connecting polyline** — scatter only
- Green dot if `current_price > net_buy_price`; red if below
- Dashed reference line at `current_price` in `#6366F1` (indigo), labeled "Current"; hidden when price nil
- Solid X-axis and Y-axis lines on plot bounds
- Hover (SVG `<title>` or equivalent): purchase date · held qty · net buy price · current price · unrealized $ and %

### Shared `chart_layout/2` helper

Both charts share a layout helper to avoid duplicating density logic:

```elixir
@spec chart_layout(n :: integer(), kind :: :bar | :scatter) ::
  %{svg_width: integer(), slot: float(), label_indices: [integer()],
    label_format: :full | :year | :quarter, bar_bw: float(), dot_r: integer()}
```

`kind: :bar` → populates `bar_bw`; `kind: :scatter` → populates `dot_r`. When `n * 36 > plot_width`, `svg_width` grows and the LiveView wraps the SVG in `overflow-x: auto`.

---

## LiveView: `HistoryLive`

### Assigns

```elixir
:page_title           "Benefits History"
:last_upload_at       Ingestions.latest_upload_at(account_id)   # DateTime | nil
:symbols              [String.t()]
:active_symbol        String.t() | nil
:active_plan          "RSU" | "ESPP"
:analysis             History.build/1 result
:prices               %{symbol => price_string | nil}
:prices_fetched_at    DateTime.t()
:currency             "INR" | "USD"   # default "INR"
:qual_open            boolean          # qualifying/disqualifying section expanded?
:espp_lots_expanded   boolean          # purchase lots table expand/collapse; default false
```

### Events

```elixir
handle_event("select_symbol",         %{"symbol" => sym},      socket)
handle_event("select_plan",           %{"plan" => plan},       socket)
handle_event("toggle_currency",       %{"currency" => cur},    socket)
handle_event("toggle_qual",           _,                       socket)
handle_event("toggle_espp_lots_table", _,                      socket)
```

`toggle_currency` takes an explicit `%{"currency" => currency}` param (two-button pattern, not a flip). `phx-value-currency="INR"` / `phx-value-currency="USD"` on each button.

### Render structure

```
page-root
├── no-data alert  (if active_symbol == nil)
└── else:
    ├── page header: h1 + INR|USD two-button toggle
    ├── info bar
    │   ├── left: symbol (or dropdown) + current price + ℹ️ tooltip
    │   └── right: "Data last updated [datetime]" + "↑ Upload" link
    ├── plan tabs: RSU | ESPP
    ├── RSU section (if active_plan == "RSU")  — §G income lens
    │   ├── summary tiles (2 rows, 7 tiles + ℹ tooltips)
    │   ├── vest income by year line_chart
    │   ├── grant breakdown table (5-row scroll + expand)
    │   ├── new grant value by year line_chart
    │   └── disclaimer callout
    └── ESPP section (if active_plan == "ESPP")
        ├── summary v2 (3 rows + return strip, all currency-aware)
        │   ├── Row 1: Gross Purchased · Net Received ℹ️ · Currently Held
        │   ├── Row 2: Purchase Value · Net Discount Value · Realized Proceeds
        │   ├── Row 3: Realized P&L · Unrealized P&L · Total P&L
        │   └── Return strip: total return % · Approx. XIRR ℹ️
        ├── purchase lots table (scroll + expand; P&L via net_buy_price)
        ├── sold share returns pnl_bar_chart (Y-axis = %; dynamic width)
        ├── open lots cost_basis_chart (dots at net_buy_price; no polyline; dynamic width)
        ├── sell-on-purchase analysis (3 cards + verdict + scope banner)
        ├── qualifying/disqualifying collapsible
        └── ESPP tab footer disclaimer
```

### Currency toggle

Two-button group (same pattern as Portfolio view):

```heex
<button phx-click="toggle_currency" phx-value-currency="INR"
        class={"btn btn-xs #{if @currency == "INR", do: "btn-primary", else: "btn-outline"}"}>
  ₹ INR
</button>
<button phx-click="toggle_currency" phx-value-currency="USD"
        class={"btn btn-xs #{if @currency == "USD", do: "btn-primary", else: "btn-outline"}"}>
  $ USD
</button>
```

### `espp_sop_analysis/2` LiveView helper

Private function in `HistoryLive`. Reads `_inr` or `_usd` variants from `summary` based on `currency`. Returns a map or `nil` (when data is insufficient). Used in the template as `<%= if sop_data = espp_sop_analysis(espp.summary, @currency) do %>`.

---

## Formatter helpers (in `HistoryLive`)

| Helper | Signature | Notes |
|---|---|---|
| `fmt_qty` | `Decimal.t() \| nil → String.t()` | `"—"` for nil |
| `fmt_money` | `(Decimal.t() \| nil, currency) → String.t()` | `"₹X,XX,XXX"` or `"$X.XX"` |
| `fmt_money_usd` | `Decimal.t() \| nil → String.t()` | Always USD |
| `fmt_money_usd_nil` | `Decimal.t() \| nil → String.t()` | Alias of above |
| `fmt_pct` | `Decimal.t() \| float() \| nil → String.t()` | `"12.3%"` |
| `fmt_xirr` | `float() \| nil → String.t()` | `"n/a"` for nil |
| `fmt_date` | `Date.t() \| nil → String.t()` | `"24-Jan-2025"` |
| `fmt_datetime` | `DateTime.t() \| nil → String.t()` | `"08 Jun 2026, 14:32 UTC"` |
| `fmt_price` | `String.t() \| nil → String.t()` | `"$453.21"` or `"—"` |
| `fmt_signed` | `(Decimal.t() \| nil, currency) → String.t()` | `"+₹1,23,456"` or `"+$1234"` |
| `fmt_inr_num` | `Decimal.t() → String.t()` | Indian number formatting (lakhs, crores) |

---

## Open questions (resolved)

1. **XIRR convergence** — returns `{:error, :no_convergence}`; UI shows "n/a". ✅
2. **Nil current_price** — all current-price-derived fields are nil; UI shows "—". ✅
3. **Combined view** — deferred, out of scope for M24. ✅
4. **buy_price location** — confirmed in `tranche.metadata_json["buy_price"]`, not origin. ✅
5. **Purchase value denominator** — gross_shares (not net_shares) for consistency with total_discount. ✅
