# Cursor Feedback on Regression Test Fixes Specs

**Status:** Living document — append sections here; do not create separate feedback files per topic.  
**Audience:** Claude / implementer on `feature/m22-multi-symbol`  
**Source report:** `docs/test-report-2026-06-10.md`  
**Official specs:** `requirements.md`, `design.md`, `tasks.md`, `test-plan.md` in this folder.

> **Note:** An earlier Cursor review targeted `upload-checks-fix/` by mistake. This file is the correct follow-up for the three regression bugs (FA-1, CG-1, SA-2).

---

## Changelog

| Date | Section | Summary |
|------|---------|---------|
| 2026-06-10 | §Review | Initial review against test report + current code |
| 2026-06-10 | §UI | `fa_warnings` not rendered — spec assumes pathway that does not exist |
| 2026-06-10 | §Design | Fix CG coverage detection + FA error tuple shape |

---

## Executive summary

The **regression-test-fixes** spec correctly scopes **three real bugs** from the 5-user test pass. **FA-2** and **SA-1** are correctly excluded (data gaps / readiness semantics, not defects).

**None of the three fixes are implemented yet** — code still matches pre-fix behaviour:

| Bug | Current behaviour |
|-----|-------------------|
| FA-1 | `ScheduleFA.build/2` returns `{:error, binary}` → Tax Centre `fa_error` red banner |
| CG-1 | `build_unknown_row/1` still emitted; `unknown_count` banner in Tax Centre |
| SA-2 | `SellAdvisorV2` fetches price before lots; u1 gets `:no_current_price` |

Spec direction is **Accept** with corrections below before/during implementation.

---

## Accept / Reject — spec items

| Item | Verdict | Justification |
|------|---------|---------------|
| R1 Schedule FA soft degradation (FA-1) | **Accept** | Fixes readiness vs CY2024 error mismatch for u3/u5 |
| R2 Capital Gains drop unknown rows + summary warning (CG-1) | **Accept** | Upgrades test report “no code change” — better UX than nil rows |
| R3 Sell Advisor early `load_sellable_lots` (SA-2) | **Accept** | Correct error atom; avoids useless price fetch |
| Exclude FA-2 (nil cost_basis_per_share) | **Accept** | `initial_value_inr` populated; Holdings gap only |
| Exclude SA-1 (ready but no lots) | **Accept** | Readiness = data available, not actionability |
| Do not change `validate_cy_coverage/3` | **Accept** | Local change in `ScheduleFA.build/2` only |
| Design `{:error, {uncovered_dates, year}}` | **Reject** | Actual return is `{:error, message_string}` — see §D.1 |
| “Existing warning rendering pathway” for FA | **Reject** | `@fa_warnings` assigned but **never rendered** in HEEx |
| SA-2 root cause “Yahoo network fail” | **Reject wording** | u1: `held_symbols == []` → `symbol = nil` → `current_price = nil` before lots check |
| Design CG `MapSet.new(allocs, & &1.sale_id)` | **Reject** | `fetch_allocations` returns **grouped map**; must check `sale_price NOT NULL` per R2 |
| R1 “return `{:ok, [], [warning]}`” only | **Reject wording** | Error path should still build **timeline rows** (may be non-empty) — design §Fix 1 is right |
| Alternative (b) year tabs “Limited” on Upload | **Reject** | Spec chose (a) soft degradation — do not implement both |

---

## Locked decisions (for Claude)

| # | Topic | Decision |
|---|-------|----------|
| 1 | FA-1 on G&L gap | `{:ok, rows, [warning \| …]}` — never `{:error, binary}` for missing CY G&L |
| 2 | FA rows when G&L gap | Still run `held_during_cy` → `build_fa_rows_from_timeline` → `aggregate_by_date` |
| 3 | CG uncovered sales | Do **not** emit `build_unknown_row`; omit from rows |
| 4 | CG coverage signal | Sale “covered” iff ∃ allocation with `sale_price NOT NULL` **or** `sale.sale_price NOT NULL` (same as UploadChecks intent) |
| 5 | CG all-uncovered FY | `{[], summary \| warning: msg}` — no `unknown_count` inflation |
| 6 | SA-2 order | `load_sellable_lots(account, explicit_symbol)` **before** price/FX; reuse result in `with` |
| 7 | SA-2 error | `{:error, :no_sellable_lots}` — not `:no_holdings` (LiveView already handles both) |
| 8 | Upload readiness | **No change** in this milestone — CY-1-only readiness mismatch for older years is UX-fixed via FA-1/CG-1, not readiness rewrite |

---

## §D — Design corrections

### D.1 `validate_cy_coverage/3` return shape (verify before coding)

**Actual code** (`tranche_timeline.ex`):

```elixir
{:error, "G&L data missing for RSU sell dates: #{dates_str}. Upload G&L for #{calendar_year}."}
```

**Not** `{:error, {uncovered_dates, year}}`.

**Implementation options (pick one):**

| Option | Approach |
|--------|----------|
| A (minimal) | On `{:error, msg}` when `is_binary(msg)`, call existing row build path; `warning = msg` or `format_gl_warning_from_string/1` |
| B (cleaner) | Before `validate_cy_coverage`, compute `missing_dates` locally in `schedule_fa.ex` (duplicate filter logic) → custom warning without parsing |
| C (future) | Structured error tuple — **out of scope** (constraint: do not change `validate_cy_coverage`) |

**Cursor recommends B or pass-through A:** use the validation message as `warning` verbatim in v1 — already lists dates and year.

### D.2 Capital Gains coverage split (fix design pseudocode)

`fetch_allocations/1` returns `%{sale_id => [alloc, …]}`.

```elixir
covered? = fn sale_id ->
  case Map.get(allocations, sale_id) do
    nil -> false
    allocs ->
      Enum.any?(allocs, fn a -> a.sale_price != nil end) ||
        (sale = sale_by_id[sale_id]; sale && sale.sale_price != nil)
  end
end
```

Do **not** use `MapSet.new(allocs, & &1.sale_id)` on the grouped map.

### D.3 SA-2 root cause (accurate)

```
held_symbols([])  # no Holdings
→ symbol = nil    # unless explicit opt
→ current_price = nil (no fetch OR skipped)
→ validate_price_fx fails
→ :no_current_price   # never reaches load_sellable_lots
```

Test report mentioned Yahoo — relevant only when symbol exists but price nil. **u1 path is no Holdings.**

---

## §UI — gaps not in tasks (add before “done”)

### U.1 Schedule FA warnings not displayed

`tax_centre_live.ex` assigns `fa_warnings` but template has **no `@fa_warnings` render**.

**Required:**

```heex
<%= for w <- @fa_warnings || [] do %>
  <div class="alert alert-warning mb-4"><span>{w}</span></div>
<% end %>
```

Place **above** the table (inside `render_schedule_fa`), when `fa_error == nil`.

### U.2 Empty FA table + warning copy

Current branch when `@fa_data == []`:

> "No foreign assets held during CY {year}"

When `fa_warnings != []` and rows empty, show the **warning** instead — otherwise user sees contradictory empty state after FA-1 fix.

### U.3 Capital Gains summary warning

Tasks 2.6 cover `summary.warning` — good. **Also** remove or gate the existing `unknown_count` banner once unknown rows are never built:

```heex
<%= if @cg_summary.unknown_count > 0 do %>
```

After CG-1, `unknown_count` should stay 0 whenever rows are shown; all-uncovered FY uses `summary.warning` only.

---

## §Sample-user expected outcomes (post-fix)

| User | FA CY2024 | CG FY2024 | Sell Advisor |
|------|-----------|-----------|--------------|
| u1 | `{:ok, _, [warning]}` (no G&L) | `{[], summary.warning}` | `:no_sellable_lots` |
| u3 | `{:ok, rows, [warning]}` not error | `{[], summary.warning}` | `{:ok, _}` unchanged |
| u5 | `{:ok, rows, [warning]}` not error | `{[], summary.warning}` | `:no_sellable_lots` unchanged |
| u2 | unchanged if G&L covers CY2024 sales | rows if covered; no unknown rows | unchanged |
| u4 | unchanged | unchanged | unchanged |

**u1 Schedule FA:** timelines may still produce rows for tranches held in CY — warning + table is valid.

---

## §Test-plan additions

| ID | Gap | Action |
|----|-----|--------|
| T-UI-1 | FA warnings render | LiveView test or manual: switch to CY2024 u3 → warning visible, not `fa_error` |
| T-UI-2 | FA empty + warning | u1 CY2024 — no “No foreign assets” when warning present |
| T-CG-1 | Partial coverage | BH sale A covered, sale B not → rows for A only + summary.warning lists B |
| T-SA-1 | No double query | Assert `load_sellable_lots` called once (optional Mox) |

**T4 footnote:** “u2 FY2024 nil rows expected” may **change** after CG-1 if those 6 sales lack G&L — re-verify against fixture before locking regression script.

---

## Implementation status

| Task | Status |
|------|--------|
| Fix 1 Schedule FA | **Not started** |
| Fix 2 Capital Gains | **Not started** |
| Fix 3 Sell Advisor | **Not started** |
| Fix 4 full suite | Tax: 148 tests, **1 failure** (User 4 FA row regression — pre-existing, unrelated to this spec) |

---

## Master review checklist (Claude)

**Spec hygiene**

- [ ] Fix `design.md` §Fix 1 error tuple shape (string, not structured)
- [ ] Fix `design.md` §Fix 2 coverage split (grouped allocs + `sale_price`)
- [ ] Fix `requirements.md` R1 — may return non-empty rows, not only `[]`
- [ ] Add tasks for U.1–U.3 (FA warnings render, empty state, CG unknown banner)

**Code**

- [ ] R1 — `schedule_fa.ex` soft path + warning
- [ ] R2 — `capital_gains.ex` coverage filter + `summary.warning`
- [ ] R3 — `sell_advisor_v2.ex` early lots exit
- [ ] `tax_centre_live.ex` — render `fa_warnings` + `cg_summary.warning`

**Tests**

- [ ] T1–T3 automated where possible (use isolated accounts u1/u3/u5)
- [ ] Re-run `docs/test-report-2026-06-10.md` script — FA-1/CG-1/SA-2 cleared

**Out of scope (do not expand)**

- [ ] Upload readiness per selected year (separate milestone)
- [ ] Schedule FSI same CY-selection issue (note only)
- [ ] FA-2 cost basis from Holdings
- [ ] SA-1 readiness label for fully-sold users

---

## How to use this file

1. **Cursor** appends sections here with changelog row.  
2. **Claude** Accept/Rejects §Accept/Reject + §Locked decisions, updates the four official spec files, implements checklist.  
3. Do **not** create `regression-feedback-*.md` siblings.
