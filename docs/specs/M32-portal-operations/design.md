# Design: M32 — Portal Operations & Compliance

## Email Stack

```
Portal.Mailer (Swoosh)
  ├── Postmark adapter (prod)
  └── Local adapter (dev)

Templates: portal/lib/portal_web/emails/*.heex
```

---

## Account Deletion

```elixir
defmodule Portal.Accounts do
  def delete_account(user_id) do
    Repo.transaction(fn ->
      Payments.cancel_if_active(user_id)
      Repo.delete_all(refresh_tokens for user)
      Repo.delete_all(device_validations for user)
      Repo.delete_all(subscriptions for user)
      Repo.delete_all(payments for user)
      insert_deletion_audit(hash(user_id))
      Repo.delete!(user)
    end)
  end
end
```

UI: `Account.DeleteLive` at `/account/delete` — confirm email input.

---

## Admin Tasks

```elixir
# lib/mix/tasks/portal.admin.extend_trial.ex
# Validates PORTAL_ADMIN_SECRET from argv or env
```

---

## Runbook Location

`docs/ops/portal-runbook.md` — created during M32 implementation (referenced from portal README).

Sections:
1. Extend trial
2. Import FX month
3. Rotate JWT keys
4. Revoke user tokens
5. Handle Razorpay webhook failures
6. Portal outage response

---

## Deletion Audit Table

### portal_deletion_audit

| Column | Type |
|--------|------|
| id | TEXT PK |
| user_id_hash | TEXT |
| deleted_at | utc_datetime |

No email stored post-deletion.
