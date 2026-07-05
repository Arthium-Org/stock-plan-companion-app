# Requirements: M17 — REST API

## Introduction

Expose existing business logic as a JSON REST API for mobile app consumption. All logic already exists in context modules — API is a thin layer.

---

## Requirement 1: Authentication

1. Phase 1: API key-based auth (single tenant, simple)
2. API key passed in header: `Authorization: Bearer <key>`
3. Key configured via environment variable
4. Future: OAuth2 / JWT for multi-user

## Requirement 2: Portfolio Endpoints

```
GET /api/portfolio
  → { espp: [origin_groups], rsu: [origin_groups] }

GET /api/portfolio/summary
  → { total_value, current_value, potential_value, by_plan_type }
```

Data from: `Portfolio.build/1` + `Portfolio.compute_summary/2`

## Requirement 3: Tax Centre Endpoints

```
GET /api/tax/schedule-fa?year=2025
  → { rows: [fa_row], csv_url: "/api/tax/schedule-fa/download?year=2025" }

GET /api/tax/schedule-fa/download?year=2025
  → CSV file download

GET /api/tax/capital-gains?fy=2025
  → { rows: [cg_row], summary: { stcg_inr, ltcg_inr, net_inr } }
```

Data from: `ScheduleFA.build/2`, `CapitalGains.build/2`

## Requirement 4: Sell Advisor Endpoints

```
POST /api/sell/advise
  body: { mode: "shares", amount: 30 }
  → { baskets: [basket], fy_baseline, current_price, current_fx }
```

Data from: `SellAdvisorV2.advise/3`

## Requirement 5: Market Data Endpoints

```
GET /api/price/current
  → { symbol: "ADBE", price: "250.17", fx_rate: "84.59" }
```

## Requirement 6: Upload Endpoints

```
POST /api/upload/benefit-history
  → multipart file upload

POST /api/upload/gl-expanded
  → multipart file upload

POST /api/upload/holdings
  → multipart file upload
```

## Requirement 7: Response Format

1. All responses: `{ status: "ok", data: ... }` or `{ status: "error", message: "..." }`
2. Dates: ISO 8601 strings
3. Decimals: string representation (avoid float precision loss)
4. INR amounts: computed server-side using current FX

## Requirement 8: CORS

1. Allow cross-origin requests (mobile app runs on different origin)
2. Configurable allowed origins

## Out of Scope (Phase 1)

- WebSocket/real-time updates
- Pagination (data sets are small)
- Rate limiting
- API versioning (/api/v1/)
