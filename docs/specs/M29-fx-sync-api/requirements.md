# Requirements: M29 — FX Sync API (Subscribers Only)

## Introduction

Expose **USD/INR monthly FX rates** from the cloud portal for sync into the desktop app's local SQLite. Rates follow Indian tax Rule 115 (SBI TT Buying Rate, previous-month lookup) — same semantics as `StockPlan.FX` in the desktop app.

**Locked decisions:**
- **Subscribers only** — valid trial or active paid subscription (M28 entitlements: `fx_sync: true`)
- **No user financial data** in requests or responses
- Desktop app syncs rates into local `stock_plan_fx_monthly_rates` (M30)

---

## Requirement 1: Authorization

1. ALL FX endpoints SHALL require `Authorization: Bearer <access_token>` from M28
2. THE system SHALL reject requests when `fx_sync` entitlement is false (HTTP **403**)
3. THE system SHALL reject expired or invalid tokens (HTTP **401**)
4. Unauthenticated access to FX endpoints is **not allowed** (no public FX API)

## Requirement 2: FX Master Data (Cloud)

1. THE portal SHALL maintain `portal_fx_monthly_rates` table with same semantic fields as desktop:

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT PK | |
| rate_date | date | Last day of month |
| year_month | TEXT | "2024-03" |
| currency_pair | TEXT | "USD/INR" |
| tt_buying_rate_month_end | decimal | Primary for tax |
| standard_rate_month_end | decimal | Fallback |
| standard_rate_month_avg | decimal | Fallback |
| source | TEXT | |
| inserted_at, updated_at | | |

2. THE portal SHALL seed historical rates from the same source as desktop (`priv/repo/fx_seed_data.exs` — copy or shared module)
3. THE portal SHALL support **monthly refresh** of new rates (operational task — admin script or cron)

## Requirement 3: Current Rate Endpoint (Optional Diagnostic)

```
GET /api/v1/fx/current
```

1. Returns most recent month rate — useful for admin/support diagnostics
2. Not required for desktop sync (desktop uses bulk monthly + local lookup)

## Requirement 4: Bulk Sync Endpoint (Primary Desktop Use Case)

```
GET /api/v1/fx/monthly?from=2024-01&to=2024-12
Authorization: Bearer <token>

→ 200 {
     "status": "ok",
     "data": {
       "currency_pair": "USD/INR",
       "rates": [
         {
           "year_month": "2024-01",
           "rate_date": "2024-01-31",
           "tt_buying_rate_month_end": "83.05",
           "standard_rate_month_end": "83.48",
           "standard_rate_month_avg": "83.12",
           "source": "sbi_tt_buy"
         }
       ],
       "sync_token": "2024-12",
       "server_time": "2026-06-11T12:00:00Z"
     }
   }
```

1. `from` and `to` SHALL be inclusive `YYYY-MM` strings
2. Maximum range per request: **120 months** (10 years)
3. THE desktop app SHALL call this on startup (if online + entitled) with `from` = last synced month, `to` = current month
4. Response includes all three rate fields so desktop upserts match local schema exactly
5. `sync_token` SHALL equal the `to` parameter of the request (highest `year_month` included in `rates`). Desktop SHALL persist this as `last_fx_sync_month` in `license.json` after successful upsert — same semantics as M30 FxSync

## Requirement 5: Sync Metadata Endpoint

```
GET /api/v1/fx/sync-status
Authorization: Bearer <token>

→ 200 {
     "status": "ok",
     "data": {
       "latest_year_month": "2026-05",
       "earliest_year_month": "1998-08",
       "total_months": 333,
       "last_updated_at": "2026-06-01T00:00:00Z"
     }
   }
```

1. Desktop uses this to decide if sync is needed without downloading full range

## Requirement 6: Rate Limiting

1. FX endpoints: **100 requests/hour** per user (bulk monthly counts as 1)
2. Return 429 with `Retry-After` header when exceeded

## Requirement 7: Response Format

1. All decimals as **strings** (no JSON floats)
2. Dates as ISO 8601 (`YYYY-MM-DD`)
3. Consistent envelope: `{ status, data }` or `{ status, message }`

## Requirement 8: Operational — Rate Updates

1. THE system SHALL provide admin task: `mix portal.fx.import` — import new monthly row from CSV or manual entry
2. THE system SHALL log each import with source and timestamp
3. Phase 1: manual monthly update. Phase 2: automated scrape from SBI/RBI sources (out of scope)

## Requirement 9: Disclaimer

1. API responses SHALL NOT include tax advice
2. Portal docs SHALL link FX methodology to [Indian Tax Rules](../../core/indian-tax-rules.md)
3. Desktop app SHALL show: "FX rates synced from Stock Plan service. Uses SBI TT Buying Rate where available."

---

## Out of Scope (M29)

- `GET /api/v1/fx/rate?date=` — **removed**; desktop performs previous-month lookup locally via `StockPlan.FX.get_rate/1`
- Public/unauthenticated FX API
- Real-time spot FX (only monthly tax rates)
- Non-USD currency pairs
- Storing which user synced which months (optional analytics later)

## Relationship to Desktop

- Desktop `StockPlan.FX.get_rate/1` logic unchanged — only **data source** gets fresher via sync
- Offline desktop: uses last synced local DB; bundled seed on first install if never synced
- Non-subscribers: bundled seed only, no API calls
