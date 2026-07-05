# Requirements: M30 — Desktop Client Licensing & FX Sync

## Introduction

Integrate the **local desktop app** (Mac + Windows) with cloud auth (M28) and FX sync (M29). All financial data remains on the user's machine. Cloud communication is limited to: subscription validation, token refresh, and FX rate download.

**Locked decisions:**
- **Offline validation grace:** 48 hours
- **FX sync:** Subscribers only (trial + active)
- **Trial:** Time-limited (duration from M28 `PORTAL_TRIAL_DAYS`, default 14)
- **Platforms:** macOS + Windows (M19)

---

## Requirement 1: Local License Store

1. THE app SHALL persist license state at `~/.stock_plan/license.json` (Windows: `%USERPROFILE%\.stock_plan\license.json`)
2. THE file SHALL contain (no financial data):

```json
{
  "device_id": "uuid-v4",
  "email": "user@example.com",
  "access_token": "...",
  "refresh_token": "...",
  "license_key": "SPM-...",
  "last_validated_at": "2026-06-11T12:00:00Z",
  "cached_entitlements": {
    "premium_features": true,
    "fx_sync": true
  },
  "subscription_status": "trial",
  "trial_ends_at": "2026-06-25T00:00:00Z",
  "offline_grace_hours": 48,
  "last_fx_sync_month": "2026-05"
}
```

Note: **`portal_api_base` is NOT stored in license.json in production releases** — see Requirement 1a.

### Requirement 1a: Portal URL (Production Safety)

1. Production desktop builds SHALL use **compile-time** `portal_api_base` or `STOCK_PLAN_PORTAL_URL` env var only
2. Production builds SHALL **ignore** any `portal_api_base` field in license.json (prevents redirect to attacker-controlled server)
3. Dev/test MAY allow license.json override for local portal testing

## Requirement 1b: File Permissions

1. Unix: `license.json` mode **0600**
2. Windows: on create, run `icacls "%USERPROFILE%\.stock_plan\license.json" /inheritance:r /grant:r "%USERNAME%:F"`
3. Tokens and license keys SHALL NOT be logged

## Requirement 2: Device ID

1. ON first launch THE app SHALL generate `device_id` (UUID v4) if missing
2. THE device_id SHALL persist across app restarts
3. THE device_id SHALL be sent with validate/activate requests only

## Requirement 3: Activation Flow (First Launch)

1. IF no valid license.json THE app SHALL show **Activation screen** before upload/portfolio
2. THE activation screen SHALL offer:
   - **Email + password** (calls login API → save tokens)
   - **Email + license key** (calls activate API → save tokens)
   - Link to register on website (opens browser to portal `/account/register`)
3. ON successful activation THE app SHALL cache validation response and proceed to normal app flow
4. THE activation screen SHALL explain: account is for subscription only; files stay local

## Requirement 4: Validation on Startup

1. ON each app start THE app SHALL attempt online validation if network available
2. IF online validation succeeds THE app SHALL update `last_validated_at` and cached entitlements
3. IF online validation fails (network) THE app SHALL use **offline grace** logic (Requirement 5)
4. IF online validation fails (401 expired token) THE app SHALL attempt token refresh once
5. IF refresh fails THE app SHALL prompt re-activation (license key or login)

## Requirement 5: Offline Grace (48 Hours)

1. THE app SHALL allow premium features when:
   ```
   now - last_validated_at <= 48 hours
   AND cached_entitlements.premium_features == true
   ```
2. IF offline grace expired THE app SHALL block premium features until online validation succeeds
3. IF grace expired THE app SHALL show banner: "Connect to the internet to verify subscription"
4. Basic features (upload, portfolio view) MAY remain available when expired — configurable list in Requirement 7
5. `offline_grace_hours` from server response SHALL override local default if present (expected: 48)

### Requirement 5a: Clock Rollback (Known Limitation)

1. Offline grace uses **client system clock** — setting clock backward can extend grace indefinitely
2. **Accepted risk for Phase 1** at current audience scale; documented in privacy/terms
3. Mitigation deferred: compare `validated_at` server timestamp against monotonic reference or require online validate for exports after N days

## Requirement 6: FX Sync (Subscribers Only)

1. AFTER successful validation with `fx_sync: true` THE app SHALL sync FX rates from M29 API
2. Sync algorithm:
   - Call `GET /api/v1/fx/sync-status`
   - Call `GET /api/v1/fx/monthly?from={last_fx_sync_month}&to={latest}` (or full seed gap on first sync)
   - Upsert into local `stock_plan_fx_monthly_rates`
   - Update `last_fx_sync_month` in license.json
3. IF `fx_sync: false` THE app SHALL NOT call FX API; use bundled seed + existing local DB only
4. IF sync fails (network) THE app SHALL continue with existing local rates; show non-blocking warning
5. IF sync fails (403) THE app SHALL skip sync silently (expired subscription)

## Requirement 7: Feature Gating

### Premium features (require valid trial/active OR within 48h offline grace)

| Feature | Gate |
|---------|------|
| Schedule FA CSV export | Premium |
| Capital Gains CSV export | Premium |
| Schedule FSI export | Premium |
| Sell Advisor | Premium |
| FX sync from cloud | Premium + fx_sync entitlement |

### Always available (even expired subscription)

| Feature | Gate |
|---------|------|
| Upload Benefit History / G&L / Holdings | Free |
| Portfolio view | Free |
| Guide / local help links | Free |
| Tax Centre preview (read-only table) | Free — **exports gated** |

1. THE app SHALL show upgrade prompt when user attempts gated action without entitlement
2. Upgrade prompt SHALL link to portal `/pricing` in browser

## Requirement 8: Portal Client Module

1. THE app SHALL implement `StockPlan.PortalClient` HTTP client (Finch)
2. Configurable base URL via:
   - **Production:** compile-time default + `STOCK_PLAN_PORTAL_URL` env var only
   - **Dev:** `config :stock_plan, portal_api_base: "http://localhost:4003"`
3. Timeouts: connect 5s, receive 30s
4. TLS required in production (no http except localhost dev)

## Requirement 9: License Context Module

```elixir
StockPlan.License.validate_and_refresh()   # startup — returns {:ok, _} | {:error, _}; never raises
StockPlan.License.premium?()                 # gating check
StockPlan.License.fx_sync_allowed?()         # FX API check
StockPlan.License.activate_with_password/2
StockPlan.License.activate_with_key/2
StockPlan.License.offline_grace_remaining()  # Duration until block
```

1. `validate_and_refresh/0` SHALL refresh the access token if needed, then call validate — **returns `{:ok, license}` or `{:error, reason}`** (no raising). Startup runs this in a background Task; failures are non-fatal and logged.

## Requirement 10: UI Integration

1. **Activation LiveView** at `/activate` — shown when not licensed
2. **Account status** in nav/footer: trial days left, or "Subscribed", or "Expired"
3. **Settings section** (optional `/settings/account`): re-validate, sign out (clear license.json), view offline grace
4. Tax Centre export buttons: disabled + tooltip when not premium
5. Sell Advisor route: **PaywallLive** at `/upgrade` when not premium (upgrade CTA + link to portal `/account/billing`)
6. Expired trial banner with "Upgrade" → opens portal billing in browser

## Requirement 10a: Update Available Banner

1. ON startup (if online) THE app SHALL fetch `GET {portal}/download/manifest.json`
2. IF manifest `latest` > `Application.spec(:stock_plan, :vsn)` THE app SHALL show non-blocking banner: "Update available — download from website"
3. Banner links to portal `/download` in browser
4. Failure to fetch manifest is non-fatal

## Requirement 11: Router Changes

1. Add `:require_license` pipeline plug — allows app use if activated (even expired for free tier)
2. Add `:require_premium` plug for gated routes/actions
3. `/activate` excluded from license check
4. Remove or relax current `check_profile` redirect — profile setup after activation

## Requirement 12: Release Configuration

1. Desktop release SHALL embed default `portal_api_base` and JWT **public key** (RS256) at compile time
2. Dev mode: point to `http://localhost:4003`
3. App version sent in validate requests from `Application.spec(:stock_plan, :vsn)`

## Requirement 13: Test Bypass (Compile-Time Guard)

1. `skip_license: true` SHALL only be set inside `config/test.exs`
2. `application.ex` SHALL gate bypass: `if Mix.env() == :test and Application.get_env(:stock_plan, :skip_license)` — structurally impossible in `:prod` compile

---

## Out of Scope (M30)

- Uploading financial data to cloud
- Cloud backup / sync of portfolio
- In-app payment (user pays on website)
- Biometric lock for license store

## Dependencies

- M28 auth API operational
- M29 FX API operational
- M19 desktop builds for Mac + Windows
