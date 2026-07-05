# Execution Plan — Stock Plan Manager (Phase 1)

## Overview

Phase 1 delivers: XLSX ingestion (Benefit History + G&L Expanded), Bronze/Silver pipeline, and LiveView screens (upload, portfolio, income, vesting timeline) with USD + INR support.

Modules are ordered by dependency. Each module has specs (requirements, design, tasks, test-plan) reviewed before implementation. TDD throughout.

---

## Module Dependency Graph

```
M1: Scaffold                                              ✓ DONE
 └─> M2: Data Layer (7 tables, types, migrations)          ✓ DONE
      ├─> M3: Benefit History XLSX Parser (Bronze structs)  ✓ DONE
      │    └─> M4: Bronze Writer (Bronze structs -> DB)     ✓ DONE
      │         └─> M5: Silver Builder (Bronze -> origins + tranches + sales)  ✓ DONE
      │              └─> M6: G&L Expanded Ingestion (Bronze + Silver enrichment)  ✓ DONE
      │                   ├─> M7a: FX Rate Service (SBI TT Buying Rate, month-end)  ✓ DONE
      │                   ├─> M7b: Stock Price Service (Yahoo Finance, vest_day_close)  ✓ DONE
      │                   └─> M8: Ingestion Orchestrator (ties everything)  ✓ DONE
      │                        └─> M9: Upload UI (LiveView)  ✓ DONE
      │                             └─> M3b: Holdings Bronze Ingestion  ✓ DONE
      │                                  └─> M5b: Holdings Silver (own table)  ← NEXT
      │                                       └─> M10: Portfolio View (Holdings-sourced)  ← REWRITE
      │                                            └─> M10-UX: Portfolio UX Polish
      │                                                 └─> DHF: Data Handling Fixes
      │                                                      └─> DV: Data Validation Guardrails
      │
      ├─> M14: Tax Centre — Schedule FA (CY) + Capital Gains (FY)
      │    └─> M14b: Schedule FSI, TR, Form 67 (Future)
      │
      └─> M13: CLI Tasks (mix stock_plan.ingest, mix stock_plan.rebuild)
           (can be built any time after M8)

Future pages:
  /history   — Benefits History (lifetime stats, transaction log, income charts — uses BH)
```

**Silver architecture:**
- BH Silver Builder: 4 phases (BH → G&L → FX → Stock Prices) → stock_plan_origins/tranches/sales
- Holdings Silver Builder: separate builder → stock_plan_holdings (new table)
- Portfolio reads from Holdings Silver when available, falls back to BH Silver

**Data source → page mapping:**
| Data Source | Silver Table | Feeds Into |
|---|---|---|
| Holdings (ByBenefitType) | `stock_plan_holdings` | Portfolio page (sole source) |
| Benefits History | `stock_plan_origins/tranches/sales` | Tax Centre, History, Portfolio fallback |
| G&L Expanded | Enriches BH Silver (sale_allocations) | Tax Centre (capital gains) |

---

## Completed Modules

### M1: Project Scaffold ✓

Phoenix 1.8, SQLite, Bandit on port 4002, Tailwind v4, LiveView, CI workflow.

### M2: Data Layer ✓

7 tables: ingestions, bronze_raw, origins, tranches, exercises, sales, sale_allocations.
SafeDecimal, ID generator, FK enforcement, context stubs. 
Schema: lifecycle-driven (origins → tranches → exercises → sales → allocations).

### M3: Benefit History XLSX Parser ✓

Pure parser: 3 sheets (ESPP, Restricted Stock, Options) → BronzeRow structs.
Parent-child linking via parent_index. Deterministic JSON + SHA256 hash.
531 rows from SampleUser-1, 514 from SampleUser-2.

### M4: Bronze Writer ✓

`insert_all` with `on_conflict: :nothing`. Validates ACTIVE ingestion.
parent_index persisted. Idempotent (re-write = 0 inserted, N skipped).

### M5: Silver Builder ✓

Bronze → Silver transformation. RSU: origins + tranches (vest/release pairing).
ESPP: enrollment grouping → origins + purchase tranches + sales + allocations.
RSU sales created without allocations (lot linkage from G&L). 
ESOP: stub (no sample data). Rebuild: DELETE + INSERT, idempotent.

### M6: G&L Expanded Ingestion ✓

G&L_Expanded XLSX through Bronze pipeline. Silver Builder Phase 2: enriches vest_fmv, sale_price, creates RSU sale_allocations. Multiple G&L files per tax year. Sale matching by Order Number. Fill-only overwrite rules. 63 RSU allocations from 3 years of G&L data.

### M7a: FX Rate Service ✓

333 monthly USD/INR rates (Aug 1998 – Apr 2026). Three rate fields: TT Buy month-end (2020+), RBI reference month-end (1998+), x-rates monthly avg (2016+). Previous-month lookup rule per Indian tax law. Silver Builder Phase 3: fills origin_fx_rate, vest_fx_rate, sale_fx_rate.

### M7b: Stock Price Service ✓

Yahoo Finance historical adjusted close → vest_day_close on tranches. Current price with 15-min ETS cache. Silver Builder Phase 4: fills vest_day_close on all VESTED tranches. Separate from vest_fmv (G&L actual).

### M8: Ingestion Orchestrator ✓

Single-call API: `ingest_benefit_history/2`, `ingest_gl/2`, `rebuild/1`. Parse outside transaction, DB ops atomic. Streaming file hash. Duplicate detection. Archives previous BH on new upload.

### M9: Upload UI ✓

LiveView upload page. Two areas: BH + G&L. Async pipeline (Task.start_link). Processing spinner, error messages, upload history table. Drag-and-drop + file picker.

### M10: Portfolio View (partial — pending rewrite)

Current holdings only (vested-unsold + unvested). Summary cards: Total / Current / Potential (E*Trade style). Grouped by type or status. Filters: vested/unvested, profit/loss. Sorting. USD/INR toggle. FMV source indicator. ESPP sold-qty aggregation fix applied.

**Pending rewrite:** Portfolio currently reads from BH-derived data (sale_allocations for available qty). Must be rewritten to use Holdings (ByBenefitType) as sole data source after M3b completes. sellable_qty + cost_basis_broker from broker snapshot replaces derived logic.

---

## M3b: Holdings Bronze Ingestion ✓

**Goal:** Ingest E*Trade ByBenefitType_expanded XLSX — the broker's point-in-time snapshot of current holdings. This is the **sole data source for the Portfolio page**.

**Why this matters:** Portfolio accuracy. Instead of deriving sold quantities from sale_allocations (which requires G&L for lot linkage and can't handle partial sells correctly), the broker directly reports what's sellable + broker-calculated cost basis.

**Scope:**
- Holdings XLSX Parser → BronzeRow structs (sheet_name: "Holdings_ESPP" + "Holdings_RSU")
- New ingestion category: `"HOLDINGS"` — coexists with BH + G&L
- New tranche fields: `sellable_qty`, `cost_basis_broker`, `tax_status`
- Silver Builder Phase 5: match by grant_number + vest_date, update tranches
- Portfolio reads from these enriched fields (not from sale_allocations)

**Inputs:** M3 (parser pattern), M4 (Bronze Writer), M5 (Silver Builder), M8 (Orchestrator)
**Outputs:** Tranches enriched with broker-reported sellable_qty + cost_basis → Portfolio page

**Key decisions:**
- Holdings is supplementary — does not archive BH or G&L
- Holdings is a snapshot (point-in-time) — overwrite, not fill-only
- ESPP + RSU sheets (SampleUser-3 has both)
- No Holdings = empty Portfolio page (system doesn't guess)

---

## M7a: FX Rate Service ✓

**Goal:** SBI TT Buying Rates for USD/INR conversion per Indian tax law. Rate = TT buying rate on last day of month BEFORE transaction month.

**Scope:**
- `stock_plan_fx_month_end_rates` table (master data — one row per month)
- `StockPlan.FX.get_rate(date)` → looks up previous month's rate
- Scraper: fetches from SBI Forex Rates API (`sbi-forex-rates-api.vercel.app`)
- Mix task: `mix stock_plan.fetch_fx_rates --from 2015-01 --to 2025-12`
- Silver Builder Phase 3: fills origin_fx_rate, vest_fx_rate, sale_fx_rate

**Inputs:** M5/M6 (Silver data to enrich)
**Outputs:** FX rates on all Silver records, scraper for historical rates

---

## M7b: Stock Price Service ✓

**Goal:** Historical and current stock prices from Yahoo Finance. Historical close stored as `vest_day_close` on tranches (fallback for missing vest_fmv). Current price for live portfolio valuation.

**Scope:**
- `vest_day_close` field added to tranches (Yahoo adjusted close on vest date)
- `StockPlan.StockPrice.get_close(symbol, date)` → historical close
- `StockPlan.StockPrice.current_price(symbol)` → live price (cached 15 min)
- Silver Builder Phase 4: fills vest_day_close on VESTED tranches

**Inputs:** M5/M6 (Silver data to enrich)
**Outputs:** Stock prices on tranches, live price for UI

---

## M8: Ingestion Orchestrator

**Goal:** End-to-end pipeline: upload file → create ingestion → Bronze → Silver.

**Scope:**
- `create_ingestion/2` — generate ingestion_id, manage ACTIVE status
- `run_benefit_history_pipeline/2` — parse Benefit History XLSX → Bronze → Silver rebuild
- `run_gl_pipeline/2` — parse G&L XLSX → Bronze → Silver rebuild (incorporates G&L)
- File hash check (warn on re-upload of same file)
- Rebuild support: `rebuild/1` — delete Silver, rebuild from ALL Bronze sources

**Inputs:** M3-M6 (all pipeline components)
**Outputs:** Full pipeline works end-to-end

**Key decisions:**
- Benefit History upload archives previous ACTIVE Benefit History ingestion
- G&L uploads are additive (multiple per account, one per tax year)
- Rebuild processes: Benefit History Bronze first → G&L Bronze second
- New Benefit History upload triggers full rebuild (re-applies existing G&L data)

---

## M9: Upload UI

**Goal:** Web UI for uploading Benefit History and G&L XLSX files.

**Scope:**
- LiveView file upload (drag-and-drop + file picker)
- Two upload types: "Benefit History" and "G&L Expanded (Tax Year)"
- Show upload progress, pipeline status, summary (origins/tranches/sales counts)
- Warn on re-upload of same file (file_hash match)
- Route: `GET /upload`

---

## M5b: Holdings Silver (NEXT)

**Goal:** Holdings gets its own Silver table (`stock_plan_holdings`), independent of BH Silver. Portfolio reads from it.

**Why:** Phase 5 enrichment of BH tranches doesn't work — Holdings must be self-contained. Users without BH, or with incomplete G&L, get wrong Portfolio data under the enrichment model.

**Scope:**
- New table: `stock_plan_holdings` — one row per vest period (RSU) or purchase (ESPP)
- New builder: `HoldingsSilverBuilder` — reads Holdings Bronze, creates Holdings Silver
- FX enrichment on Holdings Silver rows
- Portfolio.build reads from Holdings Silver when available, falls back to BH
- Phase 5 removed from BH Silver Builder

**Specs:** `docs/specs/M5b-holdings-silver/` (requirements, design, tasks, test-plan)

---

## M10: Portfolio View (Partial — pending M5b)

**Goal:** Per-grant portfolio breakdown with USD + INR toggle. **Reads from Holdings Silver only.**

**Current state:** Hierarchical UI built (collapsible grants, tabs, filters, formatting). Reads from BH-enriched tranches. Must be rewired to read from `stock_plan_holdings` after M5b.

**Pending:**
- M10 rewrite: Portfolio.build reads from Holdings Silver
- M10-UX: tranche visual separation, sorting
- DHF: origin-level sold calculation for BH fallback
- DV: data validation guardrails

---

## M11: Income View

**Goal:** Realized income per grant, per tax year.

**Scope:**
- RSU: vest income = vest_fmv × vest_qty
- ESPP: discount income = (purchase_date_fmv - buy_price) × qty
- Filter by tax year, plan_type
- USD/INR toggle
- Route: `GET /income`

---

## M12: Vesting Timeline View

**Goal:** Upcoming vests with projected values.

**Scope:**
- UNVESTED tranches with future vest_dates
- Table: vest_date, grant_number, plan_type, quantity
- Sort by vest_date ascending
- Route: `GET /timeline`

---

## M13: CLI Tasks

**Goal:** Mix tasks for non-UI operations.

**Scope:**
- `mix stock_plan.ingest_benefit_history <file_path>` — Benefit History pipeline
- `mix stock_plan.ingest_gl <file_path>` — G&L Expanded pipeline
- `mix stock_plan.rebuild` — rebuild Silver from all Bronze
- All invoke the ingestion orchestrator (M8)

---

## Suggested Implementation Order

| Step | Module | Status | What you get |
|---|---|---|---|
| 1 | M1: Scaffold | ✓ Done | Bootable app |
| 2 | M2: Data Layer | ✓ Done | 7 tables, schemas, SafeDecimal |
| 3 | M3: XLSX Parser | ✓ Done | Parse Benefit History in tests |
| 4 | M4: Bronze Writer | ✓ Done | Bronze rows in DB |
| 5 | M5: Silver Builder | ✓ Done | Origins + tranches + sales from Bronze |
| 6 | M6: G&L Ingestion | ✓ Done | vest_fmv, sale prices, RSU allocations |
| 7a | M7a: FX Rate Service | ✓ Done | SBI TT buying rates, 333 monthly rates, INR conversion |
| 7b | M7b: Stock Price Service | ✓ Done | Yahoo Finance, vest_day_close, current price cache |
| 8 | M8: Orchestrator | ✓ Done | End-to-end pipeline, one-call API |
| 9 | M9: Upload UI | ✓ Done | Web upload (BH + G&L + Holdings), async pipeline |
| 10 | M3b: Holdings Bronze | ✓ Done | ByBenefitType XLSX → Bronze rows, parser, dedup headers |
| 11 | M10: Portfolio View | ✓ Partial | Hierarchical UI with collapsible grants, tabs, filters |
| 12 | **M5b: Holdings Silver** | **Next** | Own `stock_plan_holdings` table, independent of BH |
| 13 | **M10: Portfolio Rewrite** | **After M5b** | Portfolio reads from Holdings Silver, BH fallback |
| 14 | M10-UX: Portfolio UX Polish | After M10 | Tranche indentation, sorting, visual fixes |
| 15 | DHF: Data Handling Fixes | After M10-UX | Origin-level sold calc, multi-user data correctness |
| 16 | DV: Data Validation | After DHF | Guardrails (ERROR/WARNING/INFO), data health UI |
| 17 | **M14: Tax Centre (Phase 1)** | **Specced** | Schedule FA (CY, CSV) + Capital Gains (FY, STCG/LTCG) |
| 18 | M13: CLI Tasks | | `mix stock_plan.ingest` works |
| 19 | **M19: Desktop Executable** | **Specced — Phase 1 closer** | Mac app, single binary, auto-start |
| — | M16: PWA | Specced | Installable web app on iOS + Android |
| — | M17: REST API | Specced | JSON API for mobile app consumption |
| — | M18: Mobile App | Specced | React Native (Expo) — iOS + Android |
| 20 | **M14b: Schedule FSI** | **Specced — Phase 1** | Foreign Source Income declaration (FY) |
| 21 | **M21: Tranche Timeline** | **Specced — Phase 1** | Per-tranche state at any date, data validation, Schedule FA fix |
| — | M14c: Schedule TR | Future | Tax Relief — when dividend-paying company data available |
| — | M20: Historical Analysis | Future | ESPP returns (XIRR), RSU income growth charts |
| — | Benefits History | Future | Lifetime stats, transaction log |

Steps 1-18 done. **M19 (Desktop Executable) = Phase 1 closer.** Mobile path (M16→M17→M18) specced for Phase 2.

---

## Phase 2 Modules (Future)

- Trade Confirmation PDF Parser (sell event details)
- Tax Engine (income tax, capital gains STCG/LTCG, ESPP qualification rules)
- Sell Guidance (tax-optimal lot selection)
- ITR Document Generation (Schedule FA, FSI, capital gains)
- Company Details (for Schedule FA)
- Multi-broker (Morgan Stanley, Schwab, Fidelity)
