# Design: M28 — Cloud Auth & Subscription

## Architecture

```
Desktop App (M30)                    Portal (cloud)
      │                                    │
      │  POST /api/v1/auth/activate        │
      │  POST /api/v1/auth/validate         │
      │  POST /api/v1/auth/refresh         │
      ├───────────────────────────────────►│
      │                                    ├──► Postgres (portal_* tables)
      │◄───────────────────────────────────┤
      │  { subscription_status,             │
      │    entitlements, validated_at }     │
      │                                    │
      │  Cache in ~/.stock_plan/license.json
      │  48h offline grace (client-side)
```

Web users use session cookies on `/account/*`; desktop uses JWT Bearer tokens.

---

## Module Layout

```
portal/lib/portal/
├── accounts.ex              # User CRUD, registration
├── auth.ex                  # JWT issue/verify, refresh rotation
├── subscriptions.ex         # Trial + paid status logic
└── schema/
    ├── user.ex
    ├── subscription.ex
    ├── refresh_token.ex
    └── device_validation.ex

portal/lib/portal_web/
├── api/
│   └── auth_controller.ex   # /api/v1/auth/*
├── plugs/
│   ├── api_auth.ex          # Bearer JWT verification
│   └── rate_limit.ex
└── live/account/
    ├── register_live.ex
    ├── login_live.ex
    ├── dashboard_live.ex
    └── billing_live.ex
```

---

## Subscription State Machine

```elixir
def subscription_status(subscription, now \\ DateTime.utc_now()) do
  cond do
    subscription.status == "cancelled" and past?(subscription.subscription_ends_at, now) ->
      :cancelled

    subscription.status == "active" and not past?(subscription.subscription_ends_at, now) ->
      :active

    subscription.plan == "trial" and not past?(subscription.trial_ends_at, now) ->
      :trial

    true ->
      :expired
  end
end
```

On register:
1. Insert user with generated `license_key`
2. Insert subscription: `status: trial`, `plan: trial`, `trial_ends_at: now + PORTAL_TRIAL_DAYS`

---

## JWT Flow (RS256)

```elixir
defmodule Portal.Auth do
  @access_ttl 15 * 60
  @refresh_ttl 30 * 24 * 60 * 60

  # Sign with RSA private key (portal only, env PORTAL_JWT_PRIVATE_KEY)
  # Desktop embeds public key at compile time for verify-only
  def generate_token_pair(user_id)
  def verify_access(token)
  def refresh(refresh_token)
end
```

Refresh token stored hashed in DB. Raw token returned once to client.

---

## Validate Response Builder

```elixir
defmodule Portal.Subscriptions do
  def build_validation_response(user, subscription) do
    status = subscription_status(subscription)
    premium? = status in [:trial, :active]

    %{
      subscription_status: to_string(status),
      plan: subscription.plan,
      trial_ends_at: subscription.trial_ends_at,
      subscription_ends_at: subscription.subscription_ends_at,
      validated_at: DateTime.utc_now(),
      offline_grace_hours: 48,
      entitlements: %{
        premium_features: premium?,
        fx_sync: premium?
      }
    }
  end
end
```

---

## License Key Generation

```elixir
def generate_license_key do
  # SPM-XXXX-XXXX-XXXX — 12 hex chars (4 per group), 6 random bytes
  raw = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :upper)
  <<a::binary-size(4), b::binary-size(4), c::binary-size(4)>> = raw
  "SPM-#{a}-#{b}-#{c}"
end
```

---

## Device ID

Desktop app generates once on first launch, stores in `~/.stock_plan/device_id` (UUID v4). Sent with validate/activate for audit only.

---

## Device Limit

Count distinct `device_id` for user in last 30 days. If ≥ 3 and new device_id not in set → 403.

Phase 1b: `portal_revoked_devices` table for dashboard revoke.

---

## Payment Integration

See **M31 — Payments**. M28 billing page links to M31 checkout; webhook activates subscription.

---

## Web Session vs API Token

| Client | Auth mechanism |
|--------|----------------|
| Browser `/account` | Phoenix session cookie after login |
| Desktop app | JWT access + refresh in `~/.stock_plan/license.json` |

Web dashboard and desktop share same user record. User can copy license key from web if desktop token expired offline > 48h.

---

## Config

```elixir
# config/runtime.exs (portal)
config :portal,
  trial_days: String.to_integer(System.get_env("PORTAL_TRIAL_DAYS") || "14"),
  jwt_private_key_pem: System.get_env("PORTAL_JWT_PRIVATE_KEY"),
  max_active_devices: 3,
  offline_grace_hours: 48
```

---

## Database

Postgres via **postgrex** + **ecto_sql**. **Not SQLite** — cloud portal only.

Migrations in `portal/priv/repo/migrations/`.

Desktop app SQLite schema unchanged.

---

## API Error Format

Consistent with M17 shape:

```json
{ "status": "error", "message": "Invalid credentials" }
```

HTTP codes: 401 unauthorized, 403 expired subscription (validate still returns 200 with expired status — desktop decides UX), 422 validation errors, 429 rate limited.

**Note:** Validate returns **200** even when expired — body contains `subscription_status: expired`. Desktop uses entitlements flags. Avoid 403 on validate so client can refresh tokens independently.

---

## Security Notes

- Never log raw refresh tokens or license keys
- `device_validations` retained 90 days then purge (cron job)
- bcrypt cost factor 12
