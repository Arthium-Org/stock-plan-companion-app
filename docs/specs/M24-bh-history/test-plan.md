# Test Plan: M24 — Benefit History Analysis Page

## Test surface

| Module / View | What we test |
|---|---|
| `StockPlan.Finance.XIRR` | Newton-Raphson convergence on known cashflows; graceful failure |
| `StockPlan.History` | Per-section compute functions against fixtures; full `build/1` orchestration |
| `StockPlanWeb.Components.Charts` | SVG output shape for each chart type |
| `HistoryLive` | Mount, symbol switch, plan tab switch, currency toggle, qualifying collapsible |

---

## Unit tests — `StockPlan.Finance.XIRR`

```
1. Single-period: −100 today, +110 in 365 days → ≈ 10.0%
2. Multi-period ESPP: known cashflow with hand-computed XIRR
3. All inflows (no outflows) → {:error, :no_convergence}
4. All outflows → {:error, :no_convergence}
5. Empty cashflow → {:error, :no_convergence}
6. Same-day cashflows (zero time delta) → {:error, :no_convergence}
7. Very large positive rate (>1000%) → convergence or {:error, :no_convergence} gracefully
8. Negative rate (e.g., −20%) → convergence
```

---

## Unit tests — `StockPlan.History`

### RSU summary (§G.1)

```
1. Single grant, single vest → grant_count=1; income_recognized = vest_qty × vest_fmv
2. Multi-grant → grant_promise and income_recognized aggregate across origins
3. No RSU origins → empty RSU map / no-data path for symbol
4. still_to_vest = Σ unvested vest_quantity × current_price; nil when current_price nil
5. vest_vs_grant_drift_pct positive when vest FMV > grant FMV on vested shares
6. grant_promise_inr = grant_promise_usd × current_fx (money tiles)
```

### RSU income by year (Chart A)

```
1. Vests across 3 years → one entry per year, sorted ascending
2. Vests in same year → aggregated into one entry
3. Status != VESTED → excluded
4. value_inr uses event-time FX per tranche (existing income_by_year logic)
```

### RSU grants by year (Chart B)

```
1. Two grants in same calendar year → one entry with summed grant_promise
2. Grant in 2020, vest in 2022 → grant appears in 2020 bucket only (not vest year)
3. value_inr = value_usd × current_fx
```

### RSU grant rows (§G.4 table)

```
1. Granted, none vested → recognized = 0; still_to_vest = granted × current_price (if unvested tranches exist)
2. Fully vested → still_to_vest = 0; vs_promise_pct uses recognized only
3. Partial vest → recognized + still_to_vest; vs_promise_pct combines both
4. current_price nil → still_to_vest_usd/inr nil; vs_promise_pct may omit still_to_vest leg
5. No sold_qty, realized_proceeds, return_pct, or unrealized columns in output
```

### RSU removed (must not render)

```
1. tax_paid_by_year — not in build output / not in LiveView
2. counterfactual / sold_vs_held — not in build output / not in LiveView
3. velocity — not in build output / not in LiveView
4. yoy / pct_change — not in build output / not in LiveView
```

### `net_buy_price` ingestion

```
1. Tranche with gross=50, net=40, buy_price=$100 → net_buy_price = $125 in metadata_json
2. Tranche with gross=net (no withholding) → net_buy_price = buy_price (fallback)
3. Tranche with nil buy_price → net_buy_price = nil (fallback)
4. net_buy_price recomputed correctly on Silver rebuild from Bronze
```

### ESPP lots

```
1. buy_price read from tranche.metadata_json["buy_price"] — plan quoted price (display only)
2. net_buy_price read from tranche.metadata_json["net_buy_price"] — all P&L math
3. net_buy_price fallback: if metadata key absent, compute from gross/net/buy (old ingestions)
4. gross_shares = tranches.vest_quantity (NOT net_quantity)
5. sold_qty = sum across all allocs for that tranche
6. held_qty = net_quantity − sold_qty
7. realized_pnl = Σ(alloc.sold_qty × (alloc.sale_price − net_buy_price))   ← net_buy_price, not buy_price
8. pnl_pct = realized_pnl / (net_buy_price × sold_qty) × 100               ← net_buy_price, not buy_price
9. unrealized_pnl = held_qty × (current_price − net_buy_price)             ← net_buy_price, not buy_price
10. total_discount = (vest_fmv − buy_price) × gross_shares (unchanged — context field, not P&L)
11. allocs list retained on each lot for XIRR per-alloc inflows
```

### ESPP summary

```
1. purchase_value = Σ(gross_shares × buy_price) — unchanged; uses gross, not net
2. net_discount_usd = Σ((vest_fmv − buy_price) × net_shares)  ← net_shares (was gross_shares)
3. realized_proceeds_usd = Σ(sale_price × sold_qty) — new field
4. total_pnl_usd = realized_pnl_usd + unrealized_pnl_usd — new field
5. total_return_pct = total_pnl / purchase_value × 100 — new field
6. purchase_value_inr = purchase_value × current_fx
7. sell_on_purchase = Σ(vest_fmv × net_quantity) per lot
8. gross_purchased = Σ(vest_quantity); net_received = Σ(net_quantity)
9. tax_withheld = gross_purchased − net_received (tooltip field; not a standalone tile)
```

### ESPP XIRR

```
1. Outflow uses gross_shares × buy_price (not net_shares)
2. Sale inflows: one entry per alloc at alloc.sale_date (not aggregated)
3. Lot with two sell events → two separate inflow entries at different dates
4. Partially sold lot → both sale inflow(s) and held inflow appear
5. Fully unsold lot → only outflow + held inflow
6. Fully sold lot → only outflow + sale inflow(s), no held inflow
7. nil sale_price on alloc → that alloc contributes no inflow
```

### ESPP qualifying/disqualifying split

```
1. Sale ≥ 2yr from grant AND ≥ 1yr from purchase → qualifying
2. Sale < 2yr from grant → disqualifying (even if ≥ 1yr from purchase)
3. Sale < 1yr from purchase → disqualifying (even if ≥ 2yr from grant)
4. Counts and proceeds bucket correctly
5. Lots with no sale → excluded
```

### Yahoo resilience

```
1. yahoo_price_safe/2 returns nil and emits Logger.warning when Yahoo throws
2. load_espp_allocs_by_tranche: alloc with nil sale_price gets retry via yahoo_price_safe
3. SilverBuilder: Yahoo exception does not abort ingestion; sale_price stored as nil
```

---

## LiveView tests — `HistoryLive`

```
1. Mount with empty DB → no-data alert rendered; no chart or table rendered
2. Mount with single-symbol fixture:
   - Info bar shows symbol as plain text (not dropdown)
   - RSU tab active by default (if RSU data exists)
   - RSU sections render: summary (2 rows + ℹ), vest income line chart, grant table, grant FMV line chart, disclaimer — **not** counterfactual/velocity/YoY/tax
3. Mount with multi-symbol fixture (ADBE + CRM):
   - Info bar shows symbol dropdown
   - Selecting a different symbol switches per-symbol data
4. Select ESPP plan tab:
   - ESPP tiles, lots table, sold chart, unsold chart, SOP analysis visible
   - RSU sections not rendered
5. Currency toggle:
   - Default currency is INR
   - Clicking "$ USD" button: monetary tiles show $ values
   - Clicking "₹ INR" button: monetary tiles show ₹ values
   - INR values formatted with Indian number system (lakhs/crores grouping)
   - Purchase Value, Realized P&L, Unrealized P&L, Total Discount all update on toggle
   - SOP analysis cards (Day-1 Gain, Extra, Total P&L) update on toggle
6. Qualifying/disqualifying collapsible:
   - Default closed (text "US Tax Classification" visible, body hidden)
   - Click toggle → body expands showing qualifying / disqualifying counts and proceeds
7. Info bar content:
   - Current price shows "$[price]" or "—" if nil
   - ℹ️ tooltip contains "Price as of"
   - Right side shows "Data last updated" text and "↑ Upload" link
8. RSU grant table: when grants > 5, collapsed shows max-height + "Showing 5 of N" footer; toggle expands/collapses
9. RSU summary tiles: all 7 labels have tooltip attributes (ℹ)
10. No RSU data for selected symbol → "No RSU data" message; no crash
11. No ESPP data for selected symbol → "No ESPP data" message; no crash
12. SOP analysis not rendered when sell_on_purchase is nil or zero
13. ESPP summary v2: 3 rows rendered (share counts / money flow / performance); return strip shows total return % and XIRR
14. ESPP summary: Net Received tile has DaisyUI tooltip with tax withheld share count
15. ESPP lots table: default state shows max-height constraint and "Showing N of M lots" footer when n > 5
16. ESPP lots table: toggle_espp_lots_table event removes max-height; "Collapse table" button visible
17. ESPP lots table: Lookback column absent
18. ESPP tab: footer disclaimer text visible below qualifying/disqualifying section
```

---

## Chart smoke tests

```
1. bar_chart with empty data → "No data" div rendered, no SVG
2. pnl_bar_chart with one positive lot → green bar; % label above bar; Y-axis shows %
3. pnl_bar_chart with one negative lot → red bar; % label below bar
4. pnl_bar_chart with 6 lots → svg_width = 600 (default); all 6 x-labels shown
5. pnl_bar_chart with 20 lots → svg_width > 600 (dynamic); label count < 20 (thinned)
6. cost_basis_chart: dot at net_buy_price (not buy_price)
7. cost_basis_chart: dot above current_price → red fill; dot below → green fill
8. cost_basis_chart: no <polyline> element in SVG output
9. cost_basis_chart: hover <title> contains unrealized $ and %
10. cost_basis_chart with 20 lots → svg_width > 600; label count thinned
11. cost_basis_chart: current_price nil → no reference line element
12. line_chart (RSU): categories align with series data; area fill optional; currency prefix on Y labels
```

---

## Integration smoke (manual, dev server)

- [ ] Ingest SampleUser-5 (ADBE + CRM); navigate to /history
- [ ] ADBE tab: RSU — summary, two line charts, grant table (expand if >5 grants); no sold-vs-held block
- [ ] ESPP tab shows ESPP data on same symbol
- [ ] CRM tab: switches data correctly
- [ ] Currency toggle: all tiles change consistently (no tile stays in wrong currency)
- [ ] ESPP summary: 3-row layout visible (share counts / money flow / performance); return strip below
- [ ] ESPP lots table: ≤5 lots collapsed; >5 lots shows "Showing N of M" footer + expand button
- [ ] ESPP lots table: Lookback column absent; Buy Price header has tooltip
- [ ] Sold share returns chart: Y-axis is % (not dollars); bars green/red; hover shows proceeds and P&L
- [ ] Open lots chart: dots visible; no connecting line between dots; hover shows unrealized P&L
- [ ] SOP analysis: 3 cards (day-1 gain / extra / total P&L) + verdict banner + separate scope banner ("not today's price"); currency-aware
- [ ] ESPP footer disclaimer visible below qualifying/disqualifying
- [ ] Qualifying section: collapsible works
- [ ] Page load time: <500ms on SampleUser-5

---

## Non-functional

- [x] `mix compile` — 0 warnings
- [x] `mix test --max-cases 1` — all pass (sequential to avoid SQLite contention)
- [x] No new dependencies in mix.exs
