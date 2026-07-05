# Design: M31 — Payments (Razorpay)

## Flow

```
User → /account/billing → Upgrade
  → Portal.Payments.create_checkout(user)
  → Razorpay API (subscription create)
  → Redirect to Razorpay hosted page
  → User pays
  → Razorpay webhook → PortalWeb.WebhookController
  → Portal.Subscriptions.activate_paid(user, ends_at, ref)
  → Desktop validate on next startup → entitlements restored
```

---

## Modules

```
portal/lib/portal/
├── payments.ex           # Razorpay API client
└── payments/webhook.ex   # Event dispatch

portal/lib/portal_web/
├── live/account/billing_live.ex
└── controllers/webhook_controller.ex
```

---

## Razorpay Integration

```elixir
defmodule Portal.Payments do
  def create_subscription_checkout(user)
  def cancel_at_period_end(user)
end
```

Use official Razorpay Elixir SDK or Finch + REST.

Webhook verification:

```elixir
Razorpay.Utility.verify_webhook_signature(body, signature, secret)
```

---

## Activate Paid Subscription

```elixir
def activate_paid(user_id, subscription_ends_at, provider_ref) do
  # Update portal_subscriptions:
  # status: active, plan: individual, subscription_ends_at, payment_provider_ref
end
```

---

## Config

```elixir
config :portal,
  razorpay_key_id: System.get_env("RAZORPAY_KEY_ID"),
  razorpay_key_secret: System.get_env("RAZORPAY_KEY_SECRET"),
  razorpay_webhook_secret: System.get_env("RAZORPAY_WEBHOOK_SECRET"),
  individual_price_paise: System.get_env("PORTAL_INDIVIDUAL_PRICE_INR")
```

---

## Desktop Integration (M30)

No desktop payment UI. After webhook:
1. User's existing tokens remain valid
2. Next `POST /auth/validate` returns `subscription_status: active`
3. If offline within 48h grace, premium may lag until validate — acceptable

---

## Test Mode

Razorpay test keys in dev. Webhook testing via Razorpay dashboard or ngrok to local portal.
