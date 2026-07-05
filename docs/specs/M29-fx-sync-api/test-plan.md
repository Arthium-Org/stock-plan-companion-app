# Test Plan: M29 — FX Sync API (Subscribers Only)

---

## TP-1: FX Context (Automated)

**File:** `test/portal/fx_test.exs`

Port critical cases from `test/stock_plan/fx_test.exs`:

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | get_rate mid-month | Uses previous month year_month |
| TP-1.2 | pick_best_rate priority | tt_buying preferred |
| TP-1.3 | pick_best_rate fallback | standard_end when tt nil |
| TP-1.4 | current_rate | Returns latest year_month row |
| TP-1.5 | list_monthly range | Ordered ascending, inclusive |
| TP-1.6 | list_monthly > 120 months | Error |
| TP-1.7 | Missing month | nil / 404 at controller layer |

## TP-2: Authorization (Automated)

**File:** `test/portal_web/controllers/api/fx_controller_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | No Authorization header | 401 |
| TP-2.2 | Invalid token | 401 |
| TP-2.3 | Expired trial user | 403 all FX endpoints |
| TP-2.4 | Active trial user | 200 |
| TP-2.5 | Active paid user | 200 |

## TP-3: FX Endpoints (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | GET /fx/current | rate as string, year_month present |
| TP-3.2 | GET /fx/monthly?from=2024-01&to=2024-03 | 3 rates, all fields present |
| TP-3.3 | GET /fx/sync-status | latest_year_month, total_months > 0 |
| TP-3.4 | GET /fx/rate | **404 or not routed** — endpoint removed |
| TP-3.5 | Invalid from/to format | 422 |

## TP-4: Parity with Desktop (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | 10 random dates | Portal get_rate == desktop StockPlan.FX.get_rate (same seed) |
| TP-4.2 | current_rate | Matches desktop current_rate |

**Setup:** Run parity test in CI with both modules loaded, or export golden JSON from desktop.

## TP-5: Rate Limiting (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | 101 requests in hour | 429 on 101st |

## TP-6: Seed & Import (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | mix portal.fx.seed | Idempotent, no duplicates |
| TP-6.2 | mix portal.fx.import new month | Appears in /fx/current |
| TP-6.3 | Production seed count | ≥ 333 months |

## TP-7: Integration with M30 (Manual — after M30)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | Desktop startup sync | New months upserted locally |
| TP-7.2 | Schedule FA after sync | Uses synced rates |
| TP-7.3 | Expired user desktop | No FX API call, bundled seed used |
| TP-7.4 | Offline desktop | Uses last synced local rates |

## TP-8: Security (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.1 | curl without token | 401 |
| TP-8.2 | Public internet scan | FX endpoints not useful without auth |
| TP-8.3 | Response body | No user PII, no financial data |

---

## Golden Dates for Parity

Use these transaction dates for cross-check:

| Date | Expected year_month |
|------|---------------------|
| 2024-01-15 | 2023-12 |
| 2024-06-15 | 2024-05 |
| 2025-03-31 | 2025-02 |
| 2020-07-01 | 2020-06 |

Rates must match desktop seed exactly.
