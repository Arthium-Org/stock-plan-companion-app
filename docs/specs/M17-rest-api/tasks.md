# Tasks: M17 — REST API

## Milestone 1: API Pipeline + Auth

- [ ] 1.1 Add `:api` pipeline to router (json content type)
- [ ] 1.2 Create `StockPlanWeb.API.AuthPlug` — API key auth
- [ ] 1.3 Add API key to config (`config :stock_plan, :api_key`)
- [ ] 1.4 Add CORS plug (corsica or custom)
- [ ] 1.5 Add `/api` scope to router

## Milestone 2: Portfolio API

- [ ] 2.1 Create `StockPlanWeb.API.PortfolioController`
- [ ] 2.2 `GET /api/portfolio` — hierarchical holdings JSON
- [ ] 2.3 `GET /api/portfolio/summary` — summary cards data
- [ ] 2.4 Decimal serialization (strings, not floats)
- [ ] 2.5 Write tests
- [ ] 2.6 `mix test` — pass

## Milestone 3: Tax API

- [ ] 3.1 Create `StockPlanWeb.API.TaxController`
- [ ] 3.2 `GET /api/tax/schedule-fa?year=YYYY` — FA rows JSON
- [ ] 3.3 `GET /api/tax/schedule-fa/download?year=YYYY` — CSV download
- [ ] 3.4 `GET /api/tax/capital-gains?fy=YYYY` — CG rows + summary
- [ ] 3.5 Write tests
- [ ] 3.6 `mix test` — pass

## Milestone 4: Sell Advisor API

- [ ] 4.1 Create `StockPlanWeb.API.SellController`
- [ ] 4.2 `POST /api/sell/advise` — baskets JSON
- [ ] 4.3 Input validation (mode, amount)
- [ ] 4.4 Write tests
- [ ] 4.5 `mix test` — pass

## Milestone 5: Market Data + Upload API

- [ ] 5.1 Create `StockPlanWeb.API.MarketController`
- [ ] 5.2 `GET /api/price/current` — current price + FX
- [ ] 5.3 Create `StockPlanWeb.API.UploadController`
- [ ] 5.4 `POST /api/upload/benefit-history` — multipart upload
- [ ] 5.5 `POST /api/upload/gl-expanded`
- [ ] 5.6 `POST /api/upload/holdings`
- [ ] 5.7 Write tests
- [ ] 5.8 `mix test` — pass

## Milestone 6: Verification

- [ ] 6.1 `mix format --check-formatted`
- [ ] 6.2 `mix compile --warnings-as-errors`
- [ ] 6.3 `mix test` — all pass
- [ ] 6.4 Manual: curl all endpoints
- [ ] 6.5 Manual: test auth (valid key, invalid key, no key)
- [ ] 6.6 Manual: test CORS headers

## Definition of Done

- [ ] All API endpoints return valid JSON
- [ ] API key auth works
- [ ] CORS configured
- [ ] Decimals serialized as strings
- [ ] File upload via API works
- [ ] All tests pass
