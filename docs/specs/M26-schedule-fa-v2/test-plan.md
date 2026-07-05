# Test Plan: M26 — Schedule FA v2

## TP-1: Pre-check P1 — G&L coverage (unit)

Function: `check_gl_coverage_for_fa_year/3`. CY = 2025 (`cy_start = 2025-01-01`).
BH and G&L columns include RSU and ESPP sell dates.

| ID | BH sell dates (RSU + ESPP) | G&L dates | Expected |
|---|---|---|---|
| P1.1 | 2025-03-15 | 2025-03-15 | `:ok` |
| P1.2 | 2024-06-01, 2025-03-15 | 2025-03-15 only | `:ok` (pre-CY not required) |
| P1.3 | 2025-03-15, 2026-01-20 | 2025-03-15 only | `{:error, _}` mentions 2026-01-20 |
| P1.4 | none | any | `:ok` |
| P1.5 | 2025-03-15, 2025-06-01 | both | `:ok` |
| P1.6 | 2024-06-01 only | none | `:ok` |
| P1.7 | 2025-03-15 (ESPP only) | none | `{:error, _}` |

---

## TP-2: Pre-check P2 — Holdings (unit + fixture)

| ID | Scenario | Expected |
|---|---|---|
| P2.1 | Holdings uploaded | `:ok` |
| P2.2 | No Holdings, snapshot `vested_unsold=0, unvested=0` | `:ok` |
| P2.3 | No Holdings, `bh_sold == total_released` per origin | `:ok` |
| P2.4 | No Holdings, `bh_sold < total_released` on any origin | `{:error, _}` with grant numbers |
| P2.5 | User 1 fixture, BH only | `:ok` (P2) |

---

## TP-3: `compute_cy_state` — Rules 1–3 (unit)

### Rule 1 — vested in CY

| ID | Vested | CY sale | Start | End |
|---|---|---|---|---|
| R1.1 | 18 | 18 | 18 | 0 |
| R1.2 | 18 | 2 | 18 | 16 |
| R1.3 | 17 | 0 | 17 | 17 |
| R1.4 | 15 | 0 (beyond=15 in 2026) | 15 | 15 |

### Rule 2 — vested after CY

| ID | Vest date | Start | End | In FA? |
|---|---|---|---|---|
| R2.1 | 2026-01-15 | 0 | 0 | No |

### Rule 3 — vested before CY

| ID | Vested | CY sale | Beyond | Holdings | Start | End |
|---|---|---|---|---|---|---|
| R3.1 | 17 | 0 | 0 | 17 | 17 | 17 |
| R3.2 | 18 | 18 | 0 | 0 | 18 | 0 |
| R3.3 | 18 | 0 | 0 | 16 | 16 | 16 |
| R3.4 | 18 | 2 | 0 | 16 | 18 | 16 |
| R3.5 | 18 | 0 | 0 | 0 (BH sold) | 0 | 0 |
| R3.6 | 15 | 0 | 15 | 0 | 15 | 15 |

R3.3 is the partial-G&L bug case (formula gave 18/18).
R3.5 is SampleUser 1 RSU exclusion.

---

## TP-4: Exclusion

| ID | start_count | In FA output? |
|---|---|---|
| E1 | 0 | No |
| E2 | > 0, end=0 (sold in CY) | Yes |
| E3 | > 0, end>0 | Yes |

---

## TP-5: FA field values (integration, User 3 or synthetic)

| ID | Field | Assertion |
|---|---|---|
| F1 | `initial_value_inr` | `cost_basis × start_count × vest_fx` |
| F2 | `closing_value_inr` | `dec31 × end_count × fx`; 0 when end=0 |
| F3 | `sale_proceeds_inr` | CY G&L sells only; 0 when cy_sale=0 |
| F4 | Peak | Uses `start_count` as opening qty |

---

## TP-6: `ScheduleFA.build/2` integration

**File:** `test/stock_plan/tax/schedule_fa_test.exs`

| ID | Fixture | Year | Expected |
|---|---|---|---|
| I1 | User 1 BH only | 2024 | `{:error, _}` — P1 blocks (ESPP + RSU sells on/after 2024-01-01, no G&L) |
| I2 | User 1 BH only | 2024 | No RSU row with `quantity_held == net_quantity` for pre-CY sold tranches |
| I3 | User 1 BH + 2023+2024+2025 G&L | 2024 | `{:ok, rows, _}`, rows > 0, plausible counts |
| I4 | User 1 BH + 2025 G&L only | 2024 | `{:error, _}` (P1: 2025+ BH dates missing G&L when checking from cy_start=2024) |
| I5 | User 3 BH + Holdings + G&L | 2024 | `{:ok, _, _}`, Rule 3 holdings reflected |
| I6 | Empty account | 2024 | `{:ok, [], _}` |

---

## TP-ESPP: ESPP unified holdings (regression for User 2 bug)

Rule 3 for ESPP must use `holdings_qty` (not `net_quantity − SUM(sells)`). These cases
verify the unified path eliminates the phantom closing-row bug.

| ID | Scenario | holdings_qty | cy_sale | beyond | Expected start / end |
|---|---|---|---|---|---|
| TP-ESPP-1 | Pre-CY lot fully sold, not in Holdings, G&L present | 0 (P2-inferred) | 0 | 0 | 0/0 → excluded |
| TP-ESPP-2 | Pre-CY lot sold entirely in CY (G&L), end_count=0 | 0 | 10 | 0 | 10/0 → included with proceeds |
| TP-ESPP-3 | Pre-CY lot still held (in Holdings with sellable > 0) | 8 | 2 | 0 | 10/8 → included |
| TP-ESPP-4 | `vested_unsold_origin_count == 0`, no Holdings → all lots excluded | 0 (all) | 0 | 0 | 0/0 → no FA rows |

**Integration assertion (User 2):** Load User 2 BH + G&L, FA CY 2025. Assert no FA row has
`closing_value_inr > 0` and `sale_proceeds_inr == 0` for 2019/2020 ESPP lots that are fully
sold.

---

## TP-7: Upload readiness alignment

**File:** `test/stock_plan/ingestion/upload_checks_test.exs`

| ID | Fixture | `schedule_fa` readiness |
|---|---|---|
| U1 | User 1 BH only | `:blocked` if P1 fails for CY-1; `:ready` if P1 passes for CY-1 |
| U2 | User 3 full data | `:ready` |
| U3 | No BH | `:blocked` |

---

## TP-8: Manual browser (Tax Centre)

| ID | Steps | Expected |
|---|---|---|
| M1 | User 1, BH only, select FA 2024 | Error banner if P1 fails; no misleading rows |
| M2 | User 1, full G&L, FA 2024 | Table renders, CSV downloads |
| M3 | User 3, FA 2024 | Rows match Holdings-backed quantities |

---

## Test approach

- TP-1–TP-4: pure unit tests on `compute_cy_state` / pre-check helpers
- TP-5–TP-7: DataCase with sample XLSX fixtures
- TP-8: manual

**Target:** ~25 automated tests, 3 manual checks.
