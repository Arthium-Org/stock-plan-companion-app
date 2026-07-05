# Cursor Feedback Round 2 — G&L Allocation Aggregation Spec

## Accept / Reject Summary

| Item | Verdict | Action taken |
|---|---|---|
| M24 vs wash-sale problem split | Accept | No change — already correct |
| Problem table (RU343763 / RU383740) | Accept | No change — already corrected in round 1 |
| Req 1 — aggregate first, no silent drop | Accept | No change |
| Req 2 — ESPP must use Grant Date, not Grant Number ("--") | Accept | Fixed: branched key — RS uses grant_number+vest_date; ESPP uses grant_date+purchase_date |
| Req 2 — "per file" wording | Accept | Fixed to "surviving Bronze row set after cross-file dedup" |
| Req 3 — latest wins via inserted_at | Accept | No change |
| Req 4 — BH reconciliation warning | Accept | No change |
| Req 5–6 | Accept | No change |
| Design aggregate_gl_bronze — ESPP grant_date in group key | Accept | Fixed: ESPP group key uses grant_date; lot struct carries tranche_key (grant_number for RS, grant_date for ESPP) |
| Design aggregate_gl_bronze — vest_fmv carry | Accept | Added: lot carries first non-nil Vest Date FMV for fill_tranche_fmv |
| Design upsert_gl_allocation | Accept | No change |
| Design ESPP origin lookup — Reject (incomplete) | Accept (cursor correct) | Fixed: added process_aggregated_lot section with full RS/ESPP dispatch; find_espp_origin uses lot.tranche_key = grant_date |
| Design new-flow diagram step 2 — stale ingestion_id | Accept (cursor correct) | Fixed: "latest inserted_at ingestion only" |
| Tasks T1 steps 2–3 — stale ingestion_id wording | Accept (cursor correct) | Fixed: step 2 now says inserted_at comparison |
| Tasks T3 lot fields — incomplete for ESPP | Accept (cursor correct) | Fixed: full plan_type dispatch with correct field names per plan type |
| Tasks T3 fill_tranche_fmv note | Accept | Added as step 3 in T3 |
| Tasks T4–T7 | Accept | No change |
| Test plan TP1–TP3, TP1b, TP5b, TP6–TP9 | Accept | No change |
| Test plan TP4 — stale ingestion_id | Accept (cursor correct) | Fixed: "later inserted_at timestamp" |
| cursor-feedback-on-specs.md | Accept | No change |
