# Tasks: M32 — Portal Operations & Compliance

## Milestone 1: Email

- [ ] 1.1 Swoosh + Postmark/Resend adapter
- [ ] 1.2 SPF/DKIM/DMARC for domain
- [ ] 1.3 Password reset email template
- [ ] 1.4 Trial reminder email
- [ ] 1.5 Wire M28 password reset to mailer

## Milestone 2: Account Deletion

- [ ] 2.1 Migration: `portal_deletion_audit`
- [ ] 2.2 `Accounts.delete_account/1`
- [ ] 2.3 DeleteLive UI with email confirmation
- [ ] 2.4 Cancel Razorpay before delete (M31)
- [ ] 2.5 Tests

## Milestone 3: Admin Tasks

- [ ] 3.1 `mix portal.admin.extend_trial`
- [ ] 3.2 `mix portal.admin.revoke_tokens`
- [ ] 3.3 Admin secret guard

## Milestone 4: Runbook & Privacy

- [ ] 4.1 Write `docs/ops/portal-runbook.md`
- [ ] 4.2 Update `/privacy` with DPDP + data inventory
- [ ] 4.3 Document JWT rotation procedure
- [ ] 4.4 FX monthly ops checklist in runbook

---

## Definition of Done

- Password reset email delivers in prod
- User can delete account from dashboard
- Runbook covers top 5 support scenarios
