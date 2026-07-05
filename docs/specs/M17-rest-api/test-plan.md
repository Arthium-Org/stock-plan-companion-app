# Test Plan: M17 — REST API

---

## TP-1: Auth (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Valid API key | 200 response |
| TP-1.2 | Invalid API key | 401 unauthorized |
| TP-1.3 | No auth header | 401 unauthorized |

## TP-2: Portfolio API (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | GET /api/portfolio | 200, has espp + rsu keys |
| TP-2.2 | GET /api/portfolio/summary | 200, has total_value |
| TP-2.3 | Decimals as strings | No float values in response |
| TP-2.4 | No data | 200, empty arrays |

## TP-3: Tax API (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | GET /api/tax/schedule-fa?year=2025 | 200, rows array |
| TP-3.2 | GET /api/tax/schedule-fa/download | 200, CSV content type |
| TP-3.3 | GET /api/tax/capital-gains?fy=2025 | 200, rows + summary |
| TP-3.4 | Invalid year | 400 error |

## TP-4: Sell Advisor API (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | POST /api/sell/advise {shares: 10} | 200, baskets array |
| TP-4.2 | POST /api/sell/advise {usd: 2500} | 200, baskets |
| TP-4.3 | POST /api/sell/advise {shares: 0} | 400 error |

## TP-5: Upload API (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | POST /api/upload/benefit-history | 200, ingestion summary |
| TP-5.2 | POST /api/upload/holdings | 200, holdings summary |
| TP-5.3 | Invalid file | 400 error |

## TP-6: CORS (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | OPTIONS preflight | Correct CORS headers |
| TP-6.2 | Cross-origin GET | Allowed |

---

## Test Count: ~20 (15 automated, 5 manual)
