# M26 Schedule FA v2 — Feedback 2 (Post-Fix Review)

> **SUPERSEDED — 2026-06-13: ESPP unification.** Rule 3 uses `holdings_qty` for all plan
> types (RSU + ESPP). The `net_qty − SUM(sells)` ESPP formula accepted in this doc is
> **replaced**. See updated `requirements.md §3` and `design.md` (`effective_holdings`
> section). Do not use this doc as implementation guidance for `effective_holdings`.

Review date: 2026-06-11  
Reviewer: Cursor  
Baseline: revised `requirements.md`, `design.md`, `tasks.md`, `test-plan.md` after ESPP/P1 fixes  
Prior review: `cursor-feedback-on-specs.md` (Feedback 1)

---

## Accept / Reject — Fixes in This Revision

| Fix | Verdict | Justification |
|---|---|---|
| P1 expanded to RSU + ESPP (all BH sell dates `>= cy_start`) | **Accept with caveat** | Consistent if FA is all-or-nothing — no row without computable `sale_proceeds_inr`. Creates conflict with Req 8; see Blocking Issue #1. |
| ESPP `effective_holdings = net_qty − SUM(all sells)` from BH timeline | **Accept** | ESPP BH has per-purchase sell history; Holdings file not needed for Rule 3 quantities. Fixes User 1 ESPP quantity path. |
| ESPP Rule 3 algebra (`start_count = net_quantity − pre_cy_sells`) | **Accept** | Equivalent to `cy_sale + beyond_sale + holdings`; good documentation for implementers. |
| P2 unchanged (snapshot fast-path + per-origin RSU check) | **Accept** | User 1 fully-exited pattern still works without Holdings upload. |
| Rules 1–3 + hard block on P1/P2 | **Accept** | Correctly supersedes regression-test-fixes R1 soft degradation. |
| Upload readiness via `schedule_fa_readiness/2` for CY-1 | **Accept** | Fixes badge vs Tax Centre mismatch from upload-checks-fix. |
| Retire `held_during_cy` from FA path only | **Accept** | History page dependency preserved. |

| Item | Verdict | Justification |
|---|---|---|
| Req 8 "ESPP via BH still appears" without G&L | **Reject as written** | Contradicts ESPP-inclusive P1 — User 1 BH-only blocks before row construction. |
| `test-plan.md` P1.7 "RSU-only check" | **Reject** | Stale — contradicts Req 2 P1 (all plan types). |
| `tasks.md` 1.1 "RSU dates only" | **Reject** | Stale — must say all plan types. |
| `cursor-feedback-on-specs.md` (Feedback 1) | **Reject as current** | Not updated for ESPP P1 expansion; superseded by this doc for open items. |

---

## Blocking Issue #1: Req 8 vs P1 (ESPP)

**Requirement 8** states lots sold during CY via ESPP BH should still appear in FA output.

**P1 (current)** requires G&L for every BH sell date `>= cy_start`, including ESPP.

**SampleUser 1, BH only, FA 2024:**
- ESPP BH sells exist on/after 2024-01-01 (e.g. 2024-05-03)
- No G&L uploaded
- **P1 blocks → `{:error, _}` → zero rows**

Req 8 and P1 cannot both be true today. **Resolve before implementation.**

### Option A — Split P1 by plan type (Recommended)

```
RSU:
  bh_dates_required = BH RSU sell dates where sale_date >= cy_start
  → G&L required (no per-tranche dates without G&L)

ESPP:
  → P1 does NOT block on missing G&L for quantity computation
  → Quantities from BH per-purchase sells (already in timeline.sells)
  → sale_proceeds_inr = 0 when sell source is :bh (no price)
  → Optional: warn when cy_sale > 0 and no G&L price available
```

Aligns with original user intent: G&L required for RSU filing year scope; ESPP structure from BH.

### Option B — Strict P1 for all types

Keep ESPP-inclusive P1. Update Req 8:

> Fully-exited users must upload G&L covering all ESPP sell dates in or after the filing year
> before Schedule FA can be built. ESPP rows without G&L are not produced.

Simpler spec; User 1 BH-only always blocked for years with ESPP activity.

**Recommendation:** Option A. Option B is acceptable if product decision is "no partial FA ever."

### Resolution (2026-06-11, product decision)

**Option B adopted.** No partial FA. P1 blocks for ESPP and RSU without G&L. Req 8 carve-out
removed. Checklist below applied to spec files.

---

## Stale Artifacts — Must Patch Before Implementation

| File | Location | Current (wrong) | Should be |
|---|---|---|---|
| `test-plan.md` | P1.7 | ESPP dates only, no G&L → `:ok` (RSU-only check) | `:error` under strict P1, OR remove P1.7 if Option A exempts ESPP |
| `test-plan.md` | TP-1 header | "BH RSU sale dates" column | "BH sell dates (RSU + ESPP)" or split columns |
| `tasks.md` | 1.1 | "RSU dates `>= cy_start` only" | "all plan types" or split RSU/ESPP logic per Option A/B |
| `design.md` | Example § SampleUser 1 | "P1: BH RSU sells in/after 2024" | Include ESPP sells; note block vs pass per chosen option |
| `test-plan.md` | I1 | "OR `{:ok}` if P1 passes" ambiguous | User 1 BH-only FA 2024 → `{:error, _}` under strict P1 |

---

## Non-Blocking Gaps

### G1: `sale_proceeds_inr` for ESPP BH-only sells

Req 4 says proceeds from G&L sells in CY only. Spec should explicitly state:

- ESPP rows with `source: :bh` sells may have `sale_proceeds_inr = 0`
- Row is still valid for initial / peak / closing if Option A adopted

### G2: ESPP quantity-match ambiguity (carried from Feedback 1 Q2)

`effective_holdings` and Rule 3 depend on `t.sells` from BH quantity match (`Enum.take(1)`).
Multiple ESPP purchases with identical `net_quantity` can misassign sells.

**Recommendation:** Add non-blocking warning (V3-style) when ESPP BH match is ambiguous.
Track as follow-up (M27 or DHF item). Not a blocker for M26 if documented.

### G3: `:limited` readiness scope

Req 6: `:limited` when `has_current_shares && !has_holdings`.

With ESPP not requiring Holdings for quantities, a user with only ESPP current shares and
no Holdings may still show `:limited` — correct for RSU accuracy. Consider one-line note
that ESPP-only fully-sold accounts (`snapshot` fully exited) get `:ready` without Holdings.

### G4: Feedback 1 open questions — status

| Q | Feedback 1 | Feedback 2 status |
|---|---|---|
| Q1: FA 2024 + 2025 G&L only | Keep as specced | **Still open** — unchanged; P1 blocks until 2025 G&L present |
| Q2: ESPP quantity-match | Follow-up warning | **Still open** — add task or defer to M27 |
| Q3: `initial_value_inr` Rule 3 | Accept Phase 1 | **Closed** — no change needed |

---

## Consistency Check (Revised Spec vs Codebase)

| Area | Status |
|---|---|
| M14 FA-1 row field semantics | ✅ Aligned |
| M21 `TrancheTimeline` unchanged | ✅ Aligned |
| User 1 RSU false holdings (partial G&L) | ✅ Fixed by Rule 3 + P2 |
| User 1 ESPP quantity derivation | ✅ Fixed by `effective_holdings` |
| User 1 BH-only FA build | ❌ Blocked by ESPP-inclusive P1 (unless Option A) |
| Upload readiness global CY-1 block | ✅ M26 Milestone 4 addresses |
| regression-test-fixes R1 soft path | ✅ Correctly superseded |
| DHF-16 (sold lots shown as held) | ✅ Addressed; close in Milestone 6.2 after Option resolved |

---

## Implementation Risks (Updated)

| Risk | Severity | Mitigation |
|---|---|---|
| Req 8 / P1 contradiction | **Blocker** | Resolve Option A or B; update Req 8 + P1 + tests together |
| Stale test-plan / tasks wording | **High** | Patch table in "Stale Artifacts" before coding |
| Existing `schedule_fa_test.exs` expects soft warnings | **High** | Milestone 3.6 — update to `{:error}` expectations |
| ESPP BH match assigns wrong sale | **Medium** | G2 warning; not M26 blocker |
| Tax Centre error for years user won't file | **Low** | Clear P1 error message with dates + year |

---

## Required Spec Edits (Checklist)

- [x] Resolve Blocking Issue #1 — **Option B**
- [x] Update Req 8 — remove ESPP-via-BH carve-out
- [x] Fix `test-plan.md` TP-1 (P1.7, headers, I1)
- [x] Fix `tasks.md` 1.1 — all plan types
- [x] Update `design.md` SampleUser 1 example — ESPP in P1 check
- [x] Add G3 `:limited` note to Req 6
- [ ] G1 proceeds note — moot under Option B (P1 guarantees G&L before rows)

---

## Verdict

**Ready for implementation** (Option B). Proceed Milestones 1–3 (pre-checks + `compute_cy_state` +
wire `build/2`), then Milestone 4 (upload readiness).

---

## Changelog from Feedback 1

| Feedback 1 item | Feedback 2 update |
|---|---|
| P1 RSU-only | **Changed** — spec now RSU + ESPP; new contradiction flagged |
| ESPP out of scope | **Resolved** — ESPP in Rules 1–3 with BH `effective_holdings` |
| Q1–Q3 open questions | Q3 closed; Q1/Q2 still open |
| "Ready for implementation" | **Downgraded** — blocked on Req 8 / P1 conflict |
