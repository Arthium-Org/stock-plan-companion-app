# UX Design: M24 — Benefit History (RSU Tab)

> **For implementers (Claude):** Authoritative UX for the **RSU tab** on `HistoryLive`.  
> **Visual mock:** [`m24-rsu-history.canvas.tsx`](./m24-rsu-history.canvas.tsx) · live preview: `canvases/m24-rsu-history.canvas.tsx`  
> **Locked decisions:** `cursor-feedback-on-specs.md` §G  
> **ESPP tab:** [`ux-design.md`](./ux-design.md) (separate doc — do not mix lenses)

---

## Mental model

RSU = **compensation / ordinary income at vest**. Not investment P&L (that is ESPP).

**Out of scope:** Sold vs held, counterfactual, proceeds, return % — BH alone has no tranche-level sell truth without G&L.

---

## Section order

1. Summary (§ below)
2. **RSU income by year** — line chart, vest FMV $
3. **Grant breakdown** — table, 5-row scroll + expand
4. **New grant value by year** — line chart, grant FMV $
5. **Disclaimer** footer

---

## Summary tiles

Two rows. **Every tile:** label + circled **i** with hover tooltip (`title` or DaisyUI `data-tip`).

### Row 1 — Income snapshot

| Tile | Tooltip gist |
|------|----------------|
| Grants | Count of RSU grant records |
| Grant promise | Σ(granted qty × grant-date FMV) |
| Income recognized | Σ(vest qty × vest FMV) on vested tranches |
| Still to vest (est.) | Unvested gross × today's price — estimate only |

### Row 2 — Shares + drift

| Tile | Tooltip gist |
|------|----------------|
| Vested (net shares) | Net shares after tax withholding |
| Unvested (gross shares) | Scheduled, not yet delivered |
| Vest vs grant drift | Vest FMV vs grant FMV on vested shares (%) |

Money tiles respect INR/USD toggle.

---

## Chart A — RSU income by year (hero)

- **Title:** RSU income by year
- **Subtitle:** Total compensation that vested each calendar year — like annual salary growth
- **Type:** Line + area fill
- **X:** Calendar year
- **Y:** Σ(vest qty × vest FMV) per year in selected currency
- **Labels:** Show point values when ≤8 years
- **Caption:** Source: VESTED tranches · values in thousands

---

## Grant breakdown table

| Column |
|--------|
| Grant # · Grant date · Granted · Grant promise · Recognized · Still to vest · vs promise |

- Sort: grant date **descending**
- vs promise: green/red %
- **≤5 rows** visible; scroll in card when collapsed and `n > 5`
- Footer: `Showing 5 of N grants — scroll or expand` + **Show all N** / **Collapse table**

---

## Chart B — New grant value by year

- **Title:** New grant value by year
- **Subtitle:** When fresh equity comp was awarded — separate from when it vests
- **Type:** Line + area fill
- **X:** Grant year
- **Y:** Σ(granted qty × origin_fmv) issued that year
- **Callout:** Large grant in year N appears here before vest income in Chart A

---

## Disclaimer (footer)

> Still-to-vest estimates use today's stock price — not income you have received. Income recognized uses vest-date FMV from your Benefit History upload.

---

## File map

| UX area | Files |
|---------|-------|
| Summary + layout | `history_live.ex` |
| Data | `history.ex` |
| Line charts | `charts.ex` |
| Grant table expand | `history_live.ex` (`:rsu_grants_expanded`, `toggle_rsu_grants_table`) |

---

## Acceptance criteria

- [ ] No tax withheld, velocity, YoY %, counterfactual, sold vs held on RSU tab
- [ ] Two separate line charts (not merged)
- [ ] All 7 summary tiles have working tooltips
- [ ] Grant table matches §G.4 columns; expand when `grants > 5`
- [ ] Visual parity with `m24-rsu-history.canvas.tsx`
