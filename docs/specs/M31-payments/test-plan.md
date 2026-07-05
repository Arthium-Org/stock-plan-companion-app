# Test Plan: M31 — Payments (Razorpay)

---

## TP-1: Checkout (Manual — Razorpay Test)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Click Upgrade | Redirects to Razorpay test checkout |
| TP-1.2 | Successful test payment | Webhook fires, subscription active |
| TP-1.3 | Cancel checkout | Returns to billing, still trial/expired |

## TP-2: Webhook (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Valid signature | 200, subscription updated |
| TP-2.2 | Invalid signature | 401 |
| TP-2.3 | Duplicate event id | Idempotent, no double activation |
| TP-2.4 | payment.failed | past_due metadata, email queued |

## TP-3: Lifecycle (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | activate_paid | status active, ends_at set |
| TP-3.2 | Cancel | cancelled, access until period end |
| TP-3.3 | Period end | expired |

## TP-4: Desktop E2E (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | Pay on web, validate desktop | premium_features true |
| TP-4.2 | No re-activation needed | Existing tokens work |

---

## Test Count: ~12
