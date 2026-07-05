# Requirements: M24 — Benefit History Analysis Page

## Introduction

Today `/history` is a stub ("Coming soon — lifetime stats, transaction history, income analysis"). Stock Plan Manager has all the data needed to give a CA or employee a rich lifetime view of their RSU and ESPP economics — vest income, tax burden, what their grants are actually worth, and how their compensation has trended — but none of it is surfaced.

This milestone builds the BH History page: lifetime analyses of RSU income and ESPP returns, with the analyses framed so a CA can use them in client conversations and an employee can use them to understand what their equity comp has actually been worth.

The page is **read-only** — no new ingestion, no schema change. It computes from existing Silver data.

---

## Requirement 1: Page structure

`/history` becomes a multi-section LiveView with:

1. **Page header** — title + INR/USD two-button currency toggle (right-aligned)
2. **Info bar** — sticky horizontal bar showing context info (see §1.1)
3. **Plan tabs** — RSU | ESPP tab strip to switch between plan views
4. **Plan content** — RSU or ESPP analysis depending on active tab

### 1.1 Info bar

A single horizontal bar below the page header, persistent across tab switches. Two sides:

- **Left**: symbol ticker (monospace bold). If the account holds multiple symbols, a `<select>` dropdown replaces the plain ticker. Immediately right: current stock price. Right of price: an ℹ️ icon with a hover tooltip showing "Price as of [datetime]" — the timestamp when the price was fetched during page load, not the upload time.
- **Right**: "Data last updated [datetime]" — the timestamp of the most recent ingestion upload, NOT the price fetch time. Followed by an "↑ Upload" button linking to `/upload`.

### 1.2 Multi-symbol behavior

When the account holds multiple symbols, the symbol dropdown in the info bar controls which symbol's data is shown across all sections. Plan tabs (RSU / ESPP) are preserved across symbol switches. If the newly selected symbol has no data for the active plan tab, the tab switches to whichever plan has data.

**Note:** A "Combined" cross-symbol view is out of scope for this milestone — deferred to M24b or a future iteration.

---

## Requirement 2: RSU analysis

The RSU tab treats RSUs as **compensation / ordinary income at vest** (not investment P&L like ESPP). Locked UX: `cursor-feedback-on-specs.md` §G · mock `m24-rsu-history.canvas.tsx`.

**Out of scope on this tab:** post-vest sell/hold analytics (no tranche-level sell truth from Benefit History alone — requires G&L + `sale_allocations` in a future milestone).

### 2.1 Section order

1. Summary tiles (§2.2)
2. RSU income by year chart (§2.3)
3. Grant breakdown table (§2.4)
4. New grant value by year chart (§2.3)
5. Disclaimer footer (§2.5)

### 2.2 RSU summary tiles

Two rows. **Every tile** has an info icon (`ℹ`) beside the label with a hover tooltip defining the metric.

#### Row 1 — Income snapshot

| Tile | Source |
|------|--------|
| **Grants** | Count of RSU `origins` for symbol |
| **Grant promise** | `Σ(total_quantity × origin_fmv)` |
| **Income recognized** | `Σ(vest_quantity × vest_fmv)` on VESTED tranches |
| **Still to vest (est.)** | `Σ(unvested vest_quantity × current_price)` — UI-only; not received income |

Money tiles respect INR/USD toggle.

#### Row 2 — Shares + drift

| Tile | Source |
|------|--------|
| **Vested (net shares)** | `Σ net_quantity` where status = VESTED |
| **Unvested (gross shares)** | `Σ vest_quantity` where status = UNVESTED |
| **Vest vs grant drift** | `(income_recognized / vested_promise_at_grant − 1) × 100` where `vested_promise_at_grant = Σ (vested_gross_qty / granted_qty) × grant_promise` per grant |

Color drift green if positive, red if negative.

### 2.3 Income charts (two separate line charts)

Do **not** merge grant and vest series on one chart. Do **not** show YoY % as primary.

#### RSU income by year (hero)

- Line chart with area fill
- X-axis: calendar year
- Y-axis: `Σ(vest_quantity × vest_fmv)` per year in selected currency
- Value labels when ≤8 years

#### New grant value by year

- Line chart with area fill
- X-axis: calendar year of grant date
- Y-axis: `Σ(granted_qty × origin_fmv)` for grants issued that year
- Info callout: large grant in year N appears here before it flows into vest income as tranches vest

### 2.4 Grant breakdown table

One row per RSU origin, sorted by grant date **descending**:

| Column | Source |
|--------|--------|
| Grant # | `origins.grant_number` |
| Grant date | `origins.origin_date` |
| Granted | `origins.total_quantity` |
| Grant promise | `total_quantity × origin_fmv` |
| Recognized | `Σ(vest_quantity × vest_fmv)` VESTED for this origin |
| Still to vest | `unvested_gross_qty × current_price` — `—` if none unvested |
| vs promise | `(recognized + still_to_vest) / grant_promise − 1` — green/red |

**Scroll / expand:** default 5 rows; vertical scroll when collapsed and `grants.length > 5`; **Show all N grants** / **Collapse table** toggle (same pattern as ESPP purchase lots §3.2).

### 2.5 Disclaimer

Footer callout on RSU tab:

> Still-to-vest estimates use today's stock price — not income you have received. Income recognized uses vest-date FMV from your Benefit History upload.

---

## Requirement 3: ESPP analysis

The ESPP tab treats ESPP as an investment — the employee contributes payroll deductions and receives shares at a discount.

### 3.0 P&L basis — `net_buy_price` (persisted at ingestion)

All ESPP **performance** metrics on the History page (P&L tiles, return %, charts, sell-on-purchase) use **effective cost per received share**:

```
net_buy_price = (buy_price × gross_shares) / net_shares
```

When `gross_shares == net_shares` (no tax withholding), `net_buy_price == buy_price` — no regression for users without tax withholding.

**Persisted** at BH Silver build in `tranches.metadata_json["net_buy_price"]` (`silver_builder.ex`). Recomputed on every Silver rebuild. **History page only** — Tax Centre, Portfolio, and Sell Advisor use existing cost-basis rules unchanged.

**Two layers — do not mix:**

| Layer | Question | Basis |
|---|---|---|
| Row 2 **Net Discount Value** | Plan benefit at purchase? | `vest_fmv` vs `buy_price` on net shares |
| Row 3 **P&L**, charts, SOP | How did the investment perform? | `net_buy_price` vs sale / current |

### 3.1 ESPP summary — 3 rows + return strip

Replace flat 9-tile grid with three rows and a return strip.

#### Row 1 — Share counts

| Tile | Formula | Notes |
|---|---|---|
| Gross Purchased | `Σ vest_quantity` | |
| Net Received ℹ️ | `Σ net_quantity` | Tooltip: `{tax_withheld}` shares withheld for tax |
| Currently Held | `net_received − sold` | |

#### Row 2 — Money flow

| Tile | Formula | Subtitle |
|---|---|---|
| Purchase Value | `Σ(gross_shares × buy_price)` | Payroll contributed (gross shares) |
| Net Discount Value | `Σ((vest_fmv − buy_price) × net_shares)` | Discount on shares received |
| Realized Proceeds | `Σ(sale_price × sold_qty)` | Cash from sales; `—` if no sale prices |

#### Row 3 — Performance

| Tile | Formula | Notes |
|---|---|---|
| Realized P&L | `Σ(sale_price − net_buy_price) × sold_qty` per lot | Green/red by sign |
| Unrealized P&L | `Σ(current_price − net_buy_price) × held_qty` per lot | `—` when price nil |
| Total P&L | `realized_pnl + unrealized_pnl` | `—` when either component nil |

#### Return strip (below row 3)

Full-width muted bar:

```
Portfolio return: +23.5%  ·  Approx. XIRR 18.4% ℹ️
```

| Metric | Formula | Notes |
|---|---|---|
| Total return % | `(total_pnl / purchase_value) × 100` | |
| Approx. XIRR | `compute_espp_xirr_from_lots/3` | Tooltip: payroll spread over enrollment — true XIRR may differ slightly |

All monetary tiles and strip amounts respect the INR/USD toggle.

### 3.2 Purchase lots table

One row per ESPP tranche (purchase lot), sorted by purchase date ascending.

**Heading:** `Purchase Lots ({n})` — `id="espp-lots"`

| Column | Source | Notes |
|---|---|---|
| Purchase Date | `tranches.vest_date` | |
| Gross | `tranches.vest_quantity` | |
| Net | `tranches.net_quantity` | |
| Buy Price ℹ️ | `tranche.metadata_json["buy_price"]` | Header tooltip: "Discounted purchase price — typically 15% below lock-in (grant-date) price. Payroll deducted at this price, not purchase-day market price (see FMV)." |
| FMV | `tranches.vest_fmv` | Purchase-day market price |
| Disc % | `(vest_fmv − buy_price) / buy_price × 100` | |
| Sold | allocated sold qty | |
| Held | `net − sold` | |
| Real. P&L | `(sale_price − net_buy_price) × sold_qty` | `net_buy_price` basis |
| Unreal. P&L | `(current_price − net_buy_price) × held_qty` | `net_buy_price` basis; `—` when price nil |

Currency toggle applies to all money columns. Lookback (`origin_fmv`) column removed — lock-in context covered by Buy Price tooltip.

**Scroll + expand:** Default `max-height` ≈ 5 rows, `overflow-y: auto`, sticky header. When `n > 5`: footer shows "Showing 5 of {n} lots — scroll or expand" + **Show all {n} lots** button. Expanded state removes max-height and shows **Collapse table** button.

### 3.3 Sold share returns chart

One bar per ESPP purchase where `sold_qty > 0`. Multiple sell allocations on the same purchase are aggregated into one bar.

**Chart type:** Vertical bar  
**Y-axis:** Return % (not dollar P&L) — comparable across lots regardless of size  
**Bar height:** `return_pct = realized_pnl / (net_buy_price × sold_qty) × 100`  
**X-axis:** Purchase date (`Jun '23`)  
**Zero line:** 0% dashed baseline (distinct from X-axis)  
**Solid X and Y axis lines** on plot bounds  
**Bar color:** Green if `return_pct ≥ 0`, red if negative  
**Bar label:** `+12.3%` / `-4.1%` on/near bar

**Hover (required):** purchase date · sold qty (and held qty if partial) · net buy price · avg sale price · proceeds · dollar P&L · return %

**Chart density:** Dynamic SVG width when `n × 36px > plot_width`; wrap in horizontal scroll container. X-axis label thinning: ≤12 lots → `Jun '23`; 13–24 → `'23`; >24 → year/quarter at boundaries. Full purchase date always in hover. Shared `chart_layout/2` helper with §3.4.

**Section title:** Sold lot returns

### 3.4 Open lots chart

One dot per ESPP purchase lot where `held_qty > 0`.

**Chart type:** Scatter — dots only, **no connecting polyline**  
**X-axis:** Purchase date  
**Y-axis:** Price per share  
**Dot Y position:** `net_buy_price` (effective cost per received share)  
**Reference line:** Horizontal dashed current price, labeled "Current"  
**Dot color:** Green if `current_price > net_buy_price`; red if below  
**Solid X and Y axis lines** on plot bounds

**Hover (required):** purchase date · held qty · net buy price · current price · unrealized $ and %

**When price nil:** reference line hidden; dots still rendered at net buy; unrealized `—` in hover.

**Chart density:** Same §E rules as §3.3 — shared `chart_layout/2` helper.

**Section title:** Open lots — cost vs current

### 3.5 Sell-on-Purchase analysis

Historical hypothetical: *was holding better than exiting every lot at purchase-day FMV on the next trading day?* Shown only when `sell_on_purchase_usd` can be computed. **Not** a "should I sell today?" recommendation — current market is covered elsewhere (summary row 3, return strip, unsold chart).

Three equal cards (all `net_buy_price`-based P&L):

| Card | Value | Subtitle |
|---|---|---|
| Day-1 gain | `sell_on_purchase − purchase_value` | Discount at purchase FMV (next trading day) |
| Extra from holding | `total_pnl − day1_gain` | On top of day-1 gain |
| Total P&L | `realized_pnl + unrealized_pnl` | Realized + unrealized (your actual outcome) |

Day-1 gain is always green. Extra from holding and Total P&L are green/red by sign.

**Verdict banner** (full width, below cards): success if holding beat purchase-day exit; warning if not. Copy references `{extra}` and `{day1_gain}` only — no current price.

**Scope banner** (full width, **separate** block below verdict — as prominent as verdict, not a muted subline): title **"Not a comparison to today's stock price"**; body explains this compares actual P&L to a purchase-day exit and points users to summary / unsold chart for current-market decisions. May show current price as a pointer only.

All cards and both banners respect the INR/USD toggle.

### 3.6 ESPP XIRR formula

Outflow per lot: `−(gross_shares × buy_price)` at `purchase_date`. This is the total payroll contribution, including shares later withheld for tax. Inflows:

- One inflow per sale allocation, at the allocation's `sale_date` and `sale_price`. A lot with two separate sell events at different dates produces two inflow entries, not one aggregated entry.
- One inflow per lot with unsold shares: `held_qty × current_price` at today.

**Display label:** "Approx. XIRR". **Tooltip:** "Calculated using purchase date as the outflow date. Actual payroll deductions were spread over the enrollment period, so the true XIRR may differ slightly."

If convergence fails, show "n/a".

### 3.8 ESPP tab footer disclaimer

Muted text below the qualifying/disqualifying section (last section of the ESPP tab):

> Returns and P&L on this page use effective cost per received share (total payroll ÷ net shares per purchase). **Additional tax paid in cash outside the plan is not reflected in these calculations.**

Not shown on RSU tab, Tax Centre, Portfolio, or Sell Advisor.

---

### 3.7 Qualifying vs disqualifying disposition (collapsible)

For each ESPP sale, classify:

- **Qualifying**: sold ≥ 2 years from grant date AND ≥ 1 year from purchase date
- **Disqualifying**: any sale not meeting both thresholds

Show: count of qualifying vs disqualifying dispositions, and total proceeds in each bucket.

This section is **collapsible** (default closed). Clearly labeled "US Tax Classification" with a badge "US tax only". India-only filers can ignore it.

---

## Requirement 4: No-data state

When no data has been uploaded, the entire page body is replaced with a single alert: "No data uploaded yet. Upload your Benefit History to see analyses." with a link to `/upload`.

---

## Requirement 5: Currency consistency

Every monetary value on the page respects the INR/USD toggle. Rules:

- Historical values (vest, purchase, sale) use event-time FX (stored in Silver)
- Current-price-derived values (ESPP unrealized P&L; RSU still-to-vest estimate) use current FX
- INR variants for ESPP summary fields (`purchase_value_inr`, `realized_pnl_inr`, `unrealized_pnl_inr`, `sell_on_purchase_inr`) are pre-computed in `History.build/1` using `current_fx` as an approximation
- Toggling currency rerenders via LiveView assigns — no page reload, no recompute

---

## Requirement 6: Yahoo price resilience

Yahoo Finance calls must never cause the ingestion pipeline or the History page to crash or return an error to the user.

- **At ingestion time (SilverBuilder):** Yahoo calls for sale_price are wrapped in `try/rescue`. If Yahoo throws, `sale_price` is stored as `nil` and a `Logger.warning/1` is emitted. The ingestion continues.
- **At history-build time (History.build/1):** If a sale allocation's `sale_price` is `nil` (Yahoo failed at ingestion), a second attempt is made via `yahoo_price_safe/2`. If that also fails, the allocation's price remains `nil` and P&L for that lot is `nil` (shown as "—" in the UI). `Logger.warning/1` is emitted on each failure.

---

## Requirement 7: Performance

`/history` is computed on each page load. No caching for v1. Expected query cost: 3–4 indexed queries (load origins, tranches, sales with allocations) totalling <100ms on a realistic dataset. Re-evaluate if it becomes slow.

---

## Out of scope

- **Combined view** across multiple symbols — deferred (all per-symbol for now)
- **Concentration / net-worth analysis** — requires data on other assets not in this app
- **Counterfactuals against market benchmarks** — needs benchmark price series
- **Tax-loss harvesting suggestions** — fits better in Sell Advisor
- **Wash-sale analysis** — US-specific, low value for India-focused users
- **Dividends** — not currently surfaced in Silver
- **Corporate actions (splits, mergers)** — schema doesn't model these

---

## Definition of Done

- [x] `/history` no longer says "Coming soon"
- [x] Info bar shows symbol + current price (left) and last upload datetime + Upload link (right)
- [x] RSU and ESPP sections behind plan tabs
- [x] Multi-symbol: symbol dropdown in info bar switches per-symbol data
- [ ] RSU: §2 layout — summary (2 rows + ℹ), vest $ chart, grant table (5-row expand), grant FMV chart, disclaimer; **no** sold-vs-held / counterfactual / tax / velocity / YoY
- [ ] ESPP: `net_buy_price` persisted at BH Silver build in `metadata_json`
- [ ] ESPP: summary v2 — 3 rows (share counts / money flow / performance) + return strip (total return % + XIRR)
- [ ] ESPP: purchase lots table — no Lookback column; Buy Price tooltip; 5-row scroll + expand; P&L uses `net_buy_price`
- [ ] ESPP: sold share returns chart — Y-axis = return %; dynamic width + label thinning for many lots
- [ ] ESPP: open lots chart — dots at `net_buy_price`; no polyline; unrealized hover
- [ ] ESPP: sell-on-purchase 3-card analysis (day-1 gain / extra / total P&L) + verdict + separate scope banner
- [ ] ESPP: qualifying/disqualifying collapsible
- [ ] ESPP: footer disclaimer on ESPP tab only
- [x] All monetary tiles respect INR/USD toggle consistently
- [x] XIRR: gross outflow, per-alloc inflows
- [x] Purchase Value: `gross_shares × buy_price`
- [x] Yahoo resilience at both ingestion and history-build stages
- [x] `mix compile` clean (zero warnings)
- [x] `mix test` all pass
