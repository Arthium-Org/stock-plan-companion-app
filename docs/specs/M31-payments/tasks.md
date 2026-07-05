# Tasks: M31 — Payments (Razorpay)

## Prerequisites

- M28 auth + subscription schema live
- Razorpay account (test + live keys)

---

## Milestone 1: Razorpay Client

- [ ] 1.1 Add Razorpay SDK or HTTP client
- [ ] 1.2 Env config for keys
- [ ] 1.3 `Payments.create_subscription_checkout/1`

## Milestone 2: Webhook

- [ ] 2.1 Migration: `portal_payments`
- [ ] 2.2 `POST /webhooks/razorpay` with signature verify
- [ ] 2.3 Handlers: activated, cancelled, payment.failed
- [ ] 2.4 Idempotency on payment id
- [ ] 2.5 Tests with fixture payloads

## Milestone 3: Subscription Updates

- [ ] 3.1 `Subscriptions.activate_paid/3`
- [ ] 3.2 Cancel at period end
- [ ] 3.3 Dunning: 7-day past_due grace
- [ ] 3.4 Tests

## Milestone 4: Billing UI

- [ ] 4.1 BillingLive — upgrade, status, cancel
- [ ] 4.2 Success/cancel redirect handling
- [ ] 4.3 Manual test Razorpay test mode E2E

## Milestone 5: Integration

- [ ] 5.1 M28 dashboard shows paid status
- [ ] 5.2 M30 validate returns active after webhook
- [ ] 5.3 M27 pricing page enabled only when M31 done

---

## Definition of Done

- Test-mode payment activates subscription
- Desktop entitlements restore on validate without re-activation
- Webhook idempotent and signature-verified
