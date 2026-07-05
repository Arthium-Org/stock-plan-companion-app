# Tasks: M7b — Stock Price Service ✓ DONE

All tasks completed.

- [x] Schema: `vest_day_close` (SafeDecimal, nullable) added to tranches
- [x] Yahoo Finance client: `lib/stock_plan/stock_price/yahoo.ex` — historical + current
- [x] Service: `StockPlan.StockPrice.get_close/2`, `get_close_range/3`, `current_price/1` with ETS cache
- [x] Silver Builder Phase 4: fills vest_day_close on all VESTED tranches
- [x] Tests: 6 external tests (excluded from default run)
- [x] Dependency: `req ~> 0.5` for HTTP client
