# Requirements: M31 — Payments (Razorpay)

## Introduction

Enable **paid subscriptions** for the Individual plan on the cloud portal. Required before any paid tier goes live. Integrates with M28 subscription state and M30 desktop entitlements (restore on next validate — no re-activation).

**Provider:** Razorpay (India). Stripe deferred.

---

## Requirement 1: Plan Definition

1. Plan id: `individual_annual`
2. Billing cycle: **annual**
3. Price: configurable via `PORTAL_INDIVIDUAL_PRICE_INR` (paise) — TBD at launch
4. Currency: INR
5. One active subscription per user

## Requirement 2: Checkout Flow

1. User on `/account/billing` clicks **Upgrade**
2. Portal creates Razorpay **Subscription** or **Order** server-side
3. User redirected to Razorpay hosted checkout
4. On success redirect to `/account/billing?status=success`
5. On cancel redirect to `/account/billing?status=cancelled`
6. Subscription activation is **webhook-driven** (not redirect alone)

## Requirement 3: Webhook Handler

```
POST /webhooks/razorpay
```

1. Verify Razorpay signature on raw body
2. Handle events (minimum):
   - `subscription.activated` / `payment.captured` → set M28 subscription `active`
   - `subscription.cancelled` → set `cancelled`, retain access until `subscription_ends_at`
   - `subscription.completed` / period end → set `expired` if not renewed
   - `payment.failed` → log; optional grace period (see Requirement 5)
3. Idempotent on Razorpay event id / payment id
4. Store `payment_provider_ref` on `portal_subscriptions`

## Requirement 4: Subscription Lifecycle

| Event | portal_subscriptions.status | Entitlements |
|-------|----------------------------|--------------|
| Payment success | `active` | premium + fx_sync |
| User cancels | `cancelled` | premium until period end |
| Period ends (no renewal) | `expired` | none |
| Trial (no payment) | `trial` | per M28 |

1. `subscription_ends_at` = paid period end date from Razorpay
2. Desktop restores entitlements on next `validate` after webhook — no license re-entry

## Requirement 5: Renewal Failure (Dunning)

1. IF renewal payment fails THE system SHALL retain `active` for **7 days** grace (`past_due` sub-status in metadata)
2. After 7 days without payment → `expired`
3. Email user on failure (M32)
4. Phase 1: manual retry via billing page link

## Requirement 6: Billing UI

1. `/account/billing` shows: current plan, renewal date, upgrade CTA, cancel link
2. Cancel: initiates Razorpay cancel-at-period-end (not immediate revoke if paid period remains)
3. Receipt: link to Razorpay invoice or email receipt

## Requirement 7: Data Model Additions

### portal_payments (audit)

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT PK | |
| user_id | TEXT FK | |
| razorpay_payment_id | TEXT | unique |
| razorpay_subscription_id | TEXT | |
| amount_paise | integer | |
| status | TEXT | captured / failed / refunded |
| inserted_at | utc_datetime | |

## Requirement 8: Security

1. Webhook secret in env `RAZORPAY_WEBHOOK_SECRET`
2. Never log full payment payloads with PII in production
3. Billing routes require web session auth (M28)

## Requirement 9: Trial-Only Launch Option

1. MAY ship M27+M28+M30 before M31 is complete (trial-only)
2. Billing page shows "Coming soon" until M31 live
3. **Paid tier MUST NOT be advertised** on pricing page until M31 complete

---

## Out of Scope (M31)

- Stripe / international cards
- Monthly billing
- Refund automation (manual support)
- GST invoice generation (Phase 2)
- Team / multi-seat plans

## Dependencies

- M28 auth + subscription schema
- M32 email for payment receipts and dunning
