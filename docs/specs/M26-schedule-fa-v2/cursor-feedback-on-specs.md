# M26 Schedule FA v2 — Spec Review

Review date: 2026-06-11  
Reviewer: Cursor (against M14, M21, upload-checks-fix, regression-test-fixes, and live code)

---

## Accept / Reject — Prior Art & Draft Decisions

| Item | Verdict | Justification |
|---|---|---|
| Replace `held_during_cy` formula with Rule 1–3 `compute_cy_state` | **Accept** | Fixes partial-G&L inflation and pre-CY quantity errors (verified on User 1) |
| P1: G&L required for RSU sells `>= cy_start` (not entire history) | **Accept** | Aligns with user expectation; pre-CY sells implicit in Holdings |
| P1: Also require G&L for post-CY sells when filing earlier CY | **Accept** | Rule 3 `beyond_sale` needs future sell dates to compute Dec 31 balance |
| P2: Holdings required only when BH shows unsold shares | **Accept** | Matches upload-checks-fix R1 + broker Holdings authority |
| P2: Use `bh_snapshot` for fully-exited account fast-path | **Accept** | User 1 pattern; snapshot already computed at ingest |
| Hard-block on P1/P2 (revert soft degradation) | **Accept** | Prevents misleading FA rows; supersedes regression-test-fixes R1 |
| Retire `closing=0 AND proceeds=0` row filter | **Accept** | CY-sold lots are valid FA rows with `end_count=0` |
| Keep `TrancheTimeline` unchanged | **Accept** | History page dependency; FA-only refactor |
| ESPP via existing BH quantity match in `timeline.sells` | **Accept** | Minimal scope; ESPP BH has per-purchase granularity |
| Upload readiness per CY-1 via same P1/P2 | **Accept** | Fixes badge vs Tax Centre mismatch |
| Rule 3: `start = cy_sale + beyond_sale + holdings` | **Accept** | Algebraically correct for opening CY balance |
| Exclude `start_count == 0` only | **Accept** | Matches M14 "held during CY" definition |

| Item | Verdict | Justification |
|---|---|---|
| Require G&L for CY only (strict, no beyond-CY) | **Reject** | Would make Dec 31 2024 balance unknowable when 2025 sells exist without Holdings |
| Keep soft-degradation with partial rows | **Reject** | Root cause of User 1/3 confusion; shows false holdings |
| Global `uncovered_cy1` block unrelated to selected FA year | **Reject** | Current upload_checks bug; replaced by per-year pre_check |
| Delete `TrancheTimeline.validate_cy_coverage/3` | **Reject** | May be referenced elsewhere; FA path only replaces it |
| ESPP fully out of scope with no sell source | **Reject** | User 1 FA rows are ESPP; must use BH sells in Rules 1–3 |

---

## Gaps Found in Initial Draft (fixed in this revision)

1. **Missing introduction** — linked M14/M21/supersedes list added.
2. **ESPP "out of scope"** — narrowed to "no new ESPP parser"; BH sells feed Rules 1–3.
3. **Upload checks** — Requirement 6 + tasks Milestone 4 added.
4. **API contract** — Requirement 5 documents hard error vs warnings.
5. **Fully-exited user** — Requirement 8 documents SampleUser 1 expected behavior.
6. **Design naming** — `check_gl_coverage_all_years` typo fixed to `check_gl_coverage_for_fa_year`.
7. **Row filter removal** — documented in design (sold-during-CY rows kept).

---

## Open Questions (for user/CA confirmation)

### Q1: FA 2024 with 2025 G&L only

If user uploads 2025 G&L but not 2024 G&L, P1 for FA 2024 **blocks** (2025 BH dates need G&L).
If user uploads 2025 G&L and P1 passes, Rule 3 shows pre-CY tranches with `beyond_sale` from
2025 — **correct** for "held on Dec 31 2024" tax disclosure.

**Recommendation:** Keep as specced. UI message should explain why later-year G&L is needed.

### Q2: ESPP BH quantity-match ambiguity

Multiple ESPP purchases with same `net_quantity` can match wrong BH sale (`Enum.take(1)`).

**Recommendation:** Out of scope for M26; add warning in V3-style if ESPP match is ambiguous.
Track as follow-up (M27 or DHF item).

### Q3: `initial_value_inr` for Rule 3

Uses `start_count × vest_fmv`, not proportional cost for shares sold pre-CY.

**Recommendation:** Accept for Phase 1 — matches M14 "initial value at start of holding period
during CY". CA review if needed.

---

## Consistency Check

| Spec | M26 alignment |
|---|---|
| M14 FA-1 row semantics | Compatible — quantities fixed |
| M14 FA-4 | Superseded by M26 Req 1–2 |
| M21 V2 (CY-only) | Extended: P1 adds beyond-CY dates for same filing year |
| M21 Req 6 BH validation | P2 supersedes for FA; timeline validation kept for History |
| upload-checks-fix R2.4 | Updated via M26 Req 6 |
| regression-test-fixes R1 | Superseded — hard block restored |
| data-handling-fixes DHF-16 | Addressed by Rule 3 + P2 |

---

## Implementation Risk

| Risk | Mitigation |
|---|---|---|
| Breaking existing FA tests expecting soft warnings | Milestone 3.6 updates tests |
| User 3 partial Holdings | P2 blocks — correct, Holdings mandatory |
| Performance (load all allocations) | Unchanged from current; acceptable |
| Tax Centre shows error for years user doesn't file | Year selector + clear error message |

---

## Verdict

**Spec is ready for implementation** after this revision. No blocking issues remain.
Proceed with Milestones 1–3 (core algorithm) before Upload readiness (Milestone 4).
