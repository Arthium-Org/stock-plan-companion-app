# Requirements: Upload Checks Redesign (BH Metadata)

## Context

The current upload check logic uses live Silver queries (tranche counts, sale allocation sums) to
determine feature readiness. This is fragile: it depends on Silver build state and produces
incorrect signals when the user hasn't uploaded the right files. Two core problems are fixed here:

1. Portfolio readiness should be driven by what BH says about current share ownership — not by
   whether a Holdings file was uploaded unconditionally.
2. G&L warnings must name the specific sale dates that are uncovered, derived by comparing BH
   sale events against GL allocations — not a single global "no G&L" nudge and not year-bucketed.

Additionally, the Portfolio page currently falls back to BH data when no Holdings file is uploaded.
This was the original design from before the Holdings upload feature existed (M5b). At that time
`docs/core/invariants.md` recorded it as the intended behavior. Once Holdings upload was
introduced, the BH fallback should have been removed — it was not. This spec removes it and
updates the invariant.

The reason BH alone cannot produce accurate current holdings:
- BH does not record how many shares were withheld for taxes at each vest (only the gross vest qty)
- BH records origin-level sell totals, not lot-level sell linkage
- BH has no broker-confirmed sellable balance

A "vested - sold" estimate from BH will be wrong whenever tax withholding varied per vest, or when
sells were distributed across specific lots. Holdings (ByBenefitType) is the broker's confirmed
snapshot of sellable quantities — it is authoritative for current state. `docs/core/invariants.md`
is updated alongside this spec.

---

## R1: BH Snapshot — store summary on each BH ingestion

After the Silver Phase 1 build completes for a Benefit History ingestion, compute and persist a
snapshot of the key facts derived from that file. Store as JSON on the ingestion record.

### R1.1 — Share state (BH-A)

For each BH ingestion (one file = one symbol):

| Field | Meaning |
|---|---|
| `vested_unsold_origin_count` | Count of origins (grants/enrollments) that have VESTED shares not fully sold (origin-level net_quantity > origin-level sold) |
| `unvested_count` | Count of shares in UNVESTED tranches |

If `vested_unsold_origin_count == 0` AND `unvested_count == 0`, the user has fully exited this symbol.
Holdings file for this symbol adds no value to portfolio.

### R1.2 — Sale events (BH-B)

| Field | Meaning |
|---|---|
| `sale_years` | Sorted list of distinct calendar years in which BH records SELL events for this symbol |

Example: `[2021, 2022, 2024, 2025]`. Used to determine which G&L files are needed.

### R1.3 — Storage

New nullable column `bh_snapshot_json TEXT` on `stock_plan_ingestions`. Null for non-BH
ingestion types (HOLDINGS, GL_EXPANDED). No existing column or table is modified.

Migration required. Backfill not required — existing ingestions remain null; snapshot populates
on next BH upload.

**Transition behavior (post-deployment):** After the migration is applied, any existing ACTIVE BH
ingestion will have `bh_snapshot_json = null`. When `UploadChecks.check/1` loads snapshots and
finds `has_bh = true` but an empty snapshot list (all null), it must treat this as a degraded
legacy state and prompt re-upload:
- G&L coverage nudges cannot fire (no sale_years to check)
- Holdings requirement cannot be evaluated (no vested_unsold_origin_count)
- Add a `:bh_snapshot_missing` info nudge: "Re-upload your Benefit History file to unlock
  accurate readiness checks"
- Portfolio readiness: `:blocked` (BH present but snapshot absent — cannot confirm current share
  state; `:limited` is not used for Portfolio)

---

## R2: Upload check logic redesign

The `UploadChecks.check/1` function is rewritten to derive readiness from:

- Presence / absence of each ingestion type (BH, Holdings, G&L) — unchanged
- BH snapshot data (aggregated across all active BH ingestions for the account)
- Calendar year of today — determines which G&L years are "required" vs "warned" vs "ignored"

### R2.1 — BH gate

No BH ingestion → all features `:blocked`, `no_benefit_history` error nudge. No further checks.
This is unchanged.

### R2.2 — Holdings requirement: driven by BH-A

Aggregate `vested_unsold_origin_count + unvested_count` across all active BH ingestions for the account.

| BH says | Holdings uploaded | Portfolio readiness | Nudge |
|---|---|---|---|
| current shares exist | Yes | `:ready` | none |
| current shares exist | No | `:blocked` | `:no_holdings` error — upload required |
| no current shares (fully sold/unvested=0) | Either | `:not_applicable` | none (nothing to portfolio) |

The previous `:limited` state for "BH present, no Holdings" is removed. Portfolio is either
`:ready` (Holdings uploaded), `:blocked` (mandatory and missing), or `:not_applicable` (user
has fully exited all positions — nothing to show in Portfolio).

"Current shares exist" = any active BH ingestion has `vested_unsold_origin_count > 0` OR
`unvested_count > 0`.

**No per-symbol nudge change**: `bh_without_holdings` per-symbol nudge (M22 R10) is unchanged —
it fires as `:info` for symbols with current shares and no Holdings file. The Holdings-
requirement logic above is the global feature-readiness signal.

### R2.3 — G&L requirement: date-based, derived from BH sale events

G&L Expanded is a date-range export from E*Trade — it is not per-year. Coverage is determined
by comparing actual BH sale event dates against actual GL allocation dates in Silver, not by
year buckets.

Aggregate `sale_years` from the BH snapshot (list of years with sale events) across all active
BH ingestions. This tells us which calendar years have sales.

**Coverage check**: for each BH sale event date, a GL allocation exists in `stock_plan_sale_allocations`
if and only if a G&L file covering that date was uploaded and processed. Uncovered sale dates =
BH sale dates with no matching GL allocation.

**Relevant period** (only uncovered dates in this window trigger nudges):

| Period | Label | Required for |
|---|---|---|
| `Jan 1, CY-1` to `Dec 31, CY-1` | Previous calendar year | Capital Gains, FSI, Schedule FA |
| `Jan 1, CY` to today | Current year to date | Capital Gains, FSI (year in progress — warn only) |

Sale events older than CY-1 are ignored — user cannot retroactively change a filed ITR.

**Nudge logic**:

```
uncovered = BH sale dates with no GL allocation, within the relevant period

if any uncovered dates fall in CY-1:
  emit :no_gl_for_dates nudge (severity: :warning)
  message: "G&L missing for sale dates in {CY-1}: {earliest}–{latest} ({count} events)"

if any uncovered dates fall in CY (current year in progress):
  emit :no_gl_for_dates nudge (severity: :info)
  message: "G&L not yet uploaded for {CY} — {count} sale events have no G&L match"
```

Both nudges replace the current global `:no_gl` nudge. The existing `:gl_coverage_gap` nudge
(code path via `TrancheTimeline.validate_cy_coverage`) is unified into this check — same
mechanism whether G&L is partially uploaded or not uploaded at all.

### R2.4 — Readiness: Capital Gains, FSI, Schedule FA

Capital Gains / FSI:
- `:blocked` if any uncovered sale dates fall in CY-1
- `:ready` otherwise (no sales at all, or all CY-1 dates covered)

Schedule FA:
- `:blocked` if any uncovered sale dates fall in CY-1
- `:limited` if BH present but no Holdings (Holdings improves FA accuracy even when G&L is present)
- `:ready` if CY-1 dates all covered and Holdings uploaded

Both replace the previous `has_bh_sales && !has_gl` global check with the targeted per-FY check.

---

## R3: Remove BH portfolio fallback

`Portfolio.build/1` currently selects between `build_from_holdings/1` (when Holdings ingestion
exists) and `build_from_bh/1` (fallback). The BH fallback was never a product requirement.

Remove `build_from_bh/1`. When no Holdings ingestion exists, `Portfolio.build/1` returns
`%{"ESPP" => [], "RSU" => []}` — empty, as if nothing is held.

The Portfolio page then shows a blocked/empty state (see R4).

**History page (M24)** is the correct place to show BH-derived historical data. The Portfolio
page shows current held positions only, sourced from Holdings Silver.

### R3.1 — Symbol helpers

`Portfolio.held_symbols/1` derives from `flat_holdings` — after R3 this returns `[]` when no
Holdings uploaded, even if BH has grant data. Correct: "held" means confirmed by Holdings.

`Portfolio.owned_symbols/1` derives from Origins and is unaffected — it returns all-time symbols
from BH regardless of Holdings. Used by History / Tax Centre. No change needed.

---

## R4: Portfolio page — explicit state for each case

Replace the current implicit empty-table display with explicit states driven by what we know
from BH snapshot + Holdings presence.

| BH says | Holdings | Portfolio page shows |
|---|---|---|
| no BH at all | — | "Upload Benefit History to get started" |
| current shares exist | No | "Upload a Holdings file to view your portfolio" (blocked) |
| no current shares | — | "All positions appear to be sold — see History for transaction record" |
| current shares exist | Yes | Normal portfolio view |

No live Silver query needed for these states — derived entirely from BH snapshot + ingestion presence.

---

## R5: Remove Phase 1 ESPP allocations and Yahoo proxy price

Phase 1 ESPP processing currently fetches a Yahoo Finance close price as a proxy `sale_price` and
creates a `SaleAllocation` linked to the specific tranche. Both must be removed.

**Why this breaks R2.3:** `compute_gl_coverage_gaps` determines G&L coverage by checking
`SaleAllocation.sale_price NOT NULL`. ESPP allocations created in Phase 1 carry a Yahoo proxy
price (not null), so ESPP sales appear covered even when G&L has never been uploaded. The
`:no_gl_for_dates` nudge would never fire for any ESPP account — the coverage check is silently
always satisfied.

**Why Yahoo prices violate Invariant #7:** A Yahoo close price is not the actual sale price. The
confirmed price comes from G&L. Storing a proxy as `sale_price` invents financial data that the
system does not actually have.

**After R5:**
- Phase 1 (BH) creates `Sale` with `sale_price = nil, proceeds = nil` for both RSU and ESPP.
  No `SaleAllocation` for either plan type.
- Phase 2 (G&L) creates `SaleAllocation` with confirmed price for both RSU and ESPP (unchanged).

The `Sale` records (date + quantity, no price) continue to serve origin-level sold tracking for
the BH snapshot (R1). The G&L phase 2 "delete placeholder + insert confirmed" logic in
`create_gl_allocation/5` becomes unnecessary but can be kept as defensive no-op.

---

## Out of Scope

- Changing the `gl_coverage_gap` nudge (per-year when G&L partially uploaded) — unchanged
- Sell Advisor readiness logic — unchanged
- Vesting Schedule readiness — unchanged
- The `bh_without_holdings` per-symbol nudge (M22 R10) — unchanged
- Any changes to M22 multi-symbol ingestion or archiving logic

---

## Definition of Done

- [ ] `bh_snapshot_json` column exists on `stock_plan_ingestions`; populated after every BH ingest
- [ ] Portfolio readiness is `:blocked` when current shares exist (from BH) but no Holdings
- [ ] Portfolio readiness is `:blocked` when no current shares (nothing to show)
- [ ] G&L nudge is per-year for relevant years (CY-1, CY), not a global nudge
- [ ] Capital Gains / FSI / Schedule FA blocked only when CY-1 has sales and no G&L for CY-1
- [ ] `build_from_bh` removed; Portfolio page shows explicit state messages
- [ ] All tests pass; `mix compile` 0 warnings
