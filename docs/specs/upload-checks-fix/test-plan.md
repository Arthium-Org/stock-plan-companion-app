# Test Plan: Upload Checks Redesign (BH Metadata)

## Fixtures used

| Alias | Files | State |
|---|---|---|
| User 1 | BH only (ADBE/ESPP, all sold) | Fully sold, no Holdings, no G&L |
| User 1 + G&L | User 1 + G&L 2025 | Sales covered |
| User 1 + Holdings | User 1 + Holdings | Holdings uploaded (but all sold — still empty portfolio) |
| User 3 | BH + Holdings + G&L 2025 + G&L 2026 | Full data, active holdings |
| User 5 (ADBE) | ADBE BH only (all sold) | Fully sold symbol |
| User 5 (CRM) | CRM BH + CRM Holdings | Active holdings |
| User 5 (both) | ADBE BH + CRM BH + CRM Holdings | Mixed: one sold, one active |

---

## T1 — BH snapshot populated after ingest

```
setup: ingest_benefit_history(account, bh_file_1)
assert: ingestion.bh_snapshot_json != nil
assert: snapshot["vested_unsold_origin_count"] is integer >= 0
assert: snapshot["unvested_count"] is integer >= 0
assert: snapshot["sale_years"] is list of integers (sorted)
```

```
User 1 (all ESPP sold):
  assert snapshot["vested_unsold_origin_count"] == 0
  assert snapshot["unvested_count"] == 0
  assert snapshot["sale_years"] includes year(s) of ESPP sell events in BH

User 3:
  assert snapshot["vested_unsold_origin_count"] > 0   # has unsold RSU origins
  assert snapshot["unvested_count"] > 0         # has future vests
  assert snapshot["sale_years"] includes sale years from BH
```

---

## T2 — Upload checks: empty account

```
UploadChecks.check("empty")
→ nudges: [{code: :no_benefit_history, severity: :error}]
→ readiness.portfolio == :blocked
→ readiness.capital_gains == :blocked
→ readiness.schedule_fa == :blocked
```

---

## T3 — Upload checks: BH only, fully sold (User 1)

BH has ESPP sales on dates in 2023–2025; all sold; no Holdings; no G&L.

```
→ no :no_benefit_history nudge
→ no :no_holdings nudge  (current shares == 0 per BH snapshot, Holdings not required)
→ nudge :no_gl_for_dates fires (severity :warning) for uncovered CY-1 (2025) sale dates
  — action message names the specific date range from BH
→ nudge :no_gl_for_dates fires (severity :info) for CY (2026) IF BH has 2026 sales
→ no global :no_gl nudge (removed)
→ no nudges for 2023/2024 (outside relevant window)
→ readiness.portfolio == :not_applicable  (no current shares, nothing to show)
→ readiness.capital_gains == :blocked    (2025 sales with no GL coverage)
→ readiness.schedule_fa == :blocked      (same reason)
→ readiness.vesting_schedule == :ready   (BH exists)
```

---

## T4 — Upload checks: BH only, no sales (hypothetical: unvested only)

BH has unvested tranches; no SELL events in BH.

```
→ no :no_gl nudges of any kind
→ readiness.capital_gains == :ready   (no sales → nothing to compute)
→ readiness.schedule_fa == :ready     (no sales in CY-1 → not blocked)
→ readiness.portfolio == :blocked     (current shares exist, Holdings mandatory)
→ nudge :no_holdings fires, severity :error
```

---

## T5 — Upload checks: BH + Holdings, fully sold (User 1 + Holdings)

Holdings uploaded but BH shows all sold.

```
→ no :no_holdings nudge
→ readiness.portfolio == :not_applicable  (no current shares — nothing to show even with Holdings)
→ capital_gains / schedule_fa still blocked if 2025 has sales and no G&L
```

---

## T6 — Upload checks: BH with current shares, no Holdings

BH shows vested_unsold > 0 OR unvested > 0; no Holdings uploaded.

```
→ nudge :no_holdings fires, severity :error
→ readiness.portfolio == :blocked
→ sell_advisor readiness == :blocked  (or :limited — verify spec intent)
```

---

## T7 — Upload checks: BH + Holdings, no G&L (User 3 without G&L files)

Active holdings present; no G&L for any year.

```
→ no :no_holdings nudge
→ readiness.portfolio == :ready
→ nudge :no_gl_for_dates fires (severity :warning) for 2025 (CY-1) if User 3 BH has 2025 sales
→ readiness.capital_gains == :blocked
→ readiness.schedule_fa == :blocked or :limited (Holdings present → :limited if no CY-1 gap)
```

---

## T8 — Upload checks: full data (User 3)

BH + Holdings + G&L 2025 + G&L 2026.

```
→ no nudges with severity :error or :warning
→ readiness.portfolio == :ready
→ readiness.capital_gains == :ready
→ readiness.schedule_fa == :ready
→ readiness.schedule_fsi == :ready
→ readiness.sell_advisor == :ready
```

---

## T9 — Date-based nudge: CY-1 sales uncovered, CY partially covered

BH has sales on 2025-03-15 and 2026-04-20.
G&L uploaded covering only 2026-01-01 to 2026-12-31 (2025 still uncovered).

```
→ nudge :no_gl_for_dates fires for 2025 (severity :warning)
  reason includes "2025-03-15" as the uncovered date
→ no :no_gl_for_dates nudge for 2026 (covered by uploaded G&L)
→ readiness.capital_gains == :blocked (CY-1 = 2025 uncovered)
→ no nudge for 2024 or earlier
```

---

## T10 — Date-based nudge: only pre-CY-1 sales (no relevant window)

BH has sales only on 2022-06-10 and 2023-09-20 (no 2025 or 2026 sales).

```
→ no :no_gl_for_dates nudges (all sales older than CY-1 start)
→ readiness.capital_gains == :ready
→ readiness.schedule_fa == :ready
```

---

## T11 — Portfolio page state: Holdings required

Account: BH with vested_unsold_origin_count > 0, no Holdings file.

```
portfolio_state == :holdings_required
Page shows: "Upload a Holdings (ByBenefitType) file to view your portfolio"
No ESPP/RSU table rendered
```

---

## T12 — Portfolio page state: all sold

Account: BH with vested_unsold_origin_count == 0 and unvested_count == 0 (all origins fully sold, no future vests).

```
portfolio_state == :all_sold
Page shows: "All positions appear to be sold — see History"
No ESPP/RSU table rendered
```

---

## T13 — Portfolio page state: active

Account: BH with current shares + Holdings uploaded.

```
portfolio_state == :active
Normal portfolio table renders
No state banner shown
```

---

## T14 — Portfolio page state: no data

Empty account (no ingestions at all).

```
portfolio_state == :no_data
Page shows: "Upload a Benefit History file to get started"
```

---

## T15 — bh_has_current_shares? helper

```
After ingest_benefit_history(account, bh_file_1):   # User 1, all sold
  Ingestions.bh_has_current_shares?(account) == false

After ingest_benefit_history(account, bh_file_3):   # User 3, active
  Ingestions.bh_has_current_shares?(account) == true
```

---

## T16 — Symbol consistency nudge uses snapshot (no live query)

User 5: ADBE BH (fully sold) + CRM BH + CRM Holdings.

```
→ :bh_without_holdings nudge for ADBE NOT fired  (ADBE snapshot shows 0 unsold → sold out)
→ :bh_without_holdings nudge for CRM NOT fired  (CRM has Holdings)
→ no :holdings_without_bh nudge
```

(Regression: before fix, ADBE would incorrectly fire bh_without_holdings.)

---

## T18 — ESPP Phase 1: no allocation created, sale_price nil (R5)

After BH-only ingest for an ESPP account with sell events (User 1):

```
→ Sale records exist (one per ESPP sell event): sale.sale_date set, sale.total_quantity set
→ sale.sale_price == nil  (no Yahoo proxy)
→ sale.proceeds == nil
→ NO SaleAllocation records exist in the DB before G&L is uploaded
→ compute_gl_coverage_gaps: ESPP sale dates in CY-1 have no allocation → uncovered
→ :no_gl_for_dates nudge fires with :warning for CY-1 ESPP sale dates
  (regression: was suppressed before this fix — Yahoo price looked like GL coverage)
```

After G&L upload:

```
→ SaleAllocation records created with confirmed proceeds_per_share (sale_price NOT NULL)
→ compute_gl_coverage_gaps: those sale dates now covered
→ :no_gl_for_dates nudge clears for the covered dates
```

---

## T17 — Legacy BH ingestion (snapshot null after migration)

Account has an ACTIVE BH ingestion with `bh_snapshot_json = null` (pre-migration upload).

```
→ nudge :bh_snapshot_missing fires, severity :info
  reason: "Re-upload your Benefit History to unlock accurate readiness checks"
→ no :no_holdings nudge (cannot evaluate — no snapshot)
→ no :no_gl_for_dates nudge (no sale_years to check)
→ readiness.portfolio == :blocked   (BH present but share state unknown; :limited removed for Portfolio)
→ readiness.vesting_schedule == :ready  (BH record exists)
→ readiness.capital_gains == :blocked   (no snapshot, cannot confirm coverage)
```

---

## Regression: existing test suite

After all tasks complete:

```
mix test --max-cases 1
→ 0 failures
```

Key regressions to watch:
- `upload_checks_test.exs` — all cases updated per T2–T10
- `portfolio_test.exs` — BH fallback tests removed or updated
- `multi_symbol_test.exs` — User 5 symbol consistency (T16)
- `silver_builder_test.exs` — snapshot populated correctly (T1)
