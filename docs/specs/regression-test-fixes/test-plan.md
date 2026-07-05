# Test Plan — Regression Test Fixes

## T1 — Schedule FA: no error when G&L missing for requested year (FA-1)

**Setup:** u3 account — BH + Holdings + G&L 2025/2026 uploaded. No 2024 G&L.

```
ScheduleFA.build("u3", 2024)
→ {:ok, rows, [warning]}                      # not {:error, _}
→ warning contains "2024" and the uncovered sale dates
→ rows may be empty or contain tranches held in 2024 with no sale gap issue
→ warning is a non-empty string
```

```
ScheduleFA.build("u3", 2025)
→ {:ok, rows, warnings}                       # unchanged — 2025 G&L present
→ rows non-empty
→ no warning about G&L missing
```

**Setup:** u5 account — BH ADBE+CRM + Holdings CRM + G&L. No 2024 G&L.

```
ScheduleFA.build("u5", 2024)
→ {:ok, rows, [warning]}                      # not {:error, _}
→ warning mentions uncovered 2024 RSU sale dates
```

---

## T2 — Capital Gains: empty result with warning when no G&L for FY (CG-1)

**Setup:** u1 — BH only, no G&L.

```
CapitalGains.build("u1", 2024)
→ {[], summary}
→ summary.warning is non-nil and lists uncovered sale dates
→ summary.stcg_inr == 0, summary.ltcg_inr == 0
→ no rows with :unknown gain_type
```

```
CapitalGains.build("u1", 2025)
→ {[], summary}
→ summary.warning non-nil (still no G&L)
```

**Setup:** u3 — G&L 2025/2026 only.

```
CapitalGains.build("u3", 2024)
→ {[], summary}
→ summary.warning lists the 4 uncovered 2024 sale dates

CapitalGains.build("u3", 2025)
→ {rows, summary}                             # unchanged — G&L 2025 present
→ rows non-empty, nil_price = 0
→ summary.warning == nil
```

**Setup:** u2 — G&L 2025/2026 (6 FY2024 rows with G&L coverage).

```
CapitalGains.build("u2", 2024)
→ {rows, summary}                             # rows present, G&L covers these
→ summary.warning == nil
→ no regression
```

---

## T3 — Sell Advisor: no_sellable_lots for user with no Holdings (SA-2)

**Setup:** u1 — BH only, no Holdings.

```
SellAdvisorV2.advise("u1", {:shares, 10})
→ {:error, :no_sellable_lots}                 # was {:error, :no_current_price}
→ No Yahoo price fetch in logs
```

```
SellAdvisorV2.advise("u1", {:inr, 1_000_000})
→ {:error, :no_sellable_lots}
```

**Setup:** u3 — active holder with sellable lots.

```
SellAdvisorV2.advise("u3", {:shares, 10})
→ {:ok, advice}
→ advice[:baskets] non-empty
→ No regression
```

**Setup:** u2 — Holdings present but all sold (sellable_qty = 0).

```
SellAdvisorV2.advise("u2", {:shares, 10})
→ {:error, :no_sellable_lots}                 # same as before — no regression
```

---

---

## T4 — Cursor-feedback corrections (D.2, U.1, U.2, U.3, FA-1 filter)

### D.2 — Coverage check requires `sale_price IS NOT NULL`

```
CapitalGains.build(account_with_gl_but_nil_sale_price, fy)
→ sale classified as uncovered even though allocation row exists
→ warning lists that sale date
→ covered_sales excludes that sale
```

```
CapitalGains.build(account_with_valid_gl, fy)
→ all sales with a.sale_price != nil are covered
→ no regression — same result as before for properly ingested G&L
```

### U.1 — FA warnings appear even when FA rows are empty

```
Tax Centre LiveView — FA tab with G&L missing for requested CY:
→ Warning banner appears above the FA table/empty state
→ Banner text contains the uncovered sale dates
→ "Upload G&L" link is present in the banner
```

```
Tax Centre LiveView — FA tab with valid G&L (no warnings):
→ No warning banner rendered
→ FA rows table renders normally
```

### U.2 — Empty FA state doesn't show contradictory copy when warnings present

```
Tax Centre LiveView — @fa_data == [] AND @fa_warnings != []:
→ Warning banner renders (U.1)
→ "No Schedule FA data" / "Upload G&L" copy does NOT render (would contradict warning)
```

### U.3 — Dead unknown_count banner removed

```
Tax Centre LiveView — CG tab with no G&L (all uncovered sales):
→ No "X rows with unknown cost basis" banner appears
→ CG warning from summary.warning renders instead
```

### FA-1 filter — Both-zero rows excluded from error-arm output

```
ScheduleFA.build(account_with_cy_sells_but_no_gl, cy)
→ {:ok, rows, [warning]}
→ no row in rows has closing_value_inr == 0 AND sale_proceeds_inr == 0
→ rows contains only tranches still held at year end (closing_value > 0)
```

---

## T5 — Full regression pass

Run `mix test --max-cases 1` and verify:
- All tests pass.
- Pre-existing known gap: 3 `ScheduleFATest` cross-validation tests (`T190`, `T206`, `T225`) fail with `fa_total = 0` / `gl_total = 0` due to sample data not having CY 2024 G&L allocations with `sale_price`. These are **out of scope** for this fix.
- No new failures in `tax/capital_gains_test.exs`, `tax/tranche_timeline_test.exs`, or `sell_advisor_test.exs`.

Re-run the 5-user feature test script and confirm the issue summary contains only SA-1 and CG-1-partial (u2 FY2024 nil rows which are expected data gaps from before G&L was uploaded) — not the three issues fixed here.
