# Tasks: M30 — Desktop Client Licensing & FX Sync

## Prerequisites

- M28 auth API available (local or staging)
- M29 FX API available
- M19 Mac + Windows builds

---

## Milestone 1: License Store

**Files:** `lib/stock_plan/license/store.ex`

- [ ] 1.1 Read/write `~/.stock_plan/license.json`
- [ ] 1.2 Device ID generation and persistence
- [ ] 1.3 Windows icacls on license.json create
- [ ] 1.4 `clear/0` for sign out
- [ ] 1.5 Tests with temp directory override
- [ ] 1.6 `mix test` — pass

## Milestone 2: Portal Client

**File:** `lib/stock_plan/portal_client.ex`

- [ ] 2.1 HTTP client with Finch (reuse existing)
- [ ] 2.2 `login/2`, `activate/5`, `validate/4`, `refresh/1`
- [ ] 2.3 `fx_sync_status/1`, `fx_monthly/3`
- [ ] 2.4 Configurable base URL
- [ ] 2.5 Platform + app version headers/body
- [ ] 2.6 Mox-based tests
- [ ] 2.7 `mix test` — pass

## Milestone 3: License Context

**File:** `lib/stock_plan/license.ex`

- [ ] 3.1 `activated?/0`, `premium?/0`, `fx_sync_allowed?/0`
- [ ] 3.2 Offline grace logic (48 hours)
- [ ] 3.3 `validate_and_refresh/0` — refresh then validate; returns `{:ok, _}` | `{:error, _}`; never raises
- [ ] 3.4 `activate_with_password/2`, `activate_with_key/2`
- [ ] 3.5 `offline_grace_remaining/0`
- [ ] 3.6 Unit tests: grace boundary at 47h, 49h
- [ ] 3.7 `mix test` — pass

## Milestone 4: FX Sync

**File:** `lib/stock_plan/fx_sync.ex`

- [ ] 4.1 Upsert monthly rates from API response
- [ ] 4.2 Track `last_fx_sync_month` in license.json
- [ ] 4.3 Skip when not entitled
- [ ] 4.4 Non-fatal on network error
- [ ] 4.5 Tests with mocked PortalClient
- [ ] 4.6 `mix test` — pass

## Milestone 5: Application Bootstrap

**File:** `lib/stock_plan/application.ex`

- [ ] 5.1 Background task: validate + fx sync on startup
- [ ] 5.2 `skip_license` / `skip_portal` test config
- [ ] 5.3 Dev: default portal URL localhost:4003

## Milestone 6: Router & Plugs

**Files:** `require_license.ex`, `require_premium.ex`, `router.ex`

- [ ] 6.1 `/activate` route — no license required
- [ ] 6.2 `:require_license` on main app routes
- [ ] 6.3 `:require_premium` on `/sell` and export actions
- [ ] 6.4 Replace/adjust `check_profile` plug
- [ ] 6.5 Test env bypass

## Milestone 7: Activate LiveView

**File:** `lib/stock_plan_web/live/activate_live.ex`

- [ ] 7.1 Email + password form
- [ ] 7.2 Email + license key form
- [ ] 7.3 Error handling (network, invalid credentials)
- [ ] 7.4 Success → redirect to app
- [ ] 7.5 Link to portal register (opens browser)
- [ ] 7.6 Manual test Mac + Windows

## Milestone 8: Feature Gating UI

- [ ] 8.1 Tax Centre: disable exports when not premium
- [ ] 8.2 Sell Advisor: `/upgrade` paywall when not premium
- [ ] 8.3 UpgradeLive with billing link + grace status
- [ ] 8.4 Update-available banner (manifest check)
- [ ] 8.5 Settings: sign out clears license.json

## Milestone 9: Release Config

- [ ] 9.1 Embed production `portal_api_base` in release
- [ ] 9.2 Embed JWT public key (RS256 verify) in release
- [ ] 9.3 Document env override for staging
- [ ] 9.4 Verify Windows exe + Mac app both detect platform correctly

## Milestone 10: End-to-End Test

- [ ] 10.1 Register on portal → activate in desktop → premium unlocked
- [ ] 10.2 FX sync adds new month to local DB
- [ ] 10.3 Airplane mode 24h → premium works
- [ ] 10.4 Airplane mode 49h → exports blocked
- [ ] 10.5 Expired trial online → exports blocked, free features work

---

## Definition of Done

- Desktop app requires activation before use
- Premium features respect 48h offline grace
- FX sync only for trial/active subscribers
- No financial data sent to portal APIs
- Mac + Windows builds tested against staging portal
