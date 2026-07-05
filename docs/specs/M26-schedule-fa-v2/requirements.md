# Requirements: M26 — Schedule FA v2

## Introduction

Schedule FA (Foreign Asset disclosure) was introduced in **M14** and wired to **M21 Tranche
Timeline** (`held_during_cy`). That integration has correctness gaps when G&L coverage is
partial or from the wrong years. Multi-user testing (SampleUser 1–5) surfaced:

| Symptom | Root cause |
|---|---|
| Fully-sold user (no Holdings) shows RSU lots as held | Old formula: `net_qty − G&L_sells_before_cy` with empty allocations |
| Partial G&L (e.g. 2025 only) inflates FA for 2024 | Sell dates from other years applied without Holdings anchor |
| Upload page `:blocked` but Tax Centre builds FA (or vice versa) | Readiness checks CY-1 globally; FA V2 checks selected CY only |
| `bh_snapshot` says no current shares but FA ignores it | Snapshot used only in UploadChecks, not FA pipeline |

**M26 replaces the FA quantity algorithm.** M14 row fields (initial/peak/closing/proceeds in
INR) are unchanged. M21 `TrancheTimeline` has one small change: `match_holding` returns
`sellable_qty || 0` (never nil); `apply_bh_sold_validation_with_holdings` is removed.

> **Supersedes:** M14 FA-4 data-dependency wording, M21 Requirement 3 (Schedule FA query),
> regression-test-fixes R1 (soft G&L degradation). M14 FA-1/FA-1a/FA-2 output semantics
> remain authoritative.

---

## Requirement 1: Data sources

| Source | Role in FA v2 |
|---|---|
| **BH Silver** | Tranches (vest dates, net_quantity), origin-level sell totals, `bh_snapshot_json` |
| **G&L Silver** | Tranche-level sell dates, quantities, prices (RSU; ESPP when uploaded) |
| **Holdings Silver** | Current `sellable_qty` per tranche — required when BH shows unsold shares |
| **FX + stock prices** | Unchanged from M14 |

**Not a source for current state:** origin-level BH sell events alone cannot assign per-tranche
sell dates for RSU. They are used only for P2 (fully-sold origin detection) and ESPP BH fallback.

---

## Requirement 2: Pre-checks (gates)

FA for calendar year `Y` is built only when both pre-checks pass. Failures return
`{:error, message}` — no rows, no soft-degradation.

### P1: G&L coverage — scoped to requested CY (all plan types)

G&L is **not** required for all historical years. For the requested CY `Y`:

```
cy_start = Jan 1, Y

bh_dates_required = BH sell dates (RSU + ESPP) where sale_date >= cy_start

IF bh_dates_required is empty → PASS

gl_dates = all G&L allocation sale_date values (RSU + ESPP)

missing = bh_dates_required − gl_dates

IF missing is empty → PASS
ELSE → BLOCK:
  "G&L missing for sell dates: {dates}. Upload G&L covering sales in or after {Y}."
```

**Rationale:** Rule 3 needs `cy_sale` (sells in CY) and `beyond_sale` (sells after CY end)
for both RSU and ESPP. Without G&L, `sale_proceeds_inr` cannot be computed and the FA row
is incomplete — partial FA has no value. Pre-CY sell history for both plan types is implicit
in `holdings_qty` (Holdings file or P2-inferred zero). G&L is required for CY+ BH sell
dates so `sale_proceeds_inr` and CY/beyond sale quantities are computable.

### P2: Holdings availability — direct DB check (no timelines)

P2 runs **before** `TrancheTimeline.build`. It uses a direct DB query — not TrancheTimeline
output — so that timeline construction happens only after both gates pass.

**Gate logic:**

```
IF any Holdings row exists for account_id in stock_plan_holdings → PASS
  (TrancheTimeline will resolve holdings_qty = match || 0 for every tranche)

ELSE: per-origin BH reconciliation —
  For each origin:
    total_released = SUM(vested tranche net_quantity)   ← aggregate query, no timelines
    bh_sold        = SUM(BH sale quantities for origin)

    IF |bh_sold − total_released| <= 2:
      → Origin fully sold. TrancheTimeline will set holdings_qty = 0.
      → PASS for this origin.

    IF bh_sold < total_released − 2:
      → Origin has unsold shares, no Holdings to anchor balance.
      → BLOCK: "Holdings unavailable for grants: {grant_numbers}.
                Upload Holdings (ByBenefitType) or ensure all sales are in Benefit History."
```

**Rationale:** Rule 3 needs `holdings` (Dec 31 sellable balance). If Holdings are uploaded,
`match_holding({grant_number, vest_date}) || 0` is always correct: "in Holdings" = held qty,
"not in Holdings" = sold. If Holdings are absent but BH confirms the origin is fully sold
(`bh_sold ≈ total_released`), `holdings_qty = 0` is also correct — no shares remain.
Any other state is genuinely unresolvable and must block before TrancheTimeline runs.

---

## Requirement 3: CY state algorithm (`compute_cy_state`)

For each **VESTED** tranche with `vest_date <= cy_end`, compute
`(start_count, end_count, cy_sale)`. Rows with `start_count == 0` are excluded.

### Rule 1 — Vested during CY (`cy_start ≤ vest_date ≤ cy_end`)

```
cy_sale     = SUM(sells with sale_date in [cy_start, cy_end])
start_count = net_quantity
end_count   = net_quantity − cy_sale
```

### Rule 2 — Vested after CY (`vest_date > cy_end`)

```
start_count = 0
end_count   = 0
(excluded)
```

### Rule 3 — Vested before CY (`vest_date < cy_start`)

```
cy_sale      = SUM(sells with sale_date in [cy_start, cy_end])
beyond_sale  = SUM(sells with sale_date > cy_end)
holdings     = holdings_qty from Holdings, OR 0 if origin BH-confirmed fully sold (P2)

start_count  = cy_sale + beyond_sale + holdings
end_count    = beyond_sale + holdings
```

**Interpretation:** For a pre-CY tranche, shares held entering the year =
what was sold during CY + what was sold after CY + what is still held now. Shares held on
Dec 31 = post-CY sells + current holdings. Pre-CY sells are implicit in the Holdings balance.

**Inclusion:** `start_count > 0` means the lot was held at some point during CY (M14 FA-1 ¶3).

### Sell source and holdings per plan type

| Plan | `sells` in Rules 1–3 | `effective_holdings` (Rule 3) |
|---|---|---|
| RSU | G&L allocations only (`source: :gl`) | `holdings_qty` (match_holding || 0 from TrancheTimeline) |
| ESPP | G&L allocations if present; else BH quantity-matched sell (`source: :bh`) per M21 | `holdings_qty` — same field, same logic as RSU |

`effective_holdings(t)` is a single unified function: `t.holdings_qty`. No plan-type
branching. This works for ESPP because Holdings VESTED rows are keyed by
`{grant_number, vest_date}` = `{espp_enrollment_hash, purchase_date}` — matching the
tranche key used by `match_holding`. P2 ensures Holdings is present (or origins are BH-
confirmed fully sold), so `match_holding || 0` is always correct for both RSU and ESPP.

**Sell vs holdings scope:** `timeline.sells` may include M21 BH qty-match entries for ESPP
(used in the History/diagnostics path). Schedule FA Rule 3 closing balance always uses
`holdings_qty`, never `net_quantity − SUM(sells)`. When `holdings_qty = 0` and
`cy_sale + beyond_sale = 0`, `start_count = 0` → lot excluded (User 2 / SampleUser 1
pre-CY pattern).

---

## Requirement 4: FA row fields

Unchanged from M14 FA-1 / FA-1a. Quantities come from `compute_cy_state`:

| Field | Formula |
|---|---|
| `date_acquired` | `vest_date` |
| `quantity_start` | `start_count` |
| `quantity_held` (end) | `end_count` |
| `initial_value_inr` | `cost_basis × start_count × vest_fx_rate` |
| `peak_value_inr` | interval peak during CY; initial qty = `start_count`, reduced by CY sells |
| `closing_value_inr` | `dec31_price × end_count × dec31_fx` (0 if `end_count == 0`) |
| `sale_proceeds_inr` | G&L sells in CY only: `Σ(qty × price × sale_fx)` |

`initial_value_inr` uses `start_count`, not `net_quantity` — critical for pre-CY tranches
where pre-CY sells reduced the opening balance.

### Cost basis per plan type

For Schedule FA initial value and Capital Gains cost basis, use the FMV on the acquisition
date — not the discounted purchase price:

| Plan | Cost basis |
|---|---|
| RSU | `vest_fmv` (FMV on vest date) |
| ESPP | `vest_fmv` (FMV on purchase date) — NOT the discounted buy price |

The ESPP discount income is taxed as salary at vest. The capital gain is measured from the
full purchase-date FMV, not from what was paid.

### Row aggregation (`aggregate_by_date`)

After building per-tranche rows, rows are aggregated. The grouping key is
`{date_acquired, symbol, cost_basis_per_share}`.

**Rationale:** A Schedule FA row represents shares of a given asset acquired at the same
price on the same date. Two RSU grants vesting on the same date have the same FMV → they
share a cost basis → correctly merged into one row. An ESPP purchase and an RSU vest on the
same date typically have different FMVs → different cost bases → separate rows, regardless
of plan type.

Merged rows preserve `cost_basis_per_share` (all members have the same value by definition
of the grouping key). `plan_type` in a merged row is the join of distinct plan types (e.g.
`"RSU"` always in practice; `"ESPP/RSU"` only if two plans coincidentally share a cost basis).

---

## Requirement 5: API contract

```elixir
ScheduleFA.build(account_id, calendar_year)
  → {:ok, rows, warnings}   # warnings = V1/V3 from TrancheTimeline (non-blocking)
  → {:error, message}        # P1 or P2 failure, or missing stock meta
  → {:error, {:missing_meta, symbols}}
```

**No `{:ok, rows, [gl_warning]}` when P1 fails.** Hard block replaces regression-test-fixes
R1 soft path.

---

## Requirement 6: Upload readiness alignment

Upload page readiness for Schedule FA must be **consistent with P1/P2 for the most recently
completed calendar year** (CY-1), not a rolling "any uncovered sale since CY-1" that blocks
all years.

| Condition | `schedule_fa` readiness |
|---|---|
| No BH | `:blocked` |
| P1 would fail for CY-1 | `:blocked` |
| P2 would fail for CY-1 | `:blocked` |
| BH present, `has_current_shares` and no Holdings | `:limited` |
| Otherwise | `:ready` |

`:limited` applies when BH snapshot shows current RSU (or mixed) positions requiring Holdings
for accurate Rule 3 quantities. Accounts that are **fully exited** per snapshot
(`vested_unsold_origin_count == 0` and `unvested_count == 0`) receive `:ready` without a
Holdings file — P2 infers `holdings_qty = 0` for both RSU and ESPP. ESPP Rule 3 uses the
same `holdings_qty` anchor as RSU.

Tax Centre year selector re-runs `ScheduleFA.build/2` for the selected year — P1/P2 are
evaluated for **that** year. A `:ready` badge for CY-1 does not guarantee CY-2022 succeeds
if 2022 had RSU sells without G&L.

Add helper: `UploadChecks.schedule_fa_readiness(account_id, calendar_year)` used by both
Upload page (default CY-1) and Tax Centre (selected year).

---

## Requirement 7: UI

Tax Centre Schedule FA tab:

1. On P1/P2 error → error banner, empty table, no CSV download
2. On `{:ok, rows, warnings}` → table + optional warning banner (V1/V3 only)
3. Remove copy implying FA works without required G&L/Holdings

---

## Requirement 8: Fully-exited user (SampleUser 1 pattern)

When `bh_snapshot` shows `vested_unsold_origin_count == 0` and `unvested_count == 0`:

- P2 passes without Holdings
- All origins (RSU + ESPP) infer `holdings_qty = 0` when P2 confirms origin fully sold
  (`bh_sold ≈ total_released`) or snapshot is fully exited
- **P1 still applies:** any BH sell date (RSU or ESPP) on or after `cy_start` requires matching
  G&L before FA is built. No partial FA — without G&L there is no `sale_proceeds_inr` and
  the disclosure is incomplete.
- SampleUser 1 with BH only and sales in or after the filing year → **`{:error, _}`** from P1,
  not an empty table with ESPP rows from BH alone

Once P1 and P2 pass (e.g. BH + G&L covering all required sell dates):

- Pre-CY RSU tranches fully sold before CY: `start_count = 0` → excluded
- Lots sold during CY appear with full proceeds — correct disclosure even if the user has
  since fully exited all positions

---

## Out of scope

- Stock Options
- Multi-year Holdings snapshots (Holdings = current only)
- TrancheTimeline architectural changes (History page data paths unchanged)
- Capital Gains / Schedule FSI (separate milestones)
- ITR XML export
