# Requirements: M32 — Portal Operations & Compliance

## Introduction

Operational infrastructure for the cloud portal: **email delivery**, **account deletion (DPDP)**, and **admin runbooks**. Supports M28 (auth emails), M31 (payment receipts), and M29 (FX ops).

---

## Requirement 1: Email Infrastructure

1. Provider: **Postmark** or **Resend** (TBD at setup — transactional focus)
2. Configure SPF, DKIM, DMARC for sending domain before production
3. Mailer: Swoosh adapter
4. Required emails:
   - Password reset (M28)
   - Trial ending — 3 days before (M28)
   - Payment receipt (M31)
   - Payment failed / dunning (M31)
5. Dev: local mailbox / log-only adapter
6. FROM address: `noreply@{portal_domain}`

## Requirement 2: Account Deletion (DPDP Act 2023)

1. THE system SHALL provide `DELETE /account` (web UI + API) for authenticated users
2. Deletion SHALL remove:
   - `portal_users` row (email, password_hash, license_key)
   - `portal_subscriptions`, `portal_refresh_tokens`, `portal_device_validations`, `portal_payments`
3. Deletion SHALL NOT affect desktop SQLite (user's local data untouched)
4. Razorpay: cancel active subscription before delete if `active`
5. Confirmation: type email to confirm
6. Grace period: none — immediate deletion
7. Audit log: retain `{user_id_hash, deleted_at}` for 90 days (no email stored)

## Requirement 3: Admin Operations (Mix Tasks)

| Task | Purpose |
|------|---------|
| `mix portal.admin.extend_trial EMAIL DAYS` | Support: extend trial |
| `mix portal.admin.revoke_tokens EMAIL` | Force re-login |
| `mix portal.admin.import_fx` | Alias to M29 import |
| `mix portal.fx.seed` | M29 seed |

1. Admin tasks require `PORTAL_ADMIN_SECRET` env or run only in `Mix.env() == :dev`

## Requirement 4: JWT Key Rotation Runbook

1. Document procedure: generate new RSA key pair → deploy public key to desktop release → dual-sign period → retire old key
2. Store private key in secrets manager (Fly secrets / env)
3. Desktop embeds public key only (`priv/portal_jwt_public.pem`)

## Requirement 5: Portal Downtime — Desktop Behavior

Already spec'd in M30 (48h offline grace). Runbook documents:
1. Desktop continues with cached entitlements ≤ 48h
2. FX sync fails non-fatally; local rates used
3. Status page URL (optional Phase 1b)

## Requirement 6: FX Operations Runbook

1. **Monthly:** import new SBI TT rate via `mix portal.fx.import` (within 5 business days of month end)
2. **Each desktop release:** regenerate `StockPlan.Release.Seeds` from latest FX data (min every 3 months)
3. Verify portal + desktop seed parity in CI

## Requirement 7: Privacy Policy Content

1. `/privacy` SHALL state:
   - Data collected: email, subscription metadata, device audit (no financial data)
   - Right to erasure via account deletion
   - Clock rollback limitation for offline grace (M30)
   - Data retention: device validations 90 days

---

## Out of Scope (M32)

- Full admin dashboard UI
- SOC2 / formal compliance audit
- Automated FX scraping (Phase 2)

## Dependencies

- M28 users schema
- M31 payments for cancel-before-delete
