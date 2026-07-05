# System Invariants

These are non-negotiable architectural rules. Violating any of these breaks the system's correctness guarantees. Reference this document in code reviews and before any refactor.

---

## 1. Silver is Always Full Rebuild

Silver is rebuilt entirely from Bronze — DELETE + INSERT, never partial updates.

**Why:** Silver fields are written by multiple phases (BH, G&L, FX, Stock Prices, Holdings). A partial rebuild would leave stale data from a previous phase, making the system non-deterministic.

**Rule:** `SilverBuilder.build(account_id)` always deletes all Silver rows for the account and rebuilds from scratch. No function may update a single Silver field without going through a full rebuild.

**If violated:** Tranche fields become a mix of values from different ingestion states. Debugging becomes impossible — you can't tell which phase wrote which value.

---

## 2. Same Bronze = Same Silver (Determinism)

Given identical Bronze rows, Silver rebuild produces identical output. No external state, no randomness, no time-dependency in the rebuild logic.

**Why:** This is the foundation of auditability. You can always explain a Silver value by pointing to the Bronze rows that produced it.

**Rule:** Silver Builder reads only from `bronze_raw` + `fx_monthly_rates` (static master data). It never reads current time, live prices, or external APIs during rebuild.

**If violated:** Rebuild produces different results on different days. "Just rebuild" stops being a safe recovery action.

---

## 3. One ACTIVE Ingestion Per Category Per Symbol Per Account

Each (category, symbol) pair maintains exactly one ACTIVE ingestion per account. New upload for a given symbol archives the previous ACTIVE ingestion for that same category + symbol combination only.

**Why:** M22 introduced per-symbol BH and Holdings files. A user can hold ADBE and CRM simultaneously — each has its own BH file and its own Holdings file. Archiving must be scoped to the symbol being re-uploaded, not the whole category.

**Rule:**
- BH upload for symbol S → archives previous ACTIVE BH where `dominant_symbol = S`; leaves other symbols' BH untouched
- Holdings upload for symbol S → archives previous ACTIVE Holdings where `dominant_symbol = S`; leaves other symbols' Holdings untouched
- G&L upload → additive, multiple ACTIVE per account (no archiving; G&L is multi-symbol by design)
- Categories are independent — Holdings upload never touches BH or G&L

**Enforced by:** `dominant_symbol` column on `stock_plan_ingestions` (added in M22 migration).

**If violated:** Re-uploading BH for ADBE archives CRM BH. CRM data disappears from Silver until re-uploaded. User loses portfolio and tax data for CRM silently.

---

## 4. Portfolio Source Contract

Portfolio uses a single source per build — never mixes sources.

**Source = Holdings Silver ONLY.** Always. No fallback.

- VESTED quantity = `sellable_qty` from Holdings
- UNVESTED = vest schedule rows present in Holdings (if any)
- No reconstruction from BH. No merge. No inference.

**Behavior matrix:**

| Holdings | BH | Portfolio shows |
|---|---|---|
| Yes | Yes | Holdings only (BH ignored for Portfolio) |
| Yes | No | Holdings only |
| No | Yes | Blocked — Holdings required (see rationale) |
| No | No | Blocked — upload BH first, then Holdings |

**System must NOT:**
- Fall back to BH data when Holdings is absent
- Merge BH data into Portfolio alongside Holdings
- Derive missing unvested or sold quantities from BH
- Reconcile cost_basis across sources
- Auto-correct user data

**Why Holdings is mandatory when current shares exist:**
BH records gross grant and vest events. It does not record:
- How many shares were withheld for taxes at each vest (tax-withheld qty)
- Lot-level sell linkage (which specific lots were sold, only origin-level totals)
- Current broker-confirmed sellable balance

A BH-derived "vested - origin-sold" estimate will be wrong in any case where:
- Tax withholding varied per vest (common for RSU)
- Partial lots were sold from specific vests (common for ESPP)
- Broker corrections or adjustments occurred

Holdings (ByBenefitType export) is the broker's confirmed snapshot of current sellable quantities.
It is authoritative. BH is the history of events; Holdings is the current state. **Both are needed
for a complete picture; neither substitutes for the other.**

**Design history:** The BH fallback (`No Holdings → BH-derived estimate`) was the original design
before the Holdings upload feature existed. Once Holdings upload was introduced (M5b), the BH
fallback became stale. It is now removed. The correct place for BH-derived historical data is the
History page (M24), not Portfolio.

**If violated:** Portfolio shows estimated quantities from BH that may differ from broker reality.
User makes sell decisions based on wrong sellable balances. Tax calculations become incorrect.

---

## 5. Cost Basis: Pure Fallback, No Reconciliation

Priority chain: `cost_basis_broker` > `vest_fmv` > `vest_day_close` > nil

This is a fallback, not a comparison. If `cost_basis_broker` exists, it is authoritative — period. Never compare it to `vest_fmv`, never flag a "mismatch", never "correct" one from the other.

**Why:** Broker cost basis includes adjustments invisible to us (wash sale rules, ESPP qualification/disqualification, corporate actions). It may legitimately differ from vest_fmv.

**If violated:** Someone adds "reconciliation logic" that overrides correct broker data with incorrect derived data. Financial harm to user.

---

## 6. Bronze is Append-Only

Bronze rows are never updated or deleted. All uploads retained for audit and reprocessing.

**Why:** Bronze is the immutable audit trail. If Silver is wrong, you trace back to Bronze. If Bronze is mutated, you lose the ability to diagnose.

**Rule:** No UPDATE or DELETE queries against `stock_plan_bronze_raw`. Archiving an ingestion changes the ingestion status, not the Bronze rows.

**If violated:** Audit trail broken. Cannot reproduce historical Silver states. Cannot diagnose data quality issues.

---

## 7. System Never Invents Financial Truth

If data is missing (which lot was sold, what the cost basis is, how many shares are sellable), show "unknown" / "N/A" / empty. Never fabricate tranche-level data from origin-level data. Never distribute aggregate quantities across tranches by assumption (e.g., FIFO without source data).

**Why:** Users make real financial decisions (sell timing, tax planning) based on this data. Wrong data is worse than missing data.

**If violated:** User sees fabricated per-tranche quantities, makes incorrect sell decisions, incurs avoidable tax liability.

---

## 8. No Cross-Ingestion Mixing

A query never joins rows from different ingestion_ids within the same category. Silver for one account is built from that account's ACTIVE ingestions only.

**If violated:** Data from archived (stale) ingestions bleeds into current view. User sees phantom grants or incorrect quantities.

---

## Practical Debugging Aid

When debugging Portfolio values, log the Holdings ingestion_id used:

```
[Portfolio.build] account=default, holdings_ingestion=abc123, bh_ingestion=def456
```

This gives instant visibility into which snapshot produced the displayed data without tracing through Bronze manually.
