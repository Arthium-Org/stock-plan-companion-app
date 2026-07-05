# Tasks: M28 — Cloud Auth & Subscription

## Prerequisites

- M27 portal app scaffold deployed (or local dev on 4003)
- Postgres instance for portal
- `PORTAL_JWT_PRIVATE_KEY` in prod env (RS256)

---

## Milestone 1: Database & Schemas

**Dir:** `portal/priv/repo/migrations/`, `portal/lib/portal/schema/`

- [ ] 1.1 Add Postgres adapter to portal app
- [ ] 1.2 Migration: `portal_users`
- [ ] 1.3 Migration: `portal_subscriptions`
- [ ] 1.4 Migration: `portal_refresh_tokens`
- [ ] 1.5 Migration: `portal_device_validations`
- [ ] 1.6 Ecto schemas with changesets
- [ ] 1.7 `mix ecto.migrate` — pass

## Milestone 2: User Registration & Login

**Files:** `portal/lib/portal/accounts.ex`, `portal/lib/portal/auth.ex`

- [ ] 2.1 `Accounts.register/1` — email, password, license key, trial subscription
- [ ] 2.2 Password hashing (bcrypt)
- [ ] 2.3 `Auth.login/2` — verify credentials, return token pair
- [ ] 2.4 RS256 JWT: generate/verify with RSA key pair; document public key embed for M30
- [ ] 2.5 `Auth.verify_access/1`
- [ ] 2.6 `Auth.refresh/1` — rotate refresh token
- [ ] 2.7 Write tests
- [ ] 2.8 `mix test` — pass

## Milestone 3: Auth API

**File:** `portal/lib/portal_web/controllers/api/auth_controller.ex`

- [ ] 3.1 `POST /api/v1/auth/register`
- [ ] 3.2 `POST /api/v1/auth/login`
- [ ] 3.3 `POST /api/v1/auth/refresh`
- [ ] 3.4 `POST /api/v1/auth/logout`
- [ ] 3.5 `POST /api/v1/auth/validate` — device limit (3/30d), rate limit user_id + IP
- [ ] 3.6 `POST /api/v1/auth/activate` — rate limit 10/hour/IP
- [ ] 3.7 API auth plug for protected routes
- [ ] 3.8 Rate limit plug
- [ ] 3.9 JSON error format
- [ ] 3.10 Write controller tests
- [ ] 3.11 `mix test` — pass

## Milestone 4: Subscription Logic

**File:** `portal/lib/portal/subscriptions.ex`

- [ ] 4.1 `subscription_status/2` state machine
- [ ] 4.2 `build_validation_response/2` with entitlements
- [ ] 4.3 Trial expiry check on validate
- [ ] 4.4 One trial per email enforcement
- [ ] 4.5 Configurable `PORTAL_TRIAL_DAYS` (default 14)
- [ ] 4.7 Device limit: 403 on 4th device in 30-day window
- [ ] 4.8 `mix test` — pass

## Milestone 5: Web Account UI

**Files:** `portal/lib/portal_web/live/account/*.ex`

- [ ] 5.1 RegisterLive — form, error handling, auto-login
- [ ] 5.2 LoginLive — session establishment
- [ ] 5.3 DashboardLive — status, trial countdown, license key copy
- [ ] 5.4 RequireAuth plug for account routes
- [ ] 5.5 Sign out
- [ ] 5.6 Manual browser test — full register → dashboard flow

## Milestone 6: Billing (M31 handoff)

- [ ] 6.1 Billing page UI — links to M31 checkout
- [ ] 6.2 Display subscription status from M31 webhook updates
- [ ] **Payment implementation:** see M31 tasks

## Milestone 7: Email (M32 handoff)

- [ ] 7.1 Configure Swoosh mailer (or Bamboo)
- [ ] 7.2 Password reset flow
- [ ] 7.3 Dev: mailbox preview / log token

## Milestone 8: Wire M27 Account Shell

- [ ] 8.1 Replace M27 placeholder dashboard with real data
- [ ] 8.2 Pricing page links to working register
- [ ] 8.3 Document API base URL for M30 desktop client config

---

## Definition of Done

- User can register on web, see trial status and license key
- Desktop can activate via API (test with curl / HTTP client)
- Validate returns correct entitlements for trial and expired states
- No financial data tables exist in portal DB
- Refresh token rotation works
