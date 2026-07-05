# Test Plan: M28 — Cloud Auth & Subscription

---

## TP-1: Registration (Automated)

**File:** `test/portal/accounts_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Valid register | User created, subscription status trial |
| TP-1.2 | Duplicate email | Error |
| TP-1.3 | Weak password | Changeset error |
| TP-1.4 | License key generated | Matches `SPM-` format, unique |
| TP-1.5 | trial_ends_at | inserted_at + PORTAL_TRIAL_DAYS |

## TP-2: Login & Tokens (Automated)

**File:** `test/portal/auth_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Valid login | Returns access + refresh tokens |
| TP-2.2 | Invalid password | Error |
| TP-2.3 | Access token verify | sub claim = user_id |
| TP-2.4 | Expired access token | Rejected |
| TP-2.5 | Refresh rotation | Old refresh invalid after use |
| TP-2.6 | Logout | Refresh token revoked |

## TP-3: Auth API (Automated)

**File:** `test/portal_web/controllers/api/auth_controller_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | POST register | 201, tokens in body |
| TP-3.2 | POST login | 200, tokens |
| TP-3.3 | POST validate with valid token | 200, entitlements premium true (trial) |
| TP-3.4 | POST validate expired trial | 200, subscription_status expired, premium false |
| TP-3.5 | POST activate with license key | 200, tokens + entitlements in body |
| TP-3.6 | POST activate wrong key | 401 |
| TP-3.7 | POST validate no auth | 401 |
| TP-3.8 | Rate limit validate | 429 by user_id/IP |
| TP-3.9 | Device limit 4th device | 403 |
| TP-3.10 | Activate rate limit | 429 after 10/hour/IP |

## TP-4: Subscription State Machine (Automated)

**File:** `test/portal/subscriptions_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | Active trial | status :trial, fx_sync true |
| TP-4.2 | Trial past end | status :expired |
| TP-4.3 | Active paid | status :active, subscription_ends_at future |
| TP-4.4 | Paid past end | status :expired |
| TP-4.5 | offline_grace_hours | Always 48 in response |

## TP-5: Device Validation Audit (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Validate records device | Row in portal_device_validations |
| TP-5.2 | device_id + platform stored | Matches request body |

## TP-6: Web Account UI (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Register via web | Redirects to dashboard |
| TP-6.2 | Dashboard trial | Days remaining shown |
| TP-6.3 | License key | Visible, copy works |
| TP-6.4 | Login existing user | Dashboard loads |
| TP-6.5 | Logout | Session cleared |
| TP-6.6 | /account unauthenticated | Redirect to login |

## TP-7: Security (Manual + Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | Password not in API response | JSON has no password fields |
| TP-7.2 | Refresh token not in logs | Grep logs after test run |
| TP-7.3 | HTTPS in prod | curl http redirects |

## TP-8: Data Isolation (Manual Inspection)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.1 | Postgres schema | No stock_plan_* financial tables |
| TP-8.2 | Validate request body | No file upload fields accepted |
| TP-8.3 | API docs review | No portfolio/tax endpoints |

## TP-9: Billing (Manual — if implemented)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-9.1 | Razorpay test checkout | Subscription becomes active |
| TP-9.2 | Webhook replay | Idempotent, no double activation |
| TP-9.3 | Dashboard after pay | status active, fx_sync true |

## TP-10: Integration with M30 (Manual — after M30)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-10.1 | Desktop activate | Tokens saved locally |
| TP-10.2 | Desktop validate on startup | Premium features unlocked |
| TP-10.3 | Offline 24h | App still works |
| TP-10.4 | Offline 49h | Premium blocked until online validate |

---

## Test Data

- Trial user: register fresh email, validate immediately
- Expired trial: fixture with `trial_ends_at` in past (factory or SQL seed)
- Active paid: fixture with future `subscription_ends_at`
