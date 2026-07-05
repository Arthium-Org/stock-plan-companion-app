# Test Plan: M22 — Multi-Symbol Support

## Test surface

| Module | What we test |
|---|---|
| `StockPlan.StockMeta` | Lookup behavior, error on unknown symbol, lazy load + cache |
| `StockPlan.Portfolio.user_symbols/1` | Returns distinct list, scoped to active ingestion |
| `StockPlan.Portfolio.symbol_summaries/2` | Correct totals per symbol in USD + INR |
| `StockPlan.Ingestions.extract_file_symbol/1` | Extracts symbol from BH/Holdings row data; errors gracefully on missing |
| `StockPlan.Ingestions.active_bh/2` + `active_holdings/2` | Returns the ACTIVE row for a given symbol or nil |
| `StockPlan.Ingestions.active_bh_symbols/1` + `active_holdings_symbols/1` | Distinct ACTIVE symbols, sorted |
| `StockPlan.Ingestions.any_active_bh?/1` | Boolean shorthand; preserves `validate_active_bh/1` semantics |
| `StockPlan.Portfolio.held_symbols/1` | Currently-held only; User5: returns `["CRM"]` |
| `StockPlan.Portfolio.owned_symbols/1` | All time; User5: returns `["ADBE", "CRM"]` |
| `UploadChecks.check_symbol_consistency/1` | Produces `:bh_without_holdings` (`:info`) and `:holdings_without_bh` (`:warning`) nudges |
| `StockPlan.Ingestions.archive_previous_bh/2` | Scoped to the given symbol — does NOT touch other symbols' ACTIVE rows |
| `StockPlan.Ingestions.archive_previous_holdings/2` | Same scoping behavior |
| `StockPlan.Tax.ScheduleFA.build/2` | Emits per-symbol rows, errors on missing metadata |
| `StockPlan.Tax.ScheduleFA.row_to_csv/1` | Pulls fields from metadata, not hardcoded |
| `SellAdvisorLive` | Symbol selector switches scope; only lots of selected symbol used |
| `PortfolioLive` | Per-symbol header when >1; collapse to inline when 1 |
| `TaxCentreLive` | Stacked per-symbol blocks + combined CSV |
| `UploadLive` | Per-file status line includes detected symbol for BH/Holdings |

---

## Unit tests

### StockMeta

```
1. get/1 known symbol returns full struct
2. get/1 unknown symbol returns {:error, :unknown_symbol}
3. get!/1 known symbol returns struct
4. get!/1 unknown symbol raises
5. known?/1 returns true/false correctly
6. all/0 returns full map of all symbols in priv/stock_meta.json
7. Lazy load: persistent_term not set before first call (verify with :persistent_term.get fallback)
8. Cache: second call doesn't re-read file (mock File.read! to assert called once)
```

### Portfolio.user_symbols/1

```
1. Empty DB → []
2. Single-symbol DB (ADBE only) → ["ADBE"]
3. Multi-symbol DB → all distinct symbols, sorted alphabetically
4. Archived ingestions ignored (returns only ACTIVE ingestion's symbols)
5. Symbols with only sales (no origins) still included (defensive — unlikely but possible)
```

### Portfolio.symbol_summaries/2

```
1. Single symbol: returns 1 summary with correct held_qty, cost_basis_usd/inr, value_usd/inr, pnl
2. Multi-symbol: returns N summaries, each with correct per-symbol totals (no cross-contamination)
3. Cost basis uses event-time FX (existing behavior, just verify per-symbol)
4. Current value uses passed-in current_prices map (key by symbol)
5. P&L = value - cost_basis per symbol
6. INR values use current FX (existing)
```

### ScheduleFA.build/2 — missing metadata

```
1. All symbols have metadata → returns {:ok, rows, warnings}
2. One symbol missing → returns {:error, {:missing_meta, ["XYZ"]}}
3. Multiple symbols missing → returns {:error, {:missing_meta, ["XYZ", "ABC"]}} sorted
4. No active data at all → existing empty-case behavior unchanged
```

### ScheduleFA.row_to_csv/1

```
1. Row with ADBE → CSV contains "Adobe Inc.(ADBE)", "345 Park Ave...", "95110", "United States of America", "2", "Company"
2. Row with MSFT (test fixture) → CSV contains MSFT metadata correctly
3. Row with unknown symbol → raises (caller's responsibility to pre-validate; this is the unsafe path)
```

---

## LiveView tests

### PortfolioLive

```
1. Single-symbol user: page renders without per-symbol tile row; existing layout preserved
2. Multi-symbol user: per-symbol tile row visible with one tile per symbol
3. Each tile shows: symbol, held qty, value, P&L (USD + INR if toggle is on)
4. Currency toggle preserves per-symbol breakdown
5. No row of any grant displays "Adobe (ADBE)" hardcoded; instead displays row.symbol → display_name lookup
6. Current price lookup: each row uses prices[row.symbol]
```

### SellAdvisorLive

```
1. User with 1 symbol: selector hidden, behavior identical to pre-M22
2. User with 2 symbols: selector visible, defaults to symbol with most held shares
3. Switching selector triggers re-pick of lots scoped to new symbol
4. Suggested-lot list never mixes symbols
5. Total proceeds / tax calc all in selected symbol's current price
```

### TaxCentreLive

```
1. Single symbol: Schedule FA tab shows current layout (no per-symbol header)
2. Multi-symbol: Schedule FA tab shows stacked blocks, one per symbol with symbol+name header
3. "Download Combined CSV" emits rows from all symbols concatenated
4. Missing-metadata case: red error callout names the symbol(s) and points to priv/stock_meta.json
5. Schedule FSI: per-symbol breakdown when applicable
6. Capital Gains: rows include symbol column (verify present)
```

---

## Integration tests

### Per-symbol BH ingestion (SampleUser-5)

```
1. Setup: empty DB
2. Ingest BenefitHistory.xlsx (ADBE) → ACTIVE BH row with dominant_symbol="ADBE"
3. Ingest BenefitHistory (1).xlsx (CRM) → ACTIVE BH row with dominant_symbol="CRM"
4. Assert both BH rows are ACTIVE
5. Silver: origins for both symbols present
```

### Per-symbol archive doesn't cross symbols

```
1. Setup: ACTIVE BH for both ADBE and CRM
2. Re-ingest ADBE BH (different file hash)
3. Assert ADBE BH archived (status="ARCHIVED"); CRM BH still ACTIVE
4. Silver still has both symbols' origins
```

### Holdings asymmetry (BH without Holdings)

```
1. Setup: ADBE BH only (no Holdings) + CRM BH + CRM Holdings
2. Portfolio.held_symbols → ["CRM"]                      # NOT ADBE
3. Portfolio.owned_symbols → ["ADBE", "CRM"]             # BOTH
4. Portfolio page renders CRM tile only
5. History page renders tabs for ADBE + CRM + Combined
6. Schedule FA build for a CY where ADBE was sold → includes ADBE rows
7. UploadChecks emits one :bh_without_holdings nudge for ADBE (severity :info)
8. No exceptions, no NULL errors anywhere
```

### Cross-file symbol consistency

```
1. Setup: BH for ADBE + BH for CRM + Holdings for MSFT only (user mistakenly uploaded wrong file)
2. UploadChecks.check produces 3 nudges:
   - :bh_without_holdings for ADBE (:info)
   - :bh_without_holdings for CRM   (:info)
   - :holdings_without_bh for MSFT  (:warning)
3. Severity asymmetry: Holdings-without-BH is :warning, BH-without-Holdings is :info
4. None of these block the upload
```

### End-to-end multi-symbol flow

```
1. Setup: write a Bronze fixture with origins for both ADBE and MSFT
2. Run Silver build
3. Assert Silver origins have 2 distinct symbols
4. Run Portfolio.user_symbols → ["ADBE", "MSFT"]
5. Run Portfolio.symbol_summaries → 2 entries with non-zero totals each
6. Run ScheduleFA.build → {:ok, rows, []} with rows for both symbols
7. Verify CSV output contains 2 blocks (one per symbol) with correct metadata
```

### Sell Advisor switches correctly

```
1. Multi-symbol fixture
2. Mount SellAdvisorLive
3. Assert default @symbol = symbol with most held shares
4. send_event(:select_symbol, %{symbol: other_symbol})
5. Assert socket.assigns.symbol updated
6. Assert filtered lots reflect new symbol
```

---

## Manual verification

### Single-symbol install (regression check)

- [ ] Existing user's DB (ADBE only) — Portfolio page renders identically to pre-M22
- [ ] Sell Advisor: no selector visible
- [ ] Tax Centre: single block, no per-symbol header
- [ ] Schedule FA CSV identical to pre-M22 output for the same data

### Multi-symbol new install

- [ ] Synthetic fixture or real test data with ADBE + MSFT
- [ ] Portfolio: 2 summary tiles visible, totals correct per tile
- [ ] Sell Advisor: dropdown shows both, switching works
- [ ] Tax Centre: 2 blocks visible in Schedule FA, Combined CSV downloads
- [ ] Manually inspect CSV: ADBE rows have Adobe legal name/address, MSFT rows have Microsoft

### Missing metadata error path

- [ ] Forge a Silver row with `symbol = "UNKNOWN"` (or upload a real file with unsupported symbol)
- [ ] Tax Centre → Schedule FA tab → red callout: "Missing metadata for UNKNOWN. Add to priv/stock_meta.json before generating Schedule FA."
- [ ] CSV download disabled / errors out cleanly

---

## Non-functional checks

- [ ] `mix compile --warnings-as-errors` — 0 warnings
- [ ] `mix test` — all pass (target: prev 457 + ~15 new = ~470)
- [ ] No new dialyzer warnings (if dialyzer is set up)
- [ ] Stock price API call count: N times existing (where N = symbol count). Verify cache hit rate stays high (15-min TTL still effective).

---

## Risks

| Risk | Mitigation |
|---|---|
| User holds a symbol we don't have metadata for | Hard error with clear message + remediation; don't silently emit broken CSV |
| Yahoo Finance rate-limits when fetching N symbols | 15-min cache already covers; revisit if real users hit limits |
| UI clutter when many symbols (5+) | Initial design is for 1-5; if a real user has more, iterate then |
| Existing ADBE-only install breaks on upgrade | Test explicitly; metadata for ADBE ships in priv/, no DB migration |
