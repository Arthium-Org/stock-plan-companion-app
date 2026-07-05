# Design: M29 — FX Sync API (Subscribers Only)

## Architecture

```
Desktop App (M30)                         Portal (cloud)
      │                                         │
      │  GET /api/v1/fx/sync-status             │
      │  GET /api/v1/fx/monthly?from=&to=       │
      ├────────────────────────────────────────►│
      │         Bearer JWT (M28)                │
      │         + fx_sync entitlement check     │
      │                                         ├──► portal_fx_monthly_rates (Postgres)
      │◄────────────────────────────────────────┤
      │         { rates: [...] }                │
      │                                         │
      ▼
 Upsert into local stock_plan_fx_monthly_rates (SQLite)
      │
      ▼
 StockPlan.FX.get_rate/1  (unchanged lookup logic)
```

---

## Module Layout

```
portal/lib/portal/
├── fx.ex                    # Rate lookup (mirror StockPlan.FX semantics)
├── fx/import.ex             # Admin import task
└── schema/
    └── fx_monthly_rate.ex

portal/lib/portal_web/
├── controllers/api/
│   └── fx_controller.ex
└── plugs/
    └── require_fx_entitlement.ex
```

---

## Entitlement Plug

```elixir
defmodule PortalWeb.Plugs.RequireFxEntitlement do
  def call(conn, _opts) do
    user = conn.assigns.current_user
    subscription = Portal.Subscriptions.get_for_user(user.id)

    if Portal.Subscriptions.fx_sync_allowed?(subscription) do
      conn
    else
      conn
      |> put_status(403)
      |> json(%{status: "error", message: "FX sync requires an active subscription or trial"})
      |> halt()
    end
  end
end
```

Chain: `ApiAuth` → `RequireFxEntitlement` → `FxController`

---

## Rate Lookup (Shared Semantics)

Port logic from `lib/stock_plan/fx.ex`:

```elixir
defmodule Portal.FX do
  def get_rate(%Date{} = date)
  def current_rate()
  def list_monthly(from_ym, to_ym)
  def sync_status()

  defp previous_month_key(date)
  defp pick_best_rate(rate_row)
end
```

**Option:** Extract shared pure functions to a small `fx_rules` module copied into both apps to avoid umbrella complexity in Phase 1. Document: keep in sync when tax rules change.

---

## Bulk Sync Query

```elixir
def list_monthly(from_ym, to_ym) do
  from(r in FxMonthlyRate,
    where: r.currency_pair == "USD/INR",
    where: r.year_month >= ^from_ym and r.year_month <= ^to_ym,
    order_by: [asc: r.year_month]
  )
  |> Repo.all()
end
```

Validate `from_ym <= to_ym` and month span ≤ 120.

Response includes `sync_token: to_ym` — desktop stores as `last_fx_sync_month`.

---

## Seed Strategy

1. Copy `priv/repo/fx_seed_data.exs` to portal (or symlink)
2. `mix portal.fx.seed` — idempotent upsert on `year_month`
3. CI: verify portal seed count matches desktop seed count

---

## Admin Import

```bash
mix portal.fx.import --year-month 2026-06 \
  --tt-buying 84.59 \
  --standard-end 85.02 \
  --source manual
```

Logs to `portal_fx_import_log` (optional simple table) or application logs.

---

## Router

```elixir
scope "/api/v1/fx", PortalWeb.API do
  pipe_through [:api, :api_auth, :require_fx_entitlement]

  get "/current", FxController, :current
  get "/monthly", FxController, :monthly
  get "/sync-status", FxController, :sync_status
end
```

No `GET /rate` — point-in-time lookup is local-only on desktop.

---

## Desktop Sync Algorithm (M30 reference)

```elixir
# Pseudocode — implemented in M30
def sync_fx_rates do
  with {:ok, tokens} <- License.ensure_valid_token(),
       {:ok, status} <- PortalClient.fx_sync_status(tokens),
       last = License.last_fx_sync_month() do
    from = last || status.earliest_year_month
    PortalClient.fx_monthly(tokens, from, status.latest_year_month)
    |> FX.upsert_monthly_rates()
    License.set_last_fx_sync_month(status.latest_year_month)
  end
end
```

Called after successful validate on app startup when online.

---

## Error Responses

| Code | Condition |
|------|-----------|
| 401 | Missing/invalid token |
| 403 | Valid token, fx_sync false |
| 404 | Rate not found for date |
| 422 | Invalid from/to params |
| 429 | Rate limited |

---

## Config

```elixir
config :portal, :fx_max_month_range, 120
config :portal, :fx_rate_limit_per_hour, 100
```
