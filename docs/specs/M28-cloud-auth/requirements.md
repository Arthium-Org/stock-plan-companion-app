# Requirements: M28 — Cloud Auth & Subscription

## Introduction

Provide **identity and subscription management** for the cloud portal (M27). The desktop app (M30) validates subscription status online; **no user financial data** is stored or transmitted to the cloud.

**Locked decisions:**
- **Trial:** Time-limited full access (exact duration configurable; default **14 days** until product decision)
- **Offline validation grace:** **48 hours** after last successful online validation
- **FX API:** Subscribers only (enforced in M29; entitlement set here)
- **Platforms:** macOS + Windows desktop (M19/M30)

---

## Requirement 1: User Accounts

1. THE system SHALL allow registration with **email + password**
2. THE system SHALL hash passwords with bcrypt (via `phx.gen.auth` or equivalent)
3. THE system SHALL enforce unique email addresses
4. THE system SHALL support password reset via email (Phase 1: reset token + mailer; dev: log token)
5. THE system SHALL NOT collect: name (optional), brokerage credentials, tax data, or file uploads
6. OAuth (Google) is **out of scope** for Phase 1

## Requirement 2: Authentication API

All endpoints under `/api/v1/auth`. JSON request/response.

### Register

```
POST /api/v1/auth/register
Body: { "email": "...", "password": "..." }
→ 201 { "status": "ok", "data": { "user_id": "...", "access_token": "...", "refresh_token": "..." } }
```

1. On successful registration THE system SHALL start a **trial subscription** automatically
2. THE system SHALL return JWT access token (short-lived) and refresh token (long-lived)

### Login

```
POST /api/v1/auth/login
Body: { "email": "...", "password": "..." }
→ 200 { "status": "ok", "data": { "access_token": "...", "refresh_token": "..." } }
```

### Refresh

```
POST /api/v1/auth/refresh
Body: { "refresh_token": "..." }
→ 200 { "status": "ok", "data": { "access_token": "...", "refresh_token": "..." } }
```

1. Refresh tokens SHALL rotate on use (old token invalidated)

### Validate (desktop app primary endpoint)

```
POST /api/v1/auth/validate
Header: Authorization: Bearer <access_token>
Body: { "device_id": "...", "app_version": "1.5.0", "platform": "windows_x86_64" }
→ 200 {
     "status": "ok",
     "data": {
       "subscription_status": "trial" | "active" | "expired" | "cancelled",
       "plan": "trial" | "individual",
       "trial_ends_at": "2026-06-25T00:00:00Z",
       "subscription_ends_at": null,
       "validated_at": "2026-06-11T12:00:00Z",
       "offline_grace_hours": 48,
       "entitlements": {
         "premium_features": true,
         "fx_sync": true
       }
     }
   }
```

1. THE validate endpoint SHALL be callable by the desktop app on startup and periodically
2. THE system SHALL record `device_id` + `platform` + `app_version` on each validation (audit only)
3. THE system SHALL enforce **3 active devices per subscription** (see Requirement 8a)
4. Rate limits on validate: **60/hour per user_id** + **60/hour per IP** (not per device_id)

### Logout

```
POST /api/v1/auth/logout
Body: { "refresh_token": "..." }
→ 200 { "status": "ok" }
```

## Requirement 3: Subscription States

| Status | Meaning | Premium features | FX sync |
|--------|---------|------------------|---------|
| `trial` | Within trial window | Yes | Yes |
| `active` | Paid subscription current | Yes | Yes |
| `expired` | Trial ended, no payment | No | No |
| `cancelled` | User cancelled; period ended | No | No |
| `grace` | (local only) Offline within 48h of last validate | Yes* | Yes* |

*Grace is computed **client-side** (M30) using cached validation + `offline_grace_hours: 48`.

### Trial

1. THE system SHALL grant **one trial per email** (no re-trial on re-register)
2. Trial duration SHALL be configurable via `PORTAL_TRIAL_DAYS` (default: **14**)
3. `trial_ends_at` SHALL be set at registration: `inserted_at + trial_days`
4. When `now > trial_ends_at` and no active paid subscription → `subscription_status: expired`

### Paid subscription

1. THE system SHALL support plan `individual` (annual)
2. Payment processing is specified in **M31 — Payments**
3. On successful payment (via M31 webhook) THE system SHALL set `subscription_status: active` and `subscription_ends_at`
4. THE account dashboard SHALL show license key for manual entry (backup if token refresh fails)
5. After payment THE desktop app SHALL restore entitlements on next validate — **no re-activation required** if tokens still valid

## Requirement 4: License Key (Backup Auth)

1. THE system SHALL generate a per-user license key on registration: format `SPM-XXXX-XXXX-XXXX` (hex, uppercase)
2. THE user MAY view license key on account dashboard (requires web session login)
3. THE desktop app SHALL accept license key + email as alternative to OAuth-style token flow:

```
POST /api/v1/auth/activate
Body: { "email": "...", "license_key": "SPM-...", "device_id": "...", "platform": "...", "app_version": "..." }
→ 200 {
     "status": "ok",
     "data": {
       "access_token": "...",
       "refresh_token": "...",
       "subscription_status": "trial" | "active" | "expired" | "cancelled",
       "plan": "trial" | "individual",
       "trial_ends_at": "2026-06-25T00:00:00Z",
       "subscription_ends_at": null,
       "validated_at": "2026-06-11T12:00:00Z",
       "offline_grace_hours": 48,
       "entitlements": {
         "premium_features": true,
         "fx_sync": true
       }
     }
   }
```

4. Activate returns **tokens plus entitlements** (superset of validate — desktop saves tokens and cached entitlements in one step). Unlike validate, activate does not require a Bearer token.
5. Rate limit on activate: **10 attempts/hour per IP**

## Requirement 5: Entitlements

1. `premium_features` = true when status is `trial` or `active`
2. `fx_sync` = true when status is `trial` or `active` (M29 enforces)
3. Premium features in desktop app (M30):
   - Schedule FA CSV export
   - Capital Gains CSV export
   - Schedule FSI export (when built)
   - Sell Advisor
4. Free/expired users MAY still use: upload, portfolio view, E*Trade guide (local app basics) — exact gating list configurable in M30

## Requirement 6: Web Account UI (Portal)

1. `/account/register` — registration form → auto-login → dashboard
2. `/account/login` — session-based web login (separate from JWT; or JWT in session cookie)
3. `/account` dashboard:
   - Subscription status + trial days remaining
   - License key (copy button)
   - Link to billing / upgrade
   - Download links
   - "Sign out"
4. `/account/billing` — upgrade to Individual (M31 checkout)
5. `/account/delete` — account deletion (M32 — DPDP erasure)

## Requirement 7: JWT Specification

1. Access token TTL: **15 minutes**
2. Refresh token TTL: **30 days**
3. Algorithm: **RS256 only** (asymmetric; portal holds private key, desktop verifies with embedded public key — no shared secret in client binary)
4. Claims: `sub` (user_id), `exp`, `iat`, `type` (`access` | `refresh`)

## Requirement 8: Data Model (Postgres — portal only)

### portal_users

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT PK | hex |
| email | TEXT | unique |
| password_hash | TEXT | |
| license_key | TEXT | unique, SPM-... |
| inserted_at | utc_datetime_usec | trial start |
| updated_at | utc_datetime_usec | |

### portal_subscriptions

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT PK | |
| user_id | TEXT FK | |
| status | TEXT | trial / active / expired / cancelled |
| plan | TEXT | trial / individual |
| trial_ends_at | utc_datetime | |
| subscription_ends_at | utc_datetime | nullable |
| payment_provider | TEXT | razorpay / stripe / null |
| payment_provider_ref | TEXT | external subscription id |
| inserted_at, updated_at | | |

### portal_refresh_tokens

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT PK | |
| user_id | TEXT FK | |
| token_hash | TEXT | SHA256 of token |
| expires_at | utc_datetime | |
| revoked_at | utc_datetime | nullable |

### portal_device_validations (audit)

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT PK | |
| user_id | TEXT FK | |
| device_id | TEXT | client-generated UUID |
| platform | TEXT | macos_aarch64 / windows_x86_64 / ... |
| app_version | TEXT | |
| validated_at | utc_datetime | |

**Explicitly NO tables for:** origins, tranches, sales, uploads, tax rows.

### Requirement 8a: Device Limit

1. THE system SHALL allow **maximum 3 distinct device_ids** per user with validation in the last 30 days
2. WHEN a 4th device validates THE system SHALL return HTTP **403** with message: "Device limit reached. Deactivate a device from your account dashboard."
3. Phase 1 enforcement: count distinct `device_id` in `portal_device_validations` where `validated_at` > 30 days ago
4. Phase 1b: account dashboard "Manage devices" to revoke a device (soft-block by adding to `portal_revoked_devices`)

## Requirement 9: Security

1. Rate limits:
   - register: 5/hour/IP
   - login: 10/hour/IP
   - validate: 60/hour/user_id AND 60/hour/IP
   - activate: 10/hour/IP
2. Password minimum: 8 characters (Phase 1). Before open public launch: add minimum entropy check (e.g. zxcvbn score ≥ 2)
3. HTTPS only in production
4. **CORS not required** for `/api/v1/*` — desktop calls portal via Finch (server-side HTTP, no browser). Web account UI is same-origin LiveView. No browser JS client calls these API routes in Phase 1.

## Requirement 10: Email

Email delivery specified in **M32 — Portal Operations**. M28 requires:
1. Password reset email
2. Trial ending reminder (3 days before)
3. Payment receipt (via M31 / payment provider)

---

## Out of Scope (M28)

- Storing or processing brokerage files
- Cloud portfolio/tax API — see [M17 DISPOSITION](../M17-rest-api/DISPOSITION.md)
- Payment checkout and webhooks (M31)
- Email infrastructure (M32)
- Multi-seat / team plans
- OAuth providers
- App Store / Play billing

## M17 Impact

See [M17 DISPOSITION](../M17-rest-api/DISPOSITION.md). M17 endpoints are localhost-only; not deployed to cloud.
