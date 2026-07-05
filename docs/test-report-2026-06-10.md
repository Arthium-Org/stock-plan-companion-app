# Feature Test Report — 2026-06-10

Branch: `feature/m22-multi-symbol`  
Tested via: programmatic eval against isolated accounts (u1–u5), not browser  
Server: running at localhost:4002

---

## Test Data Summary

| Account | Files Uploaded | Profile |
|---------|---------------|---------|
| u1 | BH only (no G&L, no Holdings) | ADBE only. Fully sold / terminated. |
| u2 | BH + Holdings + G&L 2025 + G&L 2026 | ADBE only. Fully sold. |
| u3 | BH + Holdings + G&L 2025 + G&L 2026 | ADBE only. Partial sell — 90 shares still held. |
| u4 | BH + Holdings + G&L (single file) | ADBE only. Partial sell — 145 RSU + 4 ESPP lots held. |
| u5 | BH ADBE + BH CRM + Holdings CRM only + G&L | Multi-symbol. ADBE fully sold. CRM RSU unvested (grant 2025-07-22). |

---

## Upload Page Readiness

All ingestions succeeded (no parse errors). Readiness panel results:

| Account | Portfolio | Vesting | Capital Gains | Sched FA | Sell Advisor |
|---------|-----------|---------|--------------|----------|-------------|
| u1 | N/A ✓ | Ready ✓ | Blocked ✓ | Blocked ✓ | Limited ✓ |
| u2 | Ready ✓ | Ready ✓ | Ready ✓ | Ready ✓ | Ready ✓ |
| u3 | Ready ✓ | Ready ✓ | Ready ✓ | Ready ✓ | Ready ✓ |
| u4 | Ready ✓ | Ready ✓ | Ready ✓ | Ready ✓ | Ready ✓ |
| u5 | Ready ✓ | Ready ✓ | Ready ✓ | Ready ✓ | Ready ✓ |

**Notes:**
- u1 Portfolio shows **N/A** (grey badge) — correct, all shares sold. ✓
- u1 Capital Gains / Schedule FA blocked — correct, no G&L uploaded. ✓
- u1 Sell Advisor shows **Limited** — correct, no Holdings file. ✓

---

## Portfolio

Portfolio.build tested for all accounts. Holdings data loads correctly.

| Account | RSU Origins | ESPP Origins | Notes |
|---------|-------------|-------------|-------|
| u1 | 0 | 0 | not_applicable — no Holdings |
| u2 | 0 sellable | 0 sellable | Holdings shows 0 sellable qty — all sold |
| u3 | 5 origins | 2 origins | Tranches with sellable qty populated ✓ |
| u4 | 9 origins | — | Tranches with sellable qty populated ✓ |
| u5 | 1 CRM origin | 0 | 13 future vest tranches (2026–2029), ADBE absent (no ADBE Holdings) |

**No bugs found in Portfolio layer.**

---

## Capital Gains

`CapitalGains.build(account, fy_start_year)` tested for FY2024 and FY2025.

| Account | FY2024 rows | FY2024 nil price | FY2025 rows | FY2025 nil price |
|---------|------------|-----------------|------------|-----------------|
| u1 | 12 | 8 (no G&L — expected) | 29 | 25 (no G&L — expected) |
| u2 | 6 | 0 ✓ | 35 | 0 ✓ |
| u3 | 5 | **4 of 5** ⚠ | 7 | 0 ✓ |
| u4 | 0 | — | 37 | 0 ✓ |
| u5 | 8 | **5 of 8** ⚠ | 12 | 0 ✓ |

**STCG/LTCG computed correctly** for u2/u3/u4/u5 FY2025 (non-nil rows).  
u4 FY2025 shows both STCG and LTCG — correctly classified by holding period. ✓

### Issue CG-1 — u3, u5: FY2024 rows have nil sale_price (WARN)
**Severity:** Warning (expected data gap, not a code bug)  
**Users:** u3, u5  
**Cause:** u3 and u5 uploaded G&L for 2025/2026 only; sales that occurred in 2024 predate the G&L window. The FY2024 rows correctly show nil price / nil gain.  
**Readiness:** Capital Gains readiness is `:ready` — correct, because the readiness check only validates CY-1 (2025) coverage.  
**Impact:** If user navigates to FY2024 tab in Tax Centre, they see rows with missing data. No error — the rows are rendered with the "G&L unavailable" warning field. Low severity.  
**Action:** No code change needed. Could add a UI note "FY2024 data incomplete — upload earlier G&L" but not blocking.

---

## Schedule FA

`ScheduleFA.build(account, calendar_year)` tested for CY2024 and CY2025.

| Account | CY2024 | CY2025 |
|---------|--------|--------|
| u1 | Error (no G&L — expected ✓) | Error (no G&L — expected ✓) |
| u2 | 11 rows, 11 nil cost_basis_per_share ⚠ | 21 rows, 21 nil cost_basis_per_share ⚠ |
| u3 | **Error: readiness=ready but build failed** ❌ | 23 rows, 5 nil cost_basis_per_share ⚠ |
| u4 | 35 rows, 16 nil cost_basis_per_share ⚠ | 45 rows, 45 nil cost_basis_per_share ⚠ |
| u5 | **Error: readiness=ready but build failed** ❌ | 12 rows, 12 nil cost_basis_per_share ⚠ |

### Issue FA-1 — u3, u5: Schedule FA CY2024 fails when readiness=ready (ERROR)
**Severity:** Medium  
**Users:** u3, u5  
**Cause:** The readiness check validates only CY-1 (2025) G&L coverage. u3 and u5 have RSU sales in 2024 not covered by their uploaded G&L (2025/2026 only). When ScheduleFA.build is called for CY2024, `validate_cy_coverage` fails and returns `{:error, "G&L data missing for RSU sell dates: ..."}`.  
**Impact:** Tax Centre page for CY2024 would show an error state for these users despite readiness=ready. The LiveView likely handles `{:error, _}` gracefully (renders an error alert), but the readiness badge says "Ready" which is misleading.  
**Root cause in readiness:** `readiness_schedule_fa` blocks on `uncovered_cy1` only. If the user selects a prior year in the UI, they may hit an error.  
**Suggested fix (needs approval):** Either (a) make ScheduleFA.build return `{:ok, [], ["No G&L for CY2024"]}` with empty rows + warning instead of `{:error, ...}` for older unsupported years, or (b) show the year tabs as "Limited" when G&L is only partial.

### Issue FA-2 — All users: cost_basis_per_share nil for tranches not in Holdings (WARN)
**Severity:** Low (data gap, not a code bug)  
**Affected:** u2 (all rows), u3 (5/23), u4 (16/35 CY2024, 45/45 CY2025), u5 (12/12)  
**Cause:** `cost_basis_per_share` comes from the Holdings file (`cost_basis_broker` column). Tranches older than the Holdings file snapshot — or tranches for symbols not in Holdings — have no broker cost basis. The `initial_value_inr` (vest FMV × vest FX × qty) is populated correctly and used as the Schedule FA figure.  
**Note:** `initial_value_inr` is non-nil for all rows — the INR value displayed on Schedule FA is correct. The nil is only in the `cost_basis_per_share` helper field.  
**Impact:** Schedule FA can be generated, but cost-basis-per-share shown may show "—" for older lots.

---

## Sell Advisor

`SellAdvisorV2.advise(account, target)` tested for `{:shares, 10}` and `{:inr, 1_000_000}`.

| Account | Result | Notes |
|---------|--------|-------|
| u1 | `:no_current_price` ⚠ | Expected no lots; misleading error |
| u2 | `:no_sellable_lots` ⚠ | All shares sold per Holdings |
| u3 | 1 basket ✓ | Working correctly |
| u4 | 1 basket ✓ | Working correctly |
| u5 | `:no_sellable_lots` ⚠ | ADBE all sold; CRM not yet vested |

### Issue SA-1 — u2, u5: Sell Advisor returns :no_sellable_lots when readiness=ready (WARN)
**Severity:** Low (expected behavior, readiness label ambiguity)  
**Users:** u2, u5  
**Cause:**
- u2: Holdings file confirms 0 sellable shares (all sold). `sellable_qty = 0` for all VESTED rows. Readiness=ready because BH + Holdings are present, but nothing is actually sellable.
- u5: ADBE fully sold (BH). CRM RSU has 1 unvested grant (2025-07-22 grant, all tranches 2026+). `sellable_qty = nil` for all (future vests). Holdings for ADBE not uploaded.  
**Impact:** Sell Advisor page loads but shows "no lots to sell" banner — user experience is correct but readiness badge says "Ready" which implies there's something actionable.  
**Suggested note:** Not a bug. Readiness checks data availability, not actionability. Acceptable behavior.

### Issue SA-2 — u1: :no_current_price instead of :no_lots (WARN)
**Severity:** Low  
**Users:** u1 (fully sold, readiness=limited)  
**Cause:** `SellAdvisorV2.advise` fetches stock price before checking if there are sellable lots. For u1, Yahoo fails to return a price (network or no active position), and the `with` chain short-circuits at `validate_price_fx` before reaching `load_sellable_lots`. The error `:no_current_price` is shown instead of `:no_sellable_lots` or `:no_holdings`.  
**Impact:** Minor — u1 has `:limited` readiness so the Sell Advisor page would already show a "upload Holdings" prompt. The confusing error only surfaces if the API is called directly.  
**Suggested fix:** Reorder the `with` chain to check `load_sellable_lots` before fetching price/fx. Needs approval.

---

## Multi-Symbol (u5)

- Two BH files ingested cleanly (ADBE + CRM). ✓
- `dominant_symbol` set correctly on each ingestion. ✓
- Portfolio shows CRM RSU only (ADBE Holdings not uploaded — correct). ✓
- Capital Gains aggregates both symbols correctly (ADBE FY2025: 12 rows, all with prices). ✓
- Schedule FA CY2025 shows 12 rows across both symbols. ✓
- Sell Advisor: no lots (CRM unvested, ADBE sold) — correct. ✓

**No multi-symbol-specific bugs found.**

---

## Summary

| # | Issue | Severity | Feature | Users |
|---|-------|----------|---------|-------|
| FA-1 | Schedule FA CY2024 errors when readiness=ready | Medium | Schedule FA | u3, u5 |
| CG-1 | FY2024 rows have nil price (no 2024 G&L) | Low/Info | Capital Gains | u3, u5 |
| FA-2 | cost_basis_per_share nil for older tranches | Low/Info | Schedule FA | u2, u3, u4, u5 |
| SA-1 | :no_sellable_lots when readiness=ready | Low | Sell Advisor | u2, u5 |
| SA-2 | :no_current_price instead of :no_lots | Low | Sell Advisor | u1 |

**No crashes. No data corruption. No missing ESPP/RSU splits.**  
Core features (Portfolio, Capital Gains FY2025, Sell Advisor for active users) all working correctly.
