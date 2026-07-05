# Test Plan: M25 — Multi-Symbol Sell Advisor

## Fixtures

- **SU5** (`docs/Sample-Data/SampleUser - 5/`) — multi-symbol baseline: ADBE BH, CRM BH, CRM Holdings, G&L Expanded.
- **SU1** — single-symbol regression check: v2 paths must remain green.

---

## Unit tests — `test/stock_plan/tax/sell_advisor_multi_test.exs`

### Input validation

| Test | Setup | Expectation |
|---|---|---|
| Rejects `:shares` target | held = [ADBE, CRM] | `{:error, :shares_requires_symbol}` |
| Rejects `:harvest` target | held = [ADBE, CRM] | `{:error, :harvest_not_supported}` |
| Rejects single-symbol account | held = [ADBE] | `{:error, :single_symbol_use_v2}` |
| Rejects target ≤ 0 | held = [ADBE, CRM], target `{:inr, 0}` | `{:error, :invalid_target}` |

### Lot enrichment

| Test | Expectation |
|---|---|
| Each enriched lot uses its own symbol's price | `lot.current_price == prices[lot.symbol]` for all lots |
| Lots without `prices[lot.symbol]` are excluded | Excluded count surfaced in `warnings` |

### Stage 1 (offset)

| Scenario | Expectation |
|---|---|
| FY baseline STCG > 0, STCL lots available | Stage 1 picks STCL lots until offset reached |
| FY baseline LTCG > 0, LTCL lots available | Stage 1 picks LTCL lots until offset reached |
| No baseline gains | Stage 1 returns `[]` |
| Stage 1 spans symbols | `committed_keys` contains tuples from each contributing symbol |

### Stage 2 — fill-by-value

| Scenario | Expectation |
|---|---|
| Target reachable from one symbol's lots | `order_count == 1`; basket uses only that symbol |
| Target requires both symbols | `order_count == 2`; basket has entries from both |
| Two equally-tax-optimal plans (one-symbol vs two-symbol) | Engine picks one-symbol solution (lower order_count score) |
| Partial lot needed at the end | Last entry has `qty_to_sell < lot.sellable_qty` |
| Overshoot minimized | `basket_value ≥ target_value` but not by more than the smallest available lot's value |

### Cross-engine parity

| Scenario | Expectation |
|---|---|
| User holds only ADBE; run Multi on synthetic 2-symbol fixture with one having zero lots | Output matches v2's single-symbol answer within ₹1 |

### Tax math

| Scenario | Expectation |
|---|---|
| STCG/LTCG aggregation in `tax_summary` | Symbol-agnostic; same totals whether ADBE/CRM lots intermix or are separate |
| FY baseline application | Same as v2 — baseline subtracts before STCG/LTCG charge calc |

### Output structure

| Scenario | Expectation |
|---|---|
| `by_symbol_plan_type` keys | All `{symbol, plan_type}` tuples present in entries |
| `by_plan_type` keys | Only `plan_type` strings; symbol erased |
| `order_count == map_size(by_symbol_plan_type)` | Always |
| `total_qty` present but labeled non-meaningful in moduledoc | Always |

### CSV export

| Scenario | Expectation |
|---|---|
| Columns | Same as v1 + `Symbol` |
| Row order | Sorted by `(symbol, plan_type, vest_date)` |
| Contiguous-by-order | Each `{symbol, plan_type}` group is contiguous in CSV |

---

## LiveView tests — `test/stock_plan_web/live/sell_advisor_live_test.exs`

| Test | Setup | Assertion |
|---|---|---|
| Selector hidden when 1 held symbol | SU1 ingestion | HTML does not contain `"All symbols"` option |
| Selector present + defaults to "All symbols" when ≥ 2 | SU5 ingestion | `<option value="ALL" selected>` present |
| "Shares" radio disabled when "All symbols" active | SU5 + default | Radio has `disabled` attribute |
| Submitting INR target with "All symbols" calls Multi engine | SU5 + INR ₹X target | Result HTML contains `"Order: ADBE — RSU"` or similar per-order block |
| Picking specific symbol calls v2 | SU5, select ADBE | Result HTML matches existing v2 single-symbol rendering |
| CSV download with multi result has Symbol column | SU5 + INR target | First CSV line contains `Symbol,` |

---

## Regression tests

- All existing tests in `test/stock_plan/tax/sell_advisor_test.exs` pass unchanged.
- v2 tests pass unchanged.
- Portfolio + Tax Centre LiveView tests pass unchanged.

---

## Manual test scenarios

Before declaring M25 done, walk through these on the running dev server:

1. **Pure SU5 dataset** (`mix ecto.reset` + upload all 4 SU5 files):
   - `/sell` page shows "All symbols" selector defaulted.
   - Enter ₹5,00,000 target → expect a basket spanning both symbols if neither alone covers it.
   - Switch dropdown to ADBE only → existing v2 page renders.
   - Switch back to "All symbols" → multi page renders again.

2. **CSV export** — download from multi result, open in Excel, confirm Symbol column present and rows grouped by symbol.

3. **Edge case — one symbol has no sellable lots** — confirm engine handles silently (no crash, no entries from that symbol, no `{symbol, _}` key in `by_symbol_plan_type`).

4. **Edge case — FY baseline alone covers target** — confirm warning message displayed and Stage 2 skipped.

---

## Performance budget

The multi engine runs greedy fill over ~100–500 lots typical. Target: `advise/3` returns in < 200ms on dev hardware. No DB queries in tight loops — all lots loaded once up front.
