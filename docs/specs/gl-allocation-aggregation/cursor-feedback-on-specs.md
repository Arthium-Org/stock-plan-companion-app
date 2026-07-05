# Cursor Feedback — G&L Allocation Aggregation Spec

## Accept / Reject Summary

| Item | Verdict | Action taken |
|---|---|---|
| Problem diagnosis (wash-sale sub-lots dropped) | Accept | Confirmed in sample data |
| Req 1 — no silent row drop | Accept | Retitled; wording clarified to "aggregate first, then one Silver row per group" |
| Req 2 — grouping key (symbol, grant, vest, order, price) | Accept with fix | Plan-type keys: RS uses grant_number+vest_date; ESPP uses grant_date+purchase_date |
| Req 3 — latest wins per (symbol, sale_date) | Accept with fix | Fixed to use `inserted_at` not `ingestion_id`; M6/M8 behavior change documented |
| Req 4 — BH qty reconciliation ±2 | Accept | Added warning (not hard-fail) behavior |
| Req 5 — ESPP order numbers always present | Accept | Unchanged |
| Req 6 — no schema change | Accept | Unchanged |
| Design `aggregate_gl_bronze/1` shape | Accept with fixes | Fixed field names, ESPP key branching, record_type filter, inserted_at comparison |
| Design `upsert_gl_allocation/5` | Accept | Unchanged |
| ingestion_id sorts by upload time | Reject (cursor correct) | Fixed: ingestion_id is random hex; use `inserted_at` |
| Pseudo-code used `&1.id` | Reject (cursor correct) | Fixed to `ingestion_id` |
| M8 "all G&L coexist" — behavior change | Accept | Documented in Req 3: latest-wins applies to overlapping (symbol, sale_date) only |
| Tasks T4 rebuild commands `--user` flag | Reject (cursor correct) | Fixed: `mix stock_plan.rebuild --user=…` does not exist; updated to actual CLI |
| Test plan TP1–TP3 (core cases) | Accept | TP1b added for SampleUser 1 with corrected dates |
| Test plan TP4 (cross-file latest wins) | Accept with fix | Fixed to use later `inserted_at`, not ingestion_id |
| Test plan TP6–TP7 manual test | Accept | Commands corrected; TP7b added for SampleUser 2 |
| Problem table RU343763 vest 06/17/2025 | Reject (cursor correct) | Fixed: vest is 01/24/2025, qty=2+2 at order 93462327, price=388.075 |
| M24 distinction — different failure mode | Accept (missing) | Added to Problem section |
| Unit test for `aggregate_gl_bronze/1` | Accept | TP5b added; T4 updated |
| Add SampleUser 2 to fixtures | Accept | T6 added |

---

## Second review (post-update) — fixes applied

| Item | Verdict | Action taken |
|---|---|---|
| ESPP group key uses Grant Date not Grant Number | Accept | Req 2, design pseudo-code, tasks T1/T3 updated |
| Aggregated lot carries `grant_date` for ESPP origin lookup | Accept | design lot map + process_aggregated_lot section |
| Stale "highest ingestion_id" in design diagram | Accept | Fixed to latest `inserted_at` |
| Stale ingestion_id in tasks T1 | Accept | Fixed to `inserted_at` |
| Stale ingestion_id in test plan TP4 | Accept | Fixed to later `inserted_at` |
| Req 2 "per file" wording | Accept | Changed to "surviving rows after cross-file dedup" |
| RSU `fill_tranche_fmv` on aggregated path | Accept | Added to design + T3 |

**Status:** Specs implementation-ready as of second review.
