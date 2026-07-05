# UX Design: M24 — Benefit History (ESPP Tab)

> **For implementers (Claude):** This is the **authoritative UX spec** for the ESPP tab on `HistoryLive`.  
> **Visual mock (in repo):** [`m24-bh-history.canvas.tsx`](./m24-bh-history.canvas.tsx) — read source for layout; Cursor **Open Canvas** requires the managed copy below.  
> **Live Canvas preview:** `~/.cursor/projects/Users-kirandev-Projects-wealth-management-stock-plan/canvases/m24-bh-history.canvas.tsx` (sync from repo copy when mock changes). Top bar: *“M24 ESPP History — full page mock (§A–F)”*.  
> **Brainstorm changelog:** `cursor-feedback-on-specs.md` (append-only history; do not implement from it directly — implement from this file + `requirements.md` / `design.md` / `test-plan.md`).  
> **Data layer:** `design.md` (`StockPlan.History` shapes, `net_buy_price` ingestion).  
> **RSU tab:** [`ux-design-rsu.md`](./ux-design-rsu.md) + mock `m24-rsu-history.canvas.tsx` — this file is **ESPP only**.

---

## Document map

| Artifact | Role |
|----------|------|
| **`ux-design.md` (this file)** | Layout, copy, interaction, visual hierarchy, chart encoding, acceptance criteria |
| **`requirements.md`** | Functional requirements — keep in sync with § references here |
| **`design.md`** | Elixir modules, data shapes, formulas at context layer |
| **`tasks.md`** | Implementation checklist |
| **`test-plan.md`** | LiveView + context tests |
| **`m24-bh-history.canvas.tsx`** | Visual mock source — **versioned in git** (this folder) |
| **Managed Canvas copy** | `~/.cursor/projects/.../canvases/` — live preview only; keep in sync with repo file |
| **Screenshots** | Optional later; not required for v1 |

Mocks alone are **not** sufficient for Claude — they lack formulas, edge cases, and file mappings. This MD + existing spec quartet is the implementation package.

---

## Page shell

### Route & module

- Route: `/history` → `HistoryLive`
- Scope: ACTIVE ingestion only; per-symbol when multi-symbol (M22)

### Header

```
┌─────────────────────────────────────────────────────────────────┐
│ Benefits History                          [ ₹ INR ] [ $ USD ]   │
├─────────────────────────────────────────────────────────────────┤
│ [ADBE ▾]  $453.21  as of {prices_fetched_at}                    │
│                          Data last updated {bh_uploaded_at}  Upload│
├─────────────────────────────────────────────────────────────────┤
│  RSU  │  ESPP  │                                                │
└─────────────────────────────────────────────────────────────────┘
```

| Element | Behavior |
|---------|----------|
| Currency toggle | Two-button group (`phx-value-currency`), same pattern as Portfolio |
| Symbol | Dropdown when `length(symbols) > 1`; plain text when single symbol |
| Current price | From Yahoo/cache; `—` if nil |
| Upload link | Links to `/upload` |
| Plan tabs | `RSU` \| `ESPP`; `phx-click="select_plan"` |

### Empty state

No ACTIVE BH ingestion → full-page warning callout + link to Upload. No partial ESPP section.

---

## Global rules (ESPP tab)

### P&L basis — `net_buy_price`

All ESPP **performance** numbers use **effective cost per received share**:

```
net_buy_price = (buy_price × gross_shares) / net_shares
```

- **Persisted** at BH Silver build: `tranches.metadata_json["net_buy_price"]` (`silver_builder.ex`)
- **History page only** — Tax Centre, Portfolio, Sell Advisor unchanged
- **Display:** Buy Price column shows plan `buy_price`; P&L math uses `net_buy_price`

### Two layers (do not mix)

| Layer | Question | Basis |
|-------|----------|-------|
| Row 2 **Net discount value** | Plan benefit at purchase? | `vest_fmv` vs `buy_price` on net shares |
| Row 3 **P&L**, charts, SOP | How did investment perform? | `net_buy_price` vs sale / current |

### Footer disclaimer (ESPP tab only)

Muted text below last section (after qualifying/disqualifying):

> Returns and P&L on this page use effective cost per received share (total payroll ÷ net shares per purchase). **Additional tax paid in cash outside the plan is not reflected in these calculations.**

---

## §A — Summary (v2)

Replace flat 9-tile grid with **3 rows + return strip**.

### Row 1 — Share counts

| Tile | Source | Notes |
|------|--------|-------|
| Gross Purchased | `Σ vest_quantity` | Integer qty |
| Net Received | `Σ net_quantity` | **ℹ️ tooltip:** `{tax_withheld}` shares withheld for tax (gross − net) |
| Currently Held | `net_received − sold` | |

**No** separate Tax Withheld tile.

### Row 2 — Money flow

| Tile | Value | Subtitle (optional, muted) |
|------|-------|---------------------------|
| Purchase Value | `Σ(gross × buy_price)` | Payroll contributed (gross shares) |
| Net Discount Value | `Σ((vest_fmv − buy_price) × net_shares)` | Discount on shares received |
| Realized Proceeds | `Σ(sale_price × sold_qty)` | Cash from sales; `—` if no sale prices |

### Row 3 — Performance

| Tile | Formula |
|------|---------|
| Realized P&L | `Σ(sale_price − net_buy_price) × sold_qty` |
| Unrealized P&L | `Σ(current_price − net_buy_price) × held_qty` |
| Total P&L | `realized + unrealized` (optional 3rd tile — **include**) |

Green/red by sign. `—` when `current_price` nil (unrealized / total).

### Return strip (below row 3)

Full-width muted bar:

```
Portfolio return: +23.5%  ·  Approx. XIRR 18.4% ℹ️
```

| Metric | Formula |
|--------|---------|
| Total return % | `(total_pnl / purchase_value) × 100` |
| Approx. XIRR | `compute_espp_xirr_from_lots/3`; label **Approx.** |

**XIRR tooltip:** Purchase date used as outflow; payroll was spread over enrollment — true XIRR may differ slightly.

### Layout notes

- Use 3-column grid per row (not 9 equal tiles in one grid)
- Currency toggle applies to all money tiles + strip amounts
- See canvas mock: `SummarySection`

### Acceptance

- [ ] Exactly 9 stat areas in 3 rows (not old 9-tile flat grid with Tax Withheld + XIRR as tiles)
- [ ] Net Received has tooltip with tax withheld share count
- [ ] Return strip shows total return % and XIRR together

---

## §B — Purchase lots table

### Heading

`Purchase Lots ({n})` — `id="espp-lots"`

### Columns (10 — no Lookback)

| Column | Source |
|--------|--------|
| Purchase Date | `vest_date` ascending |
| Gross | `vest_quantity` |
| Net | `net_quantity` |
| Buy Price ℹ️ | `metadata buy_price` |
| FMV | `vest_fmv` |
| Disc % | `(vest_fmv − buy_price) / buy_price × 100` |
| Sold | `sold_qty` |
| Held | `net − sold` |
| Real. P&L | `(sale_price − net_buy_price) × sold_qty` |
| Unreal. P&L | `(current_price − net_buy_price) × held_qty` |

### Buy Price header tooltip

> Discounted purchase price per share — typically 15% below the **lock-in (grant-date) price** for the ESPP offering. Payroll deducted at this price, not purchase-day market price (see FMV).

### Scroll + expand

| State | Behavior |
|-------|----------|
| Default | `max-height` ≈ 5 rows, `overflow-y: auto`, sticky thead |
| `n > 5` | Footer: “Showing 5 of {n} lots — scroll or expand” + **Show all {n} lots** |
| Expanded | Remove max-height; **Collapse table** button |

```elixir
assign :espp_lots_expanded, false
# event: toggle_espp_lots_table
```

### Acceptance

- [ ] Lookback column absent
- [ ] 5-row default scroll when `n > 5`
- [ ] Expand/collapse toggles max-height
- [ ] P&L columns use `net_buy_price` math

---

## §C — Sold share returns chart

**Section title:** Sold lot returns

### Purpose

Per purchase with `sold_qty > 0`: return **rate** on sold portion vs `net_buy_price`. One bar per purchase (aggregate multiple sell allocs).

### Encoding

| Element | Value |
|---------|-------|
| Chart type | Vertical bar |
| **Y-axis** | **Return %** (not dollars) |
| Bar height | `return_pct` |
| X-axis | Purchase date (`Jun '23`) |
| Zero line | 0% dashed baseline |
| Color | Green if `return_pct ≥ 0`, red if negative |
| Bar label | `+12.3%` / `-4.1%` on/near bar |

```
return_pct = realized_pnl / (net_buy_price × sold_qty) × 100
```

### Hover (required)

```
Jun 30, 2023
Sold: 28.3 shares (partial — 12.5 held)
Net buy price: $131.45 · Avg sale: $142.80
Proceeds: $4,041 · P&L: +$432 (+12.0%)
```

Currency toggle affects **hover $** only; Y-axis stays %.

### Partial sales

- One bar per purchase; partial noted in hover and optional `*` on x-label + footnote.

### Chart chrome

- Draw **solid Y-axis** (left) and **X-axis** (bottom) on plot area bounds
- 0% baseline remains a **dashed** reference line inside the plot (distinct from X-axis)
- Y-axis tick labels: `%` values; X-axis: purchase date labels per §E thinning

### Y-axis domain (dynamic)

Scale to data; **always include 0%** on the axis, but do **not** mirror a fake negative range when all returns are positive.

| Data | `yMin` | `yMax` |
|------|--------|--------|
| All positive | `0` | `max(return_pct) × 1.12`, floor span 8% if tiny |
| All negative | `min(return_pct) × 1.12` | `0` |
| Mixed | symmetric ±`max(abs(min), abs(max)) × 1.12` so 0 stays centered |

Implementation: same rule in `charts.ex` `build_pnl_bars` / `pnl_bar_chart`.

### Acceptance

- [ ] Bar height proportional to %, not dollar P&L
- [ ] Hover shows qty, proceeds, $ P&L, %
- [ ] Visible X + Y axis lines on sold and unsold charts
- [ ] Refactor `build_pnl_bars` / `pnl_bar_chart` accordingly

---

## §D — Unsold lots chart

**Section title:** Open lots — cost vs current

### Purpose

Per open lot: cost (`net_buy_price`) vs current market; unrealized P&L.

### Encoding

| Element | Spec |
|---------|------|
| Chart type | **Scatter** (dots only — **no connecting polyline**) |
| X-axis | Purchase date |
| Y-axis | Price per share |
| Dot Y | `net_buy_price` |
| Reference line | Horizontal dashed **current price**, labeled “Current” |
| Dot color | Green if `current > net_buy_price`; red if below |
| Hover | Unrealized $ and % + held qty |

```
unrealized_pnl = (current_price − net_buy_price) × held_qty
unrealized_pct = (current_price − net_buy_price) / net_buy_price × 100
```

### Chart chrome

- Same **solid Y-axis** + **X-axis** as §C
- Current price line stays **dashed** (reference, not axis)

### Acceptance

- [ ] Dots at `net_buy_price`, not raw `buy_price`
- [ ] No gray connector line between dots
- [ ] Visible X + Y axis lines
- [ ] Current price reference line hidden when price nil
- [ ] Refactor `cost_basis_chart`

---

## §E — Chart density (§C + §D)

When many lots (`n * 36px > plot_width`):

1. Grow SVG width; wrap in `overflow-x: auto`
2. Thin x-labels (every 2nd / year-only when crowded); full date in hover always
3. Caption when crowded: “{n} purchases — scroll to see all”
4. Shared `chart_layout/2` in `charts.ex` for both charts

Canvas mock: toggle **“16 lots (§E scroll)”** in prototype bar.

### Acceptance

- [ ] Horizontal scroll when > ~16 lots on 600px plot
- [ ] Labels don’t overlap at n=20

---

## §F — Sell-on-Purchase Analysis

### Purpose

*Was holding better than exiting every lot at purchase-day FMV on the next trading day?*

**Not** “should I sell today.” Current market → summary row 3, return strip, §D chart.

### Formulas

```
day1_gain          = sell_on_purchase − purchase_value
total_pnl          = realized_pnl + unrealized_pnl   # net_buy_price basis
extra_from_holding = total_pnl − day1_gain
holding_better     = extra_from_holding > 0
```

Hide entire section when `sell_on_purchase` or `purchase_value` nil.

### Layout

```
Section title + (?) tooltip
Context line (one sentence)
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ Day-1 gain  │ │ Extra from  │ │ Total P&L   │  equal cards, bg-base-200
│  +₹4.0L     │ │  holding    │ │  (actual)   │
└─────────────┘ └─────────────┘ └─────────────┘
┌─ VERDICT (success/warning) ─────────────────┐
└─────────────────────────────────────────────┘
┌─ SCOPE BANNER (info, separate block) ───────┐
│ Not a comparison to today's stock price      │
└─────────────────────────────────────────────┘
```

### Three cards

| Card | Value | Subtitle | Color |
|------|-------|----------|-------|
| Day-1 gain | `day1_gain` | Discount at purchase FMV (next trading day) | Always green |
| Extra from holding | `extra_from_holding` | On top of day-1 gain | Green/red by sign |
| Total P&L | `total_pnl` | Realized + unrealized (your actual outcome) | Green/red by sign |

**Remove** “Avg. return % / lot” card (current M22).

### Verdict banner (F.5)

**If holding better:**

> **Holding was worth it** — you are **{extra}** ahead versus selling everything at purchase-day FMV on the next trading day (on top of **{day1_gain}** day-1 discount).

**If not:**

> **Day-1 exit would have been better** — selling at purchase-day FMV on the next trading day would have left you **{abs(extra)}** more than your actual outcome (day-1 discount was **{day1_gain}**).

Styles: full width, `text-base`–`text-lg`, `font-semibold`, `py-4 px-5`, success/warning background tint.

### Scope banner (F.6) — **separate block, equally prominent**

**Not** a muted subline inside the verdict.

**Title:** Not a comparison to today's stock price

**Body:** Compares actual realized + unrealized P&L to a purchase-day exit. Does not evaluate selling current holdings at `{current_price}`. Point to summary row 3, return strip, unsold chart.

Styles: `border-2 border-info/40 bg-info/10 rounded-xl py-4 px-5`.

### Section tooltip (?)

> Compares total P&L (net buy price per share) against a hypothetical where every net share was sold at purchase-date FMV on the next trading day. Purchase value = gross shares × buy price. Excess tax paid in cash is not included (see page disclaimer).

### `espp_sop_analysis/2` return shape

```elixir
%{
  day1_gain: Decimal.t(),
  extra_from_holding: Decimal.t(),
  total_pnl: Decimal.t(),
  holding_better: boolean()
}
```

Remove `avg_return_pct`.

### Acceptance

- [ ] Three cards + verdict + **separate** scope banner
- [ ] Verdict never mentions current price or “sell today”
- [ ] Currency on cards + verdict amounts

---

## §G — Qualifying / disqualifying (unchanged)

Collapsible below SOP. US tax only — India filers can ignore.

---

## Implementation file map

| UX section | Primary files |
|------------|---------------|
| Page shell | `history_live.ex` |
| Summary v2 | `history.ex`, `history_live.ex` |
| `net_buy_price` | `silver_builder.ex`, `history.ex` |
| Purchase table | `history_live.ex` |
| Sold chart | `charts.ex`, `history_live.ex` |
| Unsold chart | `charts.ex`, `history_live.ex` |
| Chart density | `charts.ex` |
| SOP | `history_live.ex` (`espp_sop_analysis/2`) |
| Disclaimer | `history_live.ex` (ESPP section footer) |

---

## Open / TBD

| Item | Status |
|------|--------|
| §C chart section title | **Sold lot returns** (locked) |
| §D chart section title | **Open lots — cost vs current** (locked) |
| RSU tab UX | **`ux-design-rsu.md`** + §G (locked) |
| Total P&L as row 3 tile | **Include** (locked in this doc) |

---

## Claude implementation checklist

1. Read this file + `design.md` + `requirements.md`
2. Accept/Reject any drift vs `cursor-feedback-on-specs.md` changelog
3. Update `requirements.md`, `design.md`, `tasks.md`, `test-plan.md` to match
4. Implement in order: `net_buy_price` ingestion → `history.ex` → `charts.ex` → `history_live.ex`
5. Verify against canvas mock (visual) and `test-plan.md` (automated)
6. Do **not** add parallel `ux-feedback-*.md` files
