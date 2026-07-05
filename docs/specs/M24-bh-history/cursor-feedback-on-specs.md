# Cursor Feedback on M24 Specs

**Status:** Living document — append sections here; do not create separate feedback files per topic.  
**Audience:** Claude / implementer reviewing M24 on `feature/m22-multi-symbol`  
**Baseline:** M24 spec + `HistoryLive` / `History` on M22 branch (may diverge from committed `requirements.md` until merged).

**Implementable UX spec (for Claude):** `ux-design.md` in this folder — authoritative layout, copy, charts, acceptance criteria.  
**Visual mock — ESPP (in git):** `m24-bh-history.canvas.tsx` in this folder.  
**Visual mock — RSU (in git):** `m24-rsu-history.canvas.tsx` in this folder.  
**Live Canvas preview:** `canvases/m24-bh-history.canvas.tsx` (ESPP §A–F) · `canvases/m24-rsu-history.canvas.tsx` (RSU §G) — copy from repo when mocks change.

---

## Changelog

| Date | Section | Summary |
|------|---------|---------|
| 2026-06-10 | §A Global | FMV P&L basis, summary v2 layout, return strip |
| 2026-06-10 | §B Purchase lots table | Drop Lookback; scroll/expand; Buy Price tooltip |
| 2026-06-10 | §C Realized returns chart | Rename from “Sold Lots”; $ + % encoding |
| 2026-06-10 | §A / §C revise | **Revert FMV P&L** — investment returns vs `buy_price`; sold chart **% primary** |
| 2026-06-10 | §A.1b | **Net buy price** per lot for P&L and return % |
| 2026-06-10 | §A.1c | Persist `net_buy_price` at **BH ingestion**; History-only; disclaimer |
| 2026-06-10 | §D | Unsold lots chart — dots at `net_buy_price`, current price line, hover unrealized P&L |
| 2026-06-10 | §E | Chart density — dynamic layout when many lots; x-axis anti-clutter |
| 2026-06-10 | §F | Sell-on-purchase — 3 cards + **verdict + scope banner** (not vs current price) |
| 2026-06-10 | §F v2 | Scope exclusion **as prominent as verdict** — not a muted subline |
| 2026-06-10 | §G RSU | Income lens — section order, two $ charts, grant table; drop tax/velocity/YoY |
| 2026-06-10 | §G.5 | Sold vs held **removed from proposal** — BH lacks tranche sell linkage without G&L |
| 2026-06-10 | §G + §2 | `requirements.md` §2 rewritten; `design.md` RSU shape updated |
| 2026-06-10 | §G.10 | Full spec pack synced — `tasks.md` Task 13, `test-plan.md`, `ux-design-rsu.md` |

---

## Master decisions (locked)

| # | Topic | Decision |
|---|-------|----------|
| 1 | P&L basis (ESPP performance) | **`net_buy_price`** per lot — stored at ingestion; **History page only** — §A.1b–c |
| 11 | Excess cash tax | **Not modeled** — disclaimer on ESPP History footer — §A.1c |
| 2 | Summary layout | **v2** — 3 rows + return strip (§A) |
| 3 | Tax withheld | **Not a tile** — tooltip on Net Received |
| 4 | Discount tile | **Net discount** = `Σ((vest_fmv − buy_price) × net_shares)` — row 2 only; not P&L |
| 5 | Row 2 third tile | **Realized proceeds** |
| 6 | XIRR placement | **Return strip** below row 3; portfolio-only |
| 7 | Total return % | **Yes** — alongside XIRR in strip |
| 8 | Purchase table | **No Lookback**; 5-row scroll + expand (§B) |
| 9 | Sold chart **name** | **TBD** — not “Sold Lots”; not “Realized returns by purchase” |
| 10 | Sold chart encoding | **Bar height = return %** vs `buy_price`; **hover** for $ proceeds, P&L, qty |
| 12 | RSU mental model | **Income at vest** — not investment P&L (contrast ESPP §A) — §G |
| 13 | RSU hero chart | **Annual vest income ($)** by calendar year — not YoY % — §G.2 |
| 14 | RSU grant vs vest charts | **Two separate line charts** — do not merge timelines — §G.2–3 |
| 15 | RSU summary | **2 rows** + **info icon** on every tile — §G.1 |
| 16 | RSU dropped sections | Tax withheld, vesting velocity, YoY %, composition snapshot — §G.6 |
| 17 | RSU post-vest sells | **Out of scope** — no section; BH lacks tranche sell linkage without G&L — §G.6 |

---

## §A — Global: P&L basis & summary tiles

### A.1 P&L basis — investment return vs `net_buy_price`

**Use `net_buy_price` per lot for every P&L and return % on the ESPP History page** (summary row 3, purchase table, sold chart, unsold chart, sell-on-purchase `total_pnl`). Row 2 **Purchase Value** still uses raw `buy_price × gross` (total payroll).

```
realized_pnl   = Σ(sale_price − net_buy_price) × sold_qty
unrealized_pnl = Σ(current_price − net_buy_price) × held_qty
return_pct     = realized_pnl / (net_buy_price × sold_qty) × 100
```

**Two layers (do not mix):**

| Layer | Question | Basis |
|-------|----------|-------|
| Row 2 **Net discount** | What plan benefit at purchase? | `vest_fmv` vs `buy_price` |
| Row 3 **P&L**, charts, sell-on-purchase | How did my **investment** do? | `net_buy_price` vs sale/current |

FMV-based P&L (2026-06-10 draft) **rejected**. Raw `buy_price` P&L **rejected** when tax shares withheld — use `net_buy_price` (§A.1b).

**Touches:** `silver_builder.ex` (ingestion), `requirements.md` §3.1–3.4, `design.md`, `history.ex`, `history_live.ex`, `charts.ex`, tests.

### A.1b Net buy price per lot (tax withholding)

Payroll is deducted on **gross** shares at **buy_price**, but the employee only **receives net** shares after tax withholding. Cost per **sellable** share is higher than `buy_price` when `tax_withheld_qty > 0`.

**Example:**

| Field | Value |
|-------|-------|
| buy_price | $100 / sh (discounted) |
| gross_shares | 50 |
| net_shares | 40 |
| Cash out (payroll) | $100 × 50 = **$5,000** |
| **net_buy_price** | $5,000 ÷ 40 = **$125 / sh** |

Formula:

```
lot_investment     = buy_price × gross_shares
net_buy_price      = lot_investment / net_shares     # when net_shares > 0
                   = buy_price                         # when gross = net (no tax shares)
```

**Return on sold portion** (per purchase lot):

```
realized_pnl = (sale_price − net_buy_price) × sold_qty
return_pct   = realized_pnl / (net_buy_price × sold_qty) × 100
```

Sell 30 sh at $150: P&L = (150 − 125) × 30 = **$750**; return = **+20%** (not +50% using raw $100 buy price).

**Do not** use raw `buy_price` alone for P&L / return % when tax shares were withheld — that understates cost per received share.

**Unrealized (held):**

```
unrealized_pnl = (current_price − net_buy_price) × held_qty
```

**Unchanged:** Row 2 **Purchase Value** = `Σ(gross × buy_price)` (total payroll). **Net discount** still uses `vest_fmv` vs `buy_price` on gross/net per existing formula.

**Data model:** We only calculate from BH fields (gross, net, buy_price, tax shares). No cash tax payments in source data.

---

### A.1c Persist `net_buy_price` at BH ingestion (History-only)

**When:** ESPP tranche insert during **Benefit History** Silver build (`silver_builder.ex` — ESPP purchase parent rows).

**Where stored:** `tranches.metadata_json["net_buy_price"]` alongside existing `buy_price`.

**Computation at ingestion:**

```elixir
buy_price  = Purchase Price from BH parent row
gross      = Purchased Qty. (vest_quantity)
net        = Net Shares (net_quantity)

net_buy_price =
  if net > 0 and buy_price and gross do
    Decimal.div(Decimal.mult(buy_price, gross), net)
  else
    buy_price   # fallback when gross = net or missing tax split
  end
```

Persist as string in metadata (SafeDecimal convention). Recompute on every Silver rebuild from Bronze — not user-editable.

**Scope — History analysis ONLY:**

| Consumer | Use `net_buy_price`? |
|----------|----------------------|
| `StockPlan.History` / `HistoryLive` ESPP tab | **Yes** — all P&L, return %, sell-on-purchase `total_pnl` |
| Tax Centre, capital gains, Schedule FA, portfolio | **No** — keep existing cost-basis rules |
| Sell Advisor | **No** |

`History.build_espp_lots/4` reads `net_buy_price` from tranche metadata (fallback: compute from gross/net/buy if missing for old ingestions).

**Every ESPP History P&L path must use `net_buy_price`:**

- Summary row 3 (realized / unrealized / total P&L, total return %)
- Purchase lots table (Real. / Unreal. P&L columns)
- Sold-share returns chart (`return_pct`, hover $ P&L)
- Unsold chart (dot Y = `net_buy_price` vs current)
- Sell-on-purchase opportunity (`total_pnl = realized + unrealized`, both `net_buy_price`-based)

**Table display:** **Buy Price** column = plan quoted `buy_price` ($100). P&L math uses `net_buy_price` ($125). Hover/tooltip may show both.

---

### A.1d Disclaimer (ESPP History footer)

Muted text at bottom of **ESPP tab** (below qualifying/disqualifying or last section):

> Returns and P&L on this page use effective cost per received share (total payroll ÷ net shares per purchase). **Additional tax paid in cash outside the plan is not reflected in these calculations.**

Do not show on RSU tab, Tax Centre, or Portfolio.

---

### A.2 Summary layout v2

Replace flat **9-tile grid** with **3 rows + return strip**.

#### Row 1 — Share counts

| Tile | Source |
|------|--------|
| Gross Purchased | `Σ vest_quantity` |
| Net Received ℹ️ | `Σ net_quantity` — tooltip: tax withheld shares (`gross − net`) |
| Currently Held | `net_received − sold` |

#### Row 2 — Money flow

| Tile | Formula | Subtitle |
|------|---------|----------|
| Purchase Value | `Σ(gross × buy_price)` | Payroll contributed (gross shares) |
| Net Discount Value | `Σ((vest_fmv − buy_price) × net_shares)` | Discount on shares received |
| Realized Proceeds | `Σ(sale_price × sold_qty)` | Cash from sales |

#### Row 3 — Performance (`buy_price` basis)

| Tile | Formula |
|------|---------|
| Realized P&L | `Σ(sale_price − net_buy_price) × sold_qty` per lot |
| Unrealized P&L | `Σ(current_price − net_buy_price) × held_qty` per lot |
| Total P&L *(optional)* | `realized + unrealized` |

#### Return strip (below row 3)

```
Portfolio return: +42.3% total  ·  Approx. XIRR 18.4% ℹ️
```

| Metric | Formula |
|--------|---------|
| Total return % | `(total_pnl / purchase_value) × 100` |
| Approx. XIRR | existing `compute_espp_xirr_from_lots/3` |

No separate sold/unsold XIRR in v1.

---

### A.3 Sell-on-purchase

Full UX spec: **§F** (3 cards + prominent verdict). Row 2 already shows **Net Discount Value** (= day-1 gain); §F may repeat day-1 gain in card 1 for self-contained section — acceptable.

---

### A.4 Proposed `espp_analysis().summary` shape

```elixir
%{
  gross_purchased: Decimal.t(),
  net_received: Decimal.t(),
  tax_withheld: Decimal.t(),      # tooltip only
  currently_held: Decimal.t(),
  purchase_value_usd: Decimal.t(),
  purchase_value_inr: Decimal.t() | nil,
  net_discount_usd: Decimal.t(),  # was total_discount_*
  net_discount_inr: Decimal.t() | nil,
  realized_proceeds_usd: Decimal.t() | nil,
  realized_proceeds_inr: Decimal.t() | nil,
  sell_on_purchase_usd: Decimal.t(),
  sell_on_purchase_inr: Decimal.t() | nil,
  realized_pnl_usd: Decimal.t() | nil,
  realized_pnl_inr: Decimal.t() | nil,
  unrealized_pnl_usd: Decimal.t() | nil,
  unrealized_pnl_inr: Decimal.t() | nil,
  total_pnl_usd: Decimal.t() | nil,
  total_pnl_inr: Decimal.t() | nil,
  total_return_pct: Decimal.t() | nil,
  approximate_xirr: float() | nil
}
```

**`espp_lot()` — add field:**

```elixir
buy_price:     Decimal.t() | nil   # from metadata — plan quoted price (display)
net_buy_price: Decimal.t() | nil   # from metadata — all History P&L math
```

---

### A.5 Sections not yet reviewed (ESPP)

| Section | Status |
|---------|--------|
| Unsold chart | **§D** — locked |
| Sell-on-purchase | **§F** — locked |
| Qualifying/disqualifying | Unchanged |
| RSU tab | **§G** — locked |

---

## §G — RSU tab (income lens)

**Status:** Locked (2026-06-10)  
**Visual mock:** `m24-rsu-history.canvas.tsx` (git + `canvases/`)  
**Official spec:** `requirements.md` §2 rewritten to match §G (2026-06-10).

### G.0 Mental model (contrast ESPP)

| | ESPP tab | RSU tab |
|---|----------|---------|
| Lens | **Investment** — `net_buy_price`, return %, sold/unsold charts | **Compensation / income** — grant FMV → vest FMV |
| Primary question | How did my purchases perform? | How much RSU income landed each year? |
| Post-vest sells | Purchase-level sell qty from BH + G&L | **Not shown** — BH has no tranche↔sale linkage without G&L |

Do **not** show RSU **return %**, **proceeds**, **unrealized**, or **sold vs held** anywhere on the RSU tab. Benefit History alone does not establish which tranche sold how many shares (contrast ESPP purchase-level SELL events).

---

### G.1 Summary tiles (2 rows + info icons)

**Every tile** has a circled **i** beside the label; **hover** shows definition (`title` tooltip in LiveView — same pattern as ESPP Buy price ℹ).

#### Row 1 — Income snapshot

| Tile | Source | Tooltip gist |
|------|--------|--------------|
| **Grants** | Count of RSU `origins` for symbol | Number of grant records in BH |
| **Grant promise** | `Σ(total_quantity × origin_fmv)` | Total value at grant-date FMV |
| **Income recognized** | `Σ(vest_quantity × vest_fmv)` on VESTED tranches | Ordinary income at vest — fact from BH |
| **Still to vest (est.)** | `Σ(unvested vest_quantity × current_price)` | **UI-only** projection — not received income |

Respects INR/USD toggle on money tiles.

#### Row 2 — Shares + drift

| Tile | Source | Tooltip gist |
|------|--------|--------------|
| **Vested (net shares)** | `Σ net_quantity` VESTED | Sellable shares after tax withholding |
| **Unvested (gross shares)** | `Σ vest_quantity` UNVESTED | Scheduled, not yet delivered |
| **Vest vs grant drift** | See formula below | Vest FMV vs grant FMV on vested shares |

**Vest vs grant drift %:**

```
vested_promise_at_grant = Σ per grant: (vested_gross_qty / granted_qty) × grant_promise
income_recognized       = Σ(vest_quantity × vest_fmv)  # already in row 1
drift_pct               = (income_recognized / vested_promise_at_grant − 1) × 100
```

Positive = stock worth more at vest than at grant for shares already vested.

**Remove from RSU summary (old spec):** Vested/Sold/Held dollar tiles, Realized proceeds, “Total compensation outlook”, combined recognized+unvested strip.

---

### G.2 Section order (page layout)

| # | Section | Notes |
|---|---------|-------|
| 1 | Summary | §G.1 |
| 2 | **RSU income by year** | Vest FMV chart — §G.3 |
| 3 | **Grant breakdown** | Table — §G.4 |
| 4 | **New grant value by year** | Grant FMV chart — §G.3 |
| 5 | **Disclaimer** | Still-to-vest uses current price |

---

### G.3 Charts — two separate line charts (absolute $)

**Do not** merge grant promise, recognized, outlook, or YoY % on one chart.

#### Chart A — RSU income by year (hero)

- **Question:** How much RSU compensation vested each calendar year? (Like tracking annual salary growth.)
- **X-axis:** Calendar year
- **Y-axis:** Total vest-date income in selected currency — `Σ(vest_quantity × vest_fmv)` per year
- **Type:** Line chart with area fill; show value labels when ≤8 years
- **Caption:** Source = VESTED tranches from BH snapshot

#### Chart B — New grant value by year

- **Question:** When was fresh equity comp awarded?
- **X-axis:** Calendar year of **grant date**
- **Y-axis:** `Σ(granted_qty × origin_fmv)` for grants **issued** that year
- **Type:** Line chart with area fill
- **Callout below:** Large grant in year N appears here immediately but flows into Chart A only as tranches vest in later years.

**Dropped:** §2.2 cumulative vest **bar** (replaced by Chart A line), §2.7 **YoY %** line, “Income trajectory” multi-series chart, “Composition today” stacked bar.

---

### G.4 Grant breakdown table

| Column | Source |
|--------|--------|
| Grant # | `origins.grant_number` |
| Grant date | `origins.origin_date` |
| Granted | `origins.total_quantity` |
| Grant promise | `total_quantity × origin_fmv` |
| Recognized | `Σ(vest_quantity × vest_fmv)` VESTED for this origin |
| Still to vest | `unvested_gross_qty × current_price` — `—` if fully vested |
| vs promise | `(recognized + still_to_vest) / grant_promise − 1` — color green/red |

**Sort:** Grant date **descending** (newest first).

**Scroll / expand (same as ESPP §B):**

- Default **5 rows** visible
- `max-height` + vertical scroll when `grants.length > 5` and collapsed
- **Show all N grants** / **Collapse table** when `grants.length > 5`
- Footer: `Showing 5 of N grants — scroll or expand`

**Remove columns:** Vested (net), Sold, Proceeds, Unrealized, Return %.

---

### G.5 Out of scope / dropped (not in RSU proposal)

| Item | Reason |
|------|--------|
| **Sold vs held** / §2.5 counterfactual | BH alone has no tranche↔sale linkage; need G&L + `sale_allocations` before any post-vest RSU sell story |
| Tax withheld at vest chart | Tax-compliance — Tax Centre if needed, not income-growth |
| Vesting velocity | Redundant with annual $ income chart |
| YoY % income growth | Trend read from **absolute $** chart |
| Composition today bar | Redundant with summary; unclear |
| Grant table Return % / unrealized / Sold / Proceeds | Investment lens — wrong for RSU tab |
| Summary: Sold / Realized proceeds / Currently held | No reliable sell story on BH-only RSU |

**Future (not M24):** Post-vest RSU sold/held analytics only after G&L milestone.

---

### G.6 Backend additions (`history.ex`)

| Field | Computation |
|-------|-------------|
| `still_to_vest_usd` | `Σ vest_quantity` where `status == UNVESTED` × `current_price` (nil if no price) |
| `unvested_gross_shares` | `Σ vest_quantity` UNVESTED |
| `vest_vs_grant_drift_pct` | §G.1 formula |
| `grants_by_year` | Group origins by grant year → sum grant promise |
| `income_by_year` | Existing `compute_rsu_income_by_year` — used for Chart A |

Remove or stop rendering: `velocity`, `yoy`, `counterfactual`, `sold_vs_held`, grant-row `return_pct` / `unrealized_value` / `realized_proceeds`.

**Invariant:** Still-to-vest @ current price is **never stored** as financial fact — UI/Gold query time only.

---

### G.7 Disclaimer (RSU tab footer)

> Still-to-vest estimates use today's stock price — not income you have received. Income recognized uses vest-date FMV from your Benefit History upload.

---

### G.8 Claude follow-up (implementation)

- [x] Spec pack updated (see **§G.10**)
- [ ] **Task 13** in `tasks.md` — refactor `history.ex` + `history_live.ex` + charts
- [ ] Remove legacy RSU UI: tax bar, counterfactual, velocity, YoY, old summary tiles
- [ ] Add `HintStat` / tooltip pattern on all 7 summary tiles

---

### G.10 Spec pack update — for Claude review (2026-06-10)

**Accept/Reject this block before coding Task 13.** All paths under `docs/specs/M24-bh-history/`.

| File | What changed |
|------|----------------|
| **`requirements.md` §2** | Full rewrite: income lens, 5-section order, 2-row summary + ℹ, two $ line charts, grant table §2.4, disclaimer. **Removed:** §2.3 tax, §2.5 counterfactual/sold-vs-held, §2.6 velocity, §2.7 YoY. Explicit out-of-scope: post-vest sell without G&L. |
| **`design.md`** | `rsu_analysis()` new summary fields; `income_by_year` + `grants_by_year`; `grant_row()` shape; compute-function table; removed counterfactual/velocity/yoy/tax from RSU; LiveView tree + chart table updated. |
| **`tasks.md`** | **Task 13** added (RSU refactor checklist). Task 5.11 marked legacy. Deferred: RSU sold/hold until G&L. |
| **`test-plan.md`** | RSU unit tests rewritten for §G; removed tax/counterfactual/velocity/YoY cases; LiveView + manual smoke updated. |
| **`ux-design-rsu.md`** | **New** — authoritative RSU tab UX (companion to ESPP `ux-design.md`). |
| **`ux-design.md`** | Pointer to `ux-design-rsu.md`; RSU no longer “deferred”. |
| **`m24-rsu-history.canvas.tsx`** | Visual mock — matches §G layout (no Sold vs held). |

**Locked RSU page (implement exactly this order):**

1. Summary — 2 rows, 7 tiles, info icon on each  
2. RSU income by year — line chart (vest FMV $)  
3. Grant breakdown — table, newest first, 5-row scroll + expand  
4. New grant value by year — line chart (grant FMV $)  
5. Disclaimer  

**Do not implement on RSU tab:** tax withheld chart, vesting velocity, YoY %, composition bar, counterfactual, sold vs held, grant-table sold/proceeds/return %, summary sold/proceeds tiles.

**Code delta vs current `history_live.ex`:** Existing RSU UI is the *old* spec — Task 13 replaces it; do not patch incrementally on top of counterfactual/velocity blocks.

**ESPP work unchanged** — Tasks 7–12 + §A–F still apply; RSU Task 13 is parallel-safe.

---

## §B — Purchase lots table (§3.2)

### B.1 Column changes

**Remove:** Lookback (`origin_fmv`) — lock-in context via Buy Price header tooltip only.

**Keep (10 columns):**

| Column | Source | Notes |
|--------|--------|-------|
| Purchase Date | `vest_date` | Sort ascending |
| Gross | `vest_quantity` | |
| Net | `net_quantity` | |
| Buy Price ℹ️ | `metadata buy_price` | Header tooltip — see B.2 |
| FMV | `vest_fmv` | Purchase-day market price (context for discount) |
| Disc % | `(vest_fmv − buy_price) / buy_price × 100` | |
| Sold | `sold_qty` | |
| Held | `net − sold` | |
| Real. P&L | `(sale_price − net_buy_price) × sold_qty` | green/red |
| Unreal. P&L | `(current_price − net_buy_price) × held_qty` | `—` if no price |

Currency toggle on money columns.

### B.2 Buy Price header tooltip

> Discounted purchase price per share — typically 15% below the **lock-in (grant-date) price** for the ESPP offering. Payroll deducted at this price, not purchase-day market price (see FMV).

Header-level tooltip sufficient for v1; no per-row lock-in column.

### B.3 Scroll + expand (many lots)

| State | Behavior |
|-------|----------|
| Default | `max-height` ≈ **5 rows**, `overflow-y: auto`, **sticky thead** |
| `n > 5` | Footer: “Showing 5 of {n} lots — scroll or expand” + **Show all {n} lots** |
| Expanded | Remove max-height; **Collapse table** button |

```elixir
:espp_lots_expanded :: boolean()  # default false
# event: toggle_espp_lots_table
```

Heading: `Purchase Lots ({n})`. Keep `id="espp-lots"`.

---

## §C — Sold-share returns chart (§3.3, was “Sold Lots”)

### C.1 Purpose

**For each ESPP purchase, compare return rate on the sold portion vs `net_buy_price`.**

User question: *“How did each sale do as a return on my investment?”* — not dollar magnitude (big lot vs small lot), not FMV, not portfolio XIRR.

One bar per **purchase** where `sold_qty > 0` (partial or full sale). Multiple sell allocations on same purchase → one aggregated bar.

### C.2 Naming

**TBD** — decide later. Avoid “Sold Lots” (implies fully sold).

Working subtitle (not final):

> Return on **net buy price** (effective cost per received share) for shares sold from each purchase (partial or full).

Do **not** reference FMV in this chart’s copy.

### C.3 Chart encoding — **% primary, $ on hover**

| Element | Value | Why |
|---------|-------|-----|
| **Y-axis** | **Return %** | Comparable across lots; big sale vs few shares doesn’t dominate |
| **Bar height** | `return_pct` per purchase | See formula below |
| **X-axis** | Purchase date (`Jun '23`) | |
| **Zero line** | 0% baseline | Break-even vs buy price |
| **Color** | Green / red by sign of % | |
| **Bar label** | `+12.3%` / `-4.1%` on bar (optional if axis is clear) | |

**Per-purchase return % (sold portion only):**

```
net_buy_price   = (buy_price × gross_shares) / net_shares
cost_basis_sold = net_buy_price × sold_qty
realized_pnl    = Σ(sale_price − net_buy_price) × sold_qty   # per alloc
return_pct      = realized_pnl / cost_basis_sold × 100
```

**Rejected:** bar height = dollar P&L — misleads when sold quantities differ; user cares about **rate**, not which bar is tallest.

### C.4 Hover / tooltip (required)

Native SVG `<title>` or equivalent. Example:

```
Jun 30, 2023
Sold: 28.3 shares (partial — 12.5 held)
Net buy price: $127.50 · Avg sale: $142.80
Proceeds: $4,041 · P&L: +$432 (+12.0%)
```

Show on hover: purchase date, sold qty, held qty if partial, buy price, effective sale price (proceeds/sold_qty), proceeds, dollar P&L, return %.

Summary row **Realized P&L** still sums dollar P&L across lots — chart does not need bar height = $ to tie back.

### C.5 Partial sales

- One bar per purchase, not per sell order.
- X-axis: date only by default; partial indicated in **hover** (and optional `*` on label + footnote).

### C.6 Implementation notes

- Refactor `build_pnl_bars` → scale by `pnl_pct` not `realized_pnl` float; Y ticks as `%`.
- Currency toggle affects **hover proceeds/P&L**, not Y-axis (unitless %).
- `requirements.md` §3.3: update formulas and chart description.

---

## §D — Unsold lots chart (§3.4, was `cost_basis_chart`)

### D.1 Purpose

**For each open purchase lot: is market price above or below my effective cost (`net_buy_price`), and what is the unrealized P&L?**

Mirror of §C for the **held** portion — investment lens, not FMV.

### D.2 User proposal (accepted with one tweak)

| Element | Spec |
|---------|------|
| **X-axis** | Purchase date (one dot per unsold lot where `held_qty > 0`) |
| **Y-axis scale** | Price per share ($ / ₹) |
| **Dot Y position** | **`net_buy_price`** for that lot |
| **Reference line** | Horizontal dashed **current symbol price** (indigo), labeled “Current” |
| **Dot color** | **Green** if `current_price > net_buy_price`; **red** if below (unrealized loss) |
| **Hover** | Unrealized P&L for that lot (required) |

**Unrealized per lot:**

```
unrealized_pnl = (current_price − net_buy_price) × held_qty
unrealized_pct = (current_price − net_buy_price) / net_buy_price × 100
```

**Hover example:**

```
Jun 28, 2024
Held: 43.5 shares
Net buy: $168.40 · Current: $453.21
Unrealized: +$12,390 (+169.1%)
```

Include held qty, net buy price, current price, unrealized $ and %.

### D.3 Chart type — scatter (not bar, not connected line)

**Sold chart (§C)** = vertical **bar chart** (% return). **Unsold chart (§D)** = **scatter dots** + current price line. **Not the same chart type** — different questions:

| Chart | Question | Why not bar for unsold |
|-------|----------|------------------------|
| §C Sold | Return % on sold shares | Bars compare rates |
| §D Unsold | Cost vs current **price level** | Need Y = $/sh + reference line at market; bars would drop the “current price” visual |

User accepted scatter for unsold. OK to keep §C as bar chart.

**Do not** connect dots with a polyline (remove gray connector from current `cost_basis_chart`).

### D.4 Alternative considered (not recommended for v1)

**Horizontal bar chart of unrealized return %** per lot — symmetric with §C.

Rejected for unsold — loses cost vs current price at a glance. See §E for density rules shared with §C.

### D.5 Naming

**TBD** (like §C). Working subtitle:

> Open lots: effective cost per share vs current market price. Green = profitable to sell; red = underwater.

### D.6 Implementation

- Refactor `cost_basis_chart` → use `net_buy_price` from metadata (not raw `buy_price`)
- Remove or do not add connecting polyline between dots
- `current_price` nil → hide reference line; dots still at net buy; unrealized `—` in hover
- Currency toggle: Y-axis ticks and hover $ in selected currency

---

## §E — Chart density (many lots) — §C + §D

**Problem:** Current `charts.ex` uses fixed `viewBox` 600×200 with one x-label per lot. **10+ lots** → overlapping / unreadable x-axis (reported in M22 implementation).

Applies to **both** sold bar chart (§C) and unsold scatter (§D).

### E.1 Dynamic slot width

```
n           = count of lots on chart
min_slot    = 36px   # minimum horizontal space per lot (bar or dot)
plot_width  = 600 - ml - mr   # existing margins

if n * min_slot > plot_width:
  svg_width = n * min_slot + ml + mr   # grow canvas width
  wrap in horizontal scroll container (overflow-x: auto)
else:
  svg_width = 600   # default
  slot = plot_width / n
```

Container: `overflow-x: auto`, `w-full`, optional subtle hint: “Scroll chart →” when `n > floor(600/min_slot)`.

### E.2 X-axis label thinning (always apply when crowded)

```
max_labels ≈ floor(plot_width / 48)   # ~48px per label readable

if n <= max_labels:
  show every label
else if n <= 2 * max_labels:
  show every 2nd label (always first + last)
else:
  label format → year only: '22, '23, '24
  show label only where year changes OR every 3rd lot
  full purchase date **only in hover**
```

Label format by density:

| n | Format |
|---|--------|
| ≤ 12 | `Jun '23` |
| 13–24 | `'23` or `'24` (year at first lot of each year) |
| > 24 | year/quarter `Q2 '23` at quarter boundaries + hover for full date |

Never rotate labels 45° in SVG v1 — thinning + scroll preferred (rotation hard in HEEx SVG).

### E.3 Bar / dot sizing when crowded

| n | Sold bar width | Unsold dot |
|---|----------------|------------|
| ≤ 12 | `slot × 0.5` (current) | `r = 6` |
| 13–24 | `slot × 0.4` | `r = 5` |
| > 24 | `slot × 0.35` | `r = 4` |

### E.4 Overlapping dots (unsold only)

When two purchases share same month or `slot` is tight: optional **±2px x jitter** on dot cx (deterministic hash from `purchase_date`, not random) to reduce overlap. v1 acceptable without jitter if scroll gives enough slot.

### E.5 Empty real estate

If `n > 30`, consider caption under chart: `"{n} purchases — scroll to see all; hover for details"` (same pattern as purchase table expand hint).

### E.6 Implementation (`charts.ex`)

- Extract shared `chart_layout(n_lots, kind)` returning `%{svg_width, slot, label_indices, label_format, bar_bw, dot_r}`.
- `build_pnl_bars` and `build_cost_basis` consume layout — **do not** duplicate logic.
- Tests: `n=6` all labels; `n=20` thinned labels; `n=25` scroll width > 600.

### E.7 Review checklist

- [ ] Horizontal scroll when `n * min_slot > plot_width`
- [ ] Label thinning algorithm; full date in hover always
- [ ] Remove unsold connector polyline
- [ ] Shared layout helper in `charts.ex`

---

## §F — Sell-on-Purchase Analysis (§3.5)

### F.1 Purpose

**Answer one question:** *Was holding (and selling later) better than exiting at purchase-day FMV on the next trading day?*

This is a **historical hypothetical** — not “should I sell today at $453.” Current market is covered by summary row 3, unsold chart, and return strip.

### F.2 Formulas (`net_buy_price` P&L throughout)

```
purchase_value    = Σ(buy_price × gross_shares)           # payroll out
sell_on_purchase  = Σ(vest_fmv × net_shares)              # if sold net sh at purchase FMV
day1_gain           = sell_on_purchase − purchase_value    # = net discount (row 2)
total_pnl           = realized_pnl + unrealized_pnl       # net_buy_price basis
extra_from_holding  = total_pnl − day1_gain               # holding vs day-1 exit
```

```
holding_better = extra_from_holding > 0
```

**Not used in verdict:** `current_price`, mark-to-market today, or “sell everything now.”

### F.3 Layout (wireframe)

```
┌──────────────────────────────────────────────────────────────────┐
│  Sell-on-Purchase Analysis                              (?)      │
│  Hypothetical: exit every lot at purchase-day FMV on the next    │
│  trading day.                                                    │
├──────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ Day-1 gain  │  │ Extra from  │  │ Total P&L   │  (equal)   │
│  │  +₹4.0L     │  │  +₹2.4L     │  │  +₹6.4L     │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
├──────────────────────────────────────────────────────────────────┤
│  VERDICT — full width, success/warning (F.5)                     │
├──────────────────────────────────────────────────────────────────┤
│  SCOPE BANNER — full width, info/neutral (F.6)  ← same weight   │
│  “Not about selling at today's price”                            │
└──────────────────────────────────────────────────────────────────┘
```

**Visual hierarchy:** section title (small context line) → **3 equal cards** (supporting numbers) → **verdict** (answer) → **scope banner** (what this is *not*). The scope banner must be as visually loud as the verdict — **not** a `text-sm` muted subline tucked under the verdict.

### F.4 Three cards (locked)

| Card | Value | Subtitle | Color |
|------|-------|----------|-------|
| **1. Day-1 gain** | `day1_gain` | Discount if sold at purchase FMV (next trading day) | Always **green** (discount ≥ 0) |
| **2. Extra from holding** | `extra_from_holding` | On top of day-1 gain | Green if +, red if − |
| **3. Total P&L** | `total_pnl` | Realized + unrealized (your actual outcome) | Green if +, red if − |

**Reject** card 3 = “Avg. return % / lot” (current M22 `HistoryLive`) — user wants **Total P&L** as third value; return % lives in return strip + charts.

Card styling: `bg-base-200 rounded-xl` — equal size, secondary. Footers are **larger** (F.5 + F.6).

### F.5 Verdict banner

Full-width callout **below** the three cards. Answers: *was holding better than a purchase-day exit?*

| Property | Spec |
|----------|------|
| Size | `text-base`–`text-lg`, `font-semibold`, `py-4 px-5` |
| Width | Full section width |
| Color | `bg-success/15` + success text if holding better; `bg-warning/15` + warning if not |

**Copy if holding better (`extra > 0`):**

> **Holding was worth it** — you are **{extra}** ahead versus selling everything at purchase-day FMV on the next trading day (on top of **{day1_gain}** day-1 discount).

**Copy if not (`extra ≤ 0`):**

> **Day-1 exit would have been better** — selling at purchase-day FMV on the next trading day would have left you **{abs(extra)}** more than your actual outcome (day-1 discount was **{day1_gain}**).

Verdict copy must **not** mention current price or “sell today.”

### F.6 Scope banner — **not** a muted subline

**User feedback:** the “not vs current user state” message was too easy to miss. It gets its **own** full-width panel **below** the verdict, with **equal or greater** visual weight.

| Property | Spec |
|----------|------|
| Placement | Separate block under verdict — **never** nested as small text inside the verdict callout |
| Size | `text-base`, `font-medium` title + `text-sm` body — **no** `text-xs` / `opacity-50` |
| Width | Full section width |
| Style | `border-2 border-info/40 bg-info/10 rounded-xl py-4 px-5` (or DaisyUI `alert alert-info` equivalent) |
| Icon | ℹ️ or “≠” prefix on title |

**Title (always):**

> **Not a comparison to today's stock price**

**Body:**

> This section compares your **actual** realized + unrealized P&L (cards above) to a **purchase-day** hypothetical exit. It does **not** tell you whether to sell your current holdings at **{current_price}**. For that, use summary row 3, the return strip, and the unsold lots chart.

`{current_price}` is optional when price is nil — omit the parenthetical.

**Reject:** single-line `text-sm text-base-content/50` under the verdict. That was the prior design and is too subtle.

### F.7 Tooltip on section (?) 

> Compares total P&L (using net buy price per share) against a hypothetical where every net share was sold at purchase-date FMV on the next trading day. Purchase value = gross shares × buy price. Excess tax paid in cash is not included (see page disclaimer).

### F.8 When to show section

`espp_sop_analysis/2` returns `nil` when `sell_on_purchase` or `purchase_value` cannot be computed — hide entire section (unchanged).

### F.9 `espp_sop_analysis/2` return shape

```elixir
%{
  day1_gain: Decimal.t(),
  extra_from_holding: Decimal.t(),
  total_pnl: Decimal.t(),
  holding_better: boolean()
}
```

Remove `avg_return_pct` from SOP helper (move lot-level return to charts/table only if needed).

### F.10 Implementation notes

- `history_live.ex`: DOM order — cards → verdict (F.5) → scope banner (F.6)
- Two separate full-width blocks; scope banner is **not** a child `<p>` of the verdict
- Currency toggle on all three card values + verdict amounts
- Scope banner may show `current_price` from active symbol (read-only, for pointer to “where to look instead”)
- Update `requirements.md` §3.5 and `design.md` sell-on-purchase section

### F.11 Review checklist

- [ ] Three cards: day-1 gain, extra from holding, total P&L
- [ ] `total_pnl` uses `net_buy_price`-based realized + unrealized
- [ ] Verdict banner (F.5) — holding vs purchase-day exit only
- [ ] **Separate** scope banner (F.6) — as prominent as verdict; not muted subline
- [ ] Drop avg return % from SOP section

---

## Empty / degraded states

| Condition | Behavior |
|-----------|----------|
| No BH | Full-page alert + upload link (Req 4) |
| BH only, no G&L | Sold qty from BH; proceeds / realized P&L `—` without prices |
| No current price | Unrealized P&L `—`; return % / XIRR partial or `n/a` |

---

## Master review checklist (Claude)

**Global / summary**

- [ ] **`silver_builder.ex`** — compute + persist `net_buy_price` in ESPP tranche `metadata_json` at BH ingestion
- [ ] **`history.ex`** — read `net_buy_price`; all ESPP P&L / return % use it; do not leak to Tax Centre
- [ ] Update requirements §3.1, design, tasks, test-plan (ingestion + History scope)
- [ ] `history_live.ex` — v2 grid, return strip, Net Received tooltip, **§A.1d disclaimer** on ESPP tab
- [ ] Tests: `net_buy_price` when gross ≠ net; History P&L uses stored value; Tax Centre unchanged

**Purchase table (§B)**

- [ ] Remove Lookback column
- [ ] Buy Price header tooltip
- [ ] 5-row scroll + expand toggle

**Sold-share returns chart (§C)**

- [ ] Section **name TBD**
- [ ] Y-axis = **return %** vs `buy_price`; refactor `build_pnl_bars`
- [ ] Hover: proceeds, sold/held qty, buy price, $ P&L, %

**Unsold lots chart (§D)**

- [ ] Dots at `net_buy_price`; dashed current price line; no connector polyline
- [ ] Green/red by unrealized sign; hover unrealized P&L + %

**Chart density (§E — §C + §D)**

- [ ] Dynamic svg width + horizontal scroll when many lots
- [ ] X-axis label thinning; full date in hover
- [ ] Shared `chart_layout` helper in `charts.ex`

**Sell-on-purchase (§F)**

- [ ] 3 cards + verdict (F.5) + **separate scope banner** (F.6)
- [ ] Replace avg return % card with Total P&L

**RSU tab (§G — Task 13)**

- [x] Spec pack synced — **§G.10**
- [ ] Implement **Task 13** (`tasks.md`) — replace legacy RSU UI in code

**Still open (ESPP)**

- [ ] Total P&L as 3rd tile in row 3?
- [ ] Sold / unsold chart section titles (names)

---

## How to use this file

1. **Cursor** appends new sections here (§D, §E, …) with changelog row.  
2. **Claude** Accept/Rejects **§G.10**, then implements **Task 13** using `ux-design-rsu.md` + spec quartet.  
3. Do **not** create `ux-feedback-*.md` siblings — keep one source of truth.
