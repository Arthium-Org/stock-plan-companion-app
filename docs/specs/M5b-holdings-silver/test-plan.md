# Test Plan: M5b — Holdings Silver (Own Tables)

---

## TP-1: Schema + Migration (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Holding record creation | Insert with required fields succeeds |
| TP-1.2 | Required fields enforced | Insert without plan_type/status fails |
| TP-1.3 | SafeDecimal fields | Decimal values stored and retrieved correctly |

## TP-2: HoldingsSilverBuilder — RSU (Automated)

**File:** `test/stock_plan/ingestion/holdings_silver_builder_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | SampleUser-3 RSU: row count | One Holdings row per Vest Schedule period |
| TP-2.2 | Grant-level fields | grant_number, grant_date, granted_qty populated |
| TP-2.3 | Vest Schedule fields | vest_date, vested_qty, released_qty populated |
| TP-2.4 | Sellable Shares merge | Periods with Sellable Shares have sellable_qty > 0 |
| TP-2.5 | VESTED without Sellable Shares | sellable_qty = 0 (fully sold) |
| TP-2.6 | UNVESTED periods | status = "UNVESTED", sellable_qty = nil |
| TP-2.7 | Status derivation | released_qty > 0 → VESTED, else UNVESTED |
| TP-2.8 | Cost basis from Sellable Shares | cost_basis populated from Est. Cost Basis |
| TP-2.9 | Blocked info in metadata | metadata_json has blocked, blocked_type |
| TP-2.10 | SampleUser-2 RSU (no Sellable Shares) | All vested periods have sellable_qty = 0 |
| TP-2.11 | Rebuild idempotent | Second build produces same result |

## TP-3: HoldingsSilverBuilder — ESPP (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | SampleUser-3 ESPP: row count | One Holdings row per Purchase (4 expected) |
| TP-3.2 | cost_basis = Purchase Date FMV | Not discounted buy price |
| TP-3.3 | purchase_price = discounted buy price | Stored separately |
| TP-3.4 | sellable_qty = Sellable Qty + Blocked Qty | Total owned shares |
| TP-3.5 | status = VESTED | All purchases are VESTED |
| TP-3.6 | grant_number generated | Hash of "ESPP:{symbol}:{grant_date}" |
| TP-3.7 | grant_date = enrollment date | Not purchase date |

## TP-4: FX Enrichment (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | vest_fx_rate populated | Non-nil for rows with vest_date |
| TP-4.2 | Correct rate | Matches FX.get_rate(vest_date) |
| TP-4.3 | UNVESTED future dates | FX rate may be nil (no future rates) |

## TP-5: Orchestrator Integration (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | ingest_holdings end-to-end | Holdings Silver rows created |
| TP-5.2 | BH Silver NOT rebuilt | BH tranches unchanged after Holdings ingest |
| TP-5.3 | Re-upload Holdings | Previous Holdings Silver replaced |
| TP-5.4 | Holdings without BH | No error, Holdings Silver created |

## TP-6: Portfolio.build — Holdings Source (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Holdings exists → reads holdings table | Data matches stock_plan_holdings |
| TP-6.2 | No Holdings → falls back to BH | Data from stock_plan_tranches |
| TP-6.3 | Hierarchical structure | Same shape from both sources |
| TP-6.4 | ESPP cost_basis = FMV | Not discounted price |
| TP-6.5 | RSU sellable_qty = 0 not shown | Fully sold vests excluded |
| TP-6.6 | UNVESTED rows included | vest_quantity shown |

## TP-7: Multi-User Verification (Manual Browser)

| Test ID | User | Scenario | Assertion |
|---|---|---|---|
| TP-7.1 | User 1 | BH only, all sold | Empty portfolio (BH fallback, sold excluded) |
| TP-7.2 | User 2 | BH + Holdings (RSU, no Sellable Shares) | RSU vested with sellable_qty=0 excluded, unvested shown |
| TP-7.3 | User 3 | BH + Holdings (ESPP + RSU) | Both sections with correct data from Holdings |
| TP-7.4 | User 3 | ESPP cost basis | Shows FMV, not discounted price |
| TP-7.5 | User 3 | INR toggle | Values convert with FX rates |
| TP-7.6 | — | Holdings only (no BH) | Portfolio works, no crash |
| TP-7.7 | — | No uploads | Empty portfolio with upload prompt |

## TP-8: Data Anomaly Detection (Automated)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.1 | BH fallback: sold > vested | Warning logged, origin flagged |
| TP-8.2 | BH fallback: sold == vested | Origin excluded from portfolio |
| TP-8.3 | BH fallback: sold < vested | available = vested - sold |

---

## Test Approach

- TP-1 through TP-6, TP-8: Automated (DataCase)
- TP-7: Manual browser testing with real sample data per user
- Sample data: SampleUser-1 (all sold), SampleUser-2 (RSU no Sellable), SampleUser-3 (ESPP+RSU)

## Test Count: ~45 (35 automated, ~10 manual)
