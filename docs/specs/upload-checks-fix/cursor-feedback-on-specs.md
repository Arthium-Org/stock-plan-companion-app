# Cursor Feedback on Upload Checks Fix Specs

**Status:** Living document — append sections here; do not create separate feedback files per topic.  
**Audience:** Claude / implementer reviewing `upload-checks-fix` on `feature/m22-multi-symbol` (or current branch).  
**Baseline:** Spec quartet in this folder + code as of Cursor review (sample-user test pass across Users 1, 3, 5).

> **Wrong-milestone note:** Cursor also drafted this file before the user clarified the target was **`regression-test-fixes/`**. For FA-1 / CG-1 / SA-2 follow-up, use `docs/specs/regression-test-fixes/cursor-feedback-on-specs.md` instead.

**Official specs (Claude updates these after Accept/Reject):**

| File | Role |
|------|------|
| `requirements.md` | Functional requirements |
| `design.md` | Data shapes, algorithms, file map |
| `tasks.md` | Implementation checklist |
| `test-plan.md` | Fixture-based tests |

---

## Changelog

| Date | Section | Summary |
|------|---------|---------|
| 2026-06-10 | §Review | Initial Cursor review after Claude sample-user test run |
| 2026-06-10 | §Status | Most of spec already implemented — doc is partly post-hoc |
| 2026-06-10 | §Gaps | Legacy `bh_snapshot_missing`, R5 ESPP Yahoo, spec contradictions |

---

## Executive summary

Claude’s sample-user testing surfaced real problems (Portfolio BH fallback, global `:no_gl`, symbol nudges on sold-out symbols). The **upload-checks-fix spec direction is correct** and largely **already landed in code**.

Before more implementation, Claude should:

1. **Reconcile contradictions** inside the spec quartet (see §Contradictions).
2. **Close remaining gaps** (§Gaps) — especially legacy null snapshot and ESPP Yahoo on `Sale`.
3. **Mark tasks.md** — check off completed items; don’t re-implement what exists.

---

## Accept / Reject — spec items

| Item | Verdict | Justification |
|------|---------|---------------|
| R1 BH snapshot on ingestion | **Accept** | `bh_snapshot_json`, `compute_bh_snapshot/1` in `ingestions.ex` |
| R2.2 Holdings-driven portfolio readiness | **Accept** | `:ready` / `:blocked` / `:not_applicable` in `upload_checks.ex` |
| R2.3 Date-based G&L (`:no_gl_for_dates`) | **Accept** | `compute_gl_coverage_gaps/1`; User 1 tests pass |
| R3 Remove BH portfolio fallback | **Accept** | `Portfolio.build/1` → holdings only; `invariants.md` §4 updated |
| R4 Portfolio page state machine | **Accept** | `portfolio_live.ex` — `:no_data`, `:all_sold`, `:holdings_required`, `:active` |
| R5 Remove Phase 1 Yahoo / invented prices | **Accept (incomplete)** | RSU sales nil price; **ESPP still sets Yahoo on `Sale.sale_price`** |
| R1.1 `unvested_count` = share count | **Reject wording** | Code counts **UNVESTED tranches**, not shares — rename or sum qty in spec |
| R1.3 Legacy `legacy_bh` transition | **Accept** | **Not implemented** in `check/1` — see §G.1 |
| Out of scope: `gl_coverage_gap` unchanged | **Reject** | Conflicts with R2.3 — mechanism replaced by `:no_gl_for_dates` |
| DoD: portfolio `:blocked` when fully sold | **Reject** | Conflicts with R2.2 `:not_applicable` and existing tests |
| tasks 4.11 legacy → portfolio `:limited` | **Reject** | Conflicts with requirements/design `:blocked` for legacy |
| design §4 “ESPP Phase 1 creates SaleAllocation” | **Reject as written** | Current code: **no** ESPP allocations in Phase 1; Yahoo on **`Sale` only** |
| design `load_bh_snapshots` without symbol | **Reject as stale** | Code returns `{dominant_symbol, json}` for per-symbol nudges |
| `sale_years` in snapshot for G&L checks | **Reject as required** | `compute_gl_coverage_gaps` queries `Sale` directly — `sale_years` optional metadata only |

---

## Implementation status (verified in repo)

| Task area | Status | Evidence |
|-----------|--------|----------|
| Migration `bh_snapshot_json` | **Done** | `priv/repo/migrations/20260609000000_add_bh_snapshot_json_to_ingestions.exs` |
| `compute_bh_snapshot` + persist on BH ingest | **Done** | `ingestions.ex` |
| `bh_has_current_shares?/1`, `has_active_holdings?/1` | **Done** | `ingestions.ex` |
| `UploadChecks` snapshot + G&L date gaps | **Done** | `upload_checks.ex` |
| `upload_checks_test.exs` (Users 1, 3, 5) | **Mostly done** | T2–T6, symbol consistency |
| Portfolio BH fallback removed | **Done** | `portfolio.ex` — `build/1` → `build_from_holdings/1` only |
| `portfolio_live` state machine | **Done** | `portfolio_state` in `mount/3` |
| Legacy `bh_snapshot_missing` | **Not done** | No nudge; wrong inference when snapshot null |
| R5 ESPP Yahoo removal | **Not done** | `silver_builder.ex` `process_espp` still `yahoo_close_safe` on `insert_sale!` |
| `portfolio.ex` moduledoc | **Stale** | Still mentions BH fallback — update comment only |
| T17 legacy BH test | **Not done** | In test-plan, not in test file |
| T18 ESPP no-allocation regression | **Not done** | In test-plan, not in test file |

---

## §Contradictions — resolve in official specs

Claude must pick **one** answer per row and update requirements + design + tasks + test-plan together.

### C.1 Portfolio readiness when fully sold (no current shares)

| Source | Says |
|--------|------|
| R2.2 table | `:not_applicable` |
| Definition of Done | `:blocked` |
| `upload_checks_test.exs` User 1 BH-only | `:not_applicable` |

**Cursor decision (locked):** `:not_applicable` — user has exited; nothing to portfolio. Not the same as missing Holdings (`:blocked`).

### C.2 Legacy BH (`bh_snapshot_json = null` after migration)

| Source | Says |
|--------|------|
| requirements R1.3 | Portfolio readiness `:blocked` |
| design Backfill | Portfolio readiness `:blocked` |
| tasks 4.11 | Portfolio readiness `:limited` |

**Cursor decision (locked):** `:blocked` on upload-check readiness + `:bh_snapshot_missing` info nudge. **Not** `:limited` (Portfolio never uses `:limited` per R2.2).

### C.3 `gl_coverage_gap` nudge

| Source | Says |
|--------|------|
| Out of Scope | unchanged |
| R2.3 | replaced / unified into `:no_gl_for_dates` |

**Cursor decision (locked):** Remove from Out of Scope; document `:gl_coverage_gap` as **removed** (tests already refute `:no_gl`).

### C.4 `unvested_count` field meaning

| Source | Says |
|--------|------|
| requirements R1.1 | Count of **shares** in UNVESTED tranches |
| `compute_bh_snapshot` | `count()` of UNVESTED **tranches** |

**Cursor decision (locked):** Rename snapshot field to `unvested_tranche_count` **or** change computation to `sum(vest_quantity)` where `status == UNVESTED`. Tranche count is sufficient for `has_current_shares` gate today; document explicitly whichever is chosen.

---

## §Gaps — remaining implementation

### G.1 Legacy BH path (`legacy_bh`)

**When:** `has_bh = true` and `load_bh_snapshots/1` returns `[]` (all ACTIVE BH ingestions have null `bh_snapshot_json`).

**Current bug:**

- `aggregate_snapshots([])` → zeros → `has_current_shares = false`
- Portfolio readiness → `:not_applicable` (wrong — state unknown)
- `bh_has_current_shares?/1` → false → Portfolio page → `:all_sold` (wrong)
- `:no_holdings` suppressed (wrong if user actually has unvested RSU)
- G&L gaps may still run from live `Sale` table (inconsistent with spec “skip”)

**Required in `check/1`:**

```elixir
legacy_bh = has_bh and snapshots == []

# when legacy_bh:
# - emit :bh_snapshot_missing (:info)
# - skip maybe_add_no_holdings (cannot evaluate)
# - skip add_gl_coverage_nudges OR keep with live Sale query — pick one; Cursor prefers skip + nudge explains re-upload
# - readiness.portfolio == :blocked
# - readiness.capital_gains == :blocked (cannot confirm coverage per R1.3 / T17)
```

**Portfolio page:** Add state or banner for legacy — e.g. `:snapshot_required` — “Re-upload Benefit History to refresh readiness checks” — **not** `:all_sold`.

**Optional:** `mix stock_plan.backfill_bh_snapshots` — recompute snapshot from Silver for ACTIVE BH without re-upload. Out of scope unless Claude wants ops convenience; re-upload is enough for single-tenant.

### G.2 R5 — ESPP Phase 1 Yahoo on `Sale` (revise spec wording)

**Spec error:** Design §4 “BEFORE” shows `create_gl_allocation` in ESPP Phase 1. **Current code does not.** ESPP only does:

```elixir
insert_sale!(..., %{sale_date, total_quantity, sale_price: yahoo_close_safe(...), ...})
```

**G&L coverage check** uses `SaleAllocation.sale_price NOT NULL` — Yahoo on `Sale` does **not** fool coverage today.

**Still fix R5 because:**

- Invariant #7 — don’t store invented `sale_price` on Silver `Sale`
- M24 History may read `sale.sale_price` before G&L and show wrong proceeds

**Required change** (`silver_builder.ex` `process_espp` sell reduce):

```elixir
insert_sale!(ing, origin, %{
  sale_date: sale_date,
  total_quantity: qty,
  metadata_json: Jason.encode!(%{purchase_date: ...})
})
# no sale_price, no proceeds, no yahoo_close_safe
```

Update design §4 to match **actual** before-state (Yahoo on Sale, not allocation).

### G.3 Stale documentation

- `portfolio.ex` `@moduledoc` — remove “BH fallback” bullet; state Holdings-only.
- `design.md` `load_bh_snapshots` — include `dominant_symbol` in select (matches code).

### G.4 Test gaps (from test-plan)

| Test | Action |
|------|--------|
| T17 legacy BH | Add to `upload_checks_test.exs` — insert ACTIVE BH with null snapshot |
| T18 ESPP Phase 1 | Assert `Sale.sale_price == nil`, zero allocations pre-G&L |
| T11–T14 Portfolio states | LiveView tests or document manual-only |

---

## §Locked decisions (for Claude)

| # | Topic | Decision |
|---|-------|----------|
| 1 | Fully sold portfolio readiness | `:not_applicable` (not `:blocked`) |
| 2 | Legacy null snapshot readiness | `:blocked` + `:bh_snapshot_missing` nudge |
| 3 | Portfolio `:limited` | Removed for Portfolio only; Schedule FA may still use `:limited` |
| 4 | G&L nudge code | `:no_gl_for_dates` only; remove `:no_gl` and `:gl_coverage_gap` |
| 5 | G&L coverage signal | `SaleAllocation` with `sale_price NOT NULL` per sale_id |
| 6 | BH snapshot sold tracking | Origin-level `Sale.total_quantity` sum — not `SaleAllocation` |
| 7 | Symbol nudges | `bh_symbols_with_unsold` from per-ingestion snapshot + `dominant_symbol` |
| 8 | Portfolio data source | Holdings Silver only; History (M24) for BH-derived analytics |
| 9 | ESPP Phase 1 sales | `Sale` date + qty only; no price until G&L |

---

## §Sample-user findings (context for spec)

These motivated the spec; confirm fixed after §Gaps:

| User | Issue (before fix) | Expected after fix |
|------|-------------------|-------------------|
| User 1 | Portfolio `:limited` with BH+G&L but no Holdings | Portfolio `:not_applicable` (all sold); no Holdings nudge |
| User 1 | Global `:no_gl` | `:no_gl_for_dates` for CY-1 uncovered sales |
| User 3 | Portfolio `:blocked` without Holdings despite needing BH view | Portfolio `:blocked` + `:no_holdings` error until Holdings uploaded |
| User 3 | Full data | All readiness `:ready`, no error/warning nudges |
| User 5 | `bh_without_holdings` for sold-out ADBE | Suppressed when snapshot shows 0 unsold |

---

## Master review checklist (Claude)

**Spec hygiene**

- [ ] Resolve §Contradictions C.1–C.4 in all four spec files
- [ ] Update tasks.md — check off Tasks 1–4, 6–7 items already done
- [ ] Remove / correct Out of Scope `gl_coverage_gap` line
- [ ] Fix design §4 R5 “BEFORE” block (Sale Yahoo, not allocation)
- [ ] Align `unvested_count` naming with implementation

**Code gaps**

- [ ] G.1 `legacy_bh` in `upload_checks.ex` + Portfolio page state
- [ ] G.2 Remove ESPP Yahoo from Phase 1 `insert_sale!`
- [ ] G.3 Stale moduledoc / design `load_bh_snapshots`

**Tests**

- [ ] T17 legacy BH
- [ ] T18 ESPP sale_price nil pre-G&L
- [ ] Re-run full suite + sample users 1, 3, 5

**Cross-milestone**

- [ ] M24 History: confirm BH-only sold qty / price behavior after R5 (no Yahoo on `Sale`)
- [ ] `invariants.md` §4 — already updated; no further change unless Portfolio legacy state added

---

## How to use this file

1. **Cursor** appends new sections here with changelog row.  
2. **Claude** Accept/Rejects items in §Accept/Reject and §Locked decisions, then updates `requirements.md`, `design.md`, `tasks.md`, `test-plan.md`.  
3. Do **not** create `upload-checks-feedback-*.md` siblings — keep one source of truth.  
4. After implementation, mark checklist items done here or add a “Completed” changelog row.
