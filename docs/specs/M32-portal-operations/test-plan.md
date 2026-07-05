# Test Plan: M32 — Portal Operations & Compliance

---

## TP-1: Email (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Password reset | Email received, link works |
| TP-1.2 | Trial reminder | Sent 3 days before end |
| TP-1.3 | SPF/DKIM | mail-tester.com score acceptable |

## TP-2: Account Deletion (Automated + Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Delete account | All portal_* user rows gone |
| TP-2.2 | Deletion audit | user_id_hash row exists, no email |
| TP-2.3 | Desktop data | Local SQLite unchanged |
| TP-2.4 | Wrong confirm email | Blocked |
| TP-2.5 | Active subscription | Cancelled first or blocked with message |

## TP-3: Admin Tasks (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | extend_trial | trial_ends_at updated |
| TP-3.2 | revoke_tokens | Desktop refresh fails, re-login works |

---

## Test Count: ~10
