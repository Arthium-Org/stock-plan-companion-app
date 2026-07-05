# Requirements — Regression Test Fixes

**Source:** `docs/test-report-2026-06-10.md`  
**Branch:** `feature/m22-multi-symbol`  
**Scope:** Three bugs found during cross-user regression testing. No new features.

**Cursor follow-up:** `cursor-feedback-on-specs.md` in this folder — Accept/Reject review + UI gaps.

---

## Background

Regression testing against all 5 sample users (u1–u5) surfaced three issues:

| ID | Feature | Users affected |
|----|---------|---------------|
| FA-1 | Schedule FA returns hard error for years without full G&L coverage | u3, u5 |
| CG-1 | Capital Gains processes and displays incomplete rows when G&L not available | u1, u3, u5 |
| SA-2 | Sell Advisor returns `:no_current_price` instead of `:no_sellable_lots` for users with no Holdings | u1 |

`FA-2` (nil `cost_basis_per_share` on aggregated Schedule FA rows) and `SA-1` (`:no_sellable_lots` for fully-sold users with Holdings) were reviewed and determined to be **correct behaviour** — not defects.

---

## R1: Schedule FA — graceful degradation when G&L missing for a calendar year (FA-1)

### Problem

`ScheduleFA.build(account_id, calendar_year)` calls `TrancheTimeline.validate_cy_coverage/3` to confirm G&L exists for all RSU sale dates in the requested calendar year. When G&L is missing (e.g., user uploaded 2025/2026 G&L but not 2024), this returns `{:error, "G&L data missing for RSU sell dates: ..."}`.

The LiveView catches this and shows an error banner. However, the Upload page readiness shows `:ready` for Schedule FA — the readiness check only validates CY-1 (the previous calendar year), not the year the user selects. The mismatch means clicking CY2024 in the Tax Centre shows an error even though the readiness badge said "Ready".

### Required behaviour

`ScheduleFA.build/2` must **never return `{:error, _}`** for missing G&L. Instead:

- Return `{:ok, [], [warning]}` where `warning` is a human-readable message:  
  `"G&L data not available for this period. Sales on [date1], [date2], … are not covered — upload G&L for [year] to generate Schedule FA."`
- The LiveView renders an empty table with the warning message displayed inline (existing warning rendering pathway).
- Rows for tranches that have **no sale activity** in the requested year are still computed and returned normally — only the validation gate is removed.

### Constraints

- Do not change `TrancheTimeline.validate_cy_coverage/3` — it may be used elsewhere.
- The change is local to `ScheduleFA.build/2`: replace the `{:error, msg} → {:error, msg}` arm with `{:error, msg} → {:ok, rows, [human_message]}`.
- Existing `{:ok, rows, warnings}` path is unchanged.

---

## R2: Capital Gains — block computation when G&L not available for the FY (CG-1)

### Problem

`CapitalGains.build(account_id, fy_start_year)` queries all sales in the FY window and produces rows regardless of G&L coverage. For sales with no G&L allocation data, it creates rows with:
- `sale_price: nil`
- `gain_loss_usd: nil`, `gain_loss_inr: nil`
- `gain_type: :unknown`
- `warning: "Lot details unavailable — upload G&L Expanded for this FY"`

These nil rows inflate the row count and give the false impression that capital gains have been computed. The summary shows `stcg_inr: 0`, `ltcg_inr: 0` — which a user could misread as "no gains".

### Required behaviour

Before building rows, detect whether the FY has **zero G&L coverage**:

- If no sale allocations exist for any sale in the FY window (i.e., every sale is an "unknown" row) → return `{[], summary}` where `summary` contains a `warning` field:  
  `"G&L data not available. Sales on [date1], [date2], … cannot be computed — upload G&L Expanded for [FY]."`
- If **some** sales have G&L coverage and **some** do not → include only the covered rows. Add a `warning` field to `summary` listing the uncovered sale dates. Do not include unknown rows.
- If all sales have G&L coverage → current behaviour, no change.

### Coverage detection

A sale is "covered" if it has at least one `sale_allocation` record with a non-nil `sale_price` (either on the allocation or the sale). This is the same signal used by `UploadChecks.compute_gl_coverage_gaps/1`.

### Summary warning field

Add a `warning` key to the summary map. The LiveView Tax Centre renders this warning inline above the table when present.

---

## R3: Sell Advisor — return `:no_sellable_lots` when no Holdings ingested (SA-2)

### Problem

`SellAdvisorV2.advise/3` resolves the default symbol via `Portfolio.held_symbols(account_id)`. For a user with no Holdings file uploaded, `held_symbols` returns `[]`, symbol is `nil`, and the price fetch is skipped — `current_price = nil`. The `with` chain then fails at `validate_price_fx(nil, fx)` and returns `{:error, :no_current_price}`.

The correct error is `:no_sellable_lots` (or `:no_holdings`). The Sell Advisor LiveView renders a misleading "price unavailable" error rather than "nothing to sell".

Root cause path:
```
held_symbols([]) → symbol = nil → current_price = nil → validate_price_fx fails → :no_current_price
```

This does **not** affect users with Holdings uploaded (u2, u5) because `held_symbols` returns a symbol, the price fetch succeeds, and the `with` chain correctly reaches `load_sellable_lots` which returns `[]`.

### Required behaviour

If no sellable lots exist **before** attempting price fetch, return `{:error, :no_sellable_lots}` immediately.

Implementation: add an early-exit check at the top of `SellAdvisorV2.advise/3`:

```elixir
lots = SellAdvisor.load_sellable_lots(account_id, symbol_hint)
if lots == [] do
  {:error, :no_sellable_lots}
else
  # existing with-chain using current_price / current_fx
end
```

Where `symbol_hint = Keyword.get(opts, :symbol)` — the explicitly passed symbol if any, else `nil` (the load will query all holdings for the account). Do not call `resolve_default_symbol` before the lots check — that resolves from Holdings which may not exist.

### Constraints

- The `load_sellable_lots(account_id, nil)` query is cheap (indexed on account_id, status, sellable_qty).
- The explicit `symbol` opt (passed from the LiveView) is preserved — lots are still filtered by symbol when provided.
- For u2/u5 (Holdings present, all sold), the early check still returns `:no_sellable_lots` correctly and avoids an unnecessary Yahoo price fetch.
