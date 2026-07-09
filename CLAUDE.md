# CLAUDE.md — Stock Plan Manager

## Access Restriction

- **Do not read, write, or execute files outside of this project's working directory (the directory containing this `CLAUDE.md`) even in `--dangerously-skip-permissions` mode. Ask for permission.**

## Review Discipline

- **Review all external feedback (GPT or otherwise) on merit.** Do not accept blindly. Evaluate each suggestion for: correctness, relevance to current scope, and whether it adds value vs complexity.
- **Always provide Accept/Reject summary FIRST.** Before making any changes, list each feedback item with Accept or Reject and a one-line justification. Then proceed to update specs/code. Never skip the summary.
- **Decline with justification** when a suggestion is over-engineering, premature optimization, already handled, or out of scope. State why.
- **Accept when genuinely needed** — correctness fixes, clarity improvements, missing edge cases.
- **Never add complexity for hypothetical future requirements.** Build for what's needed now.
- **No guessing.** Every explanation must be based on verified facts — check the data, read the code, run a query. Do not speculate about root causes or assume what data exists/doesn't exist. If unsure, investigate first, then explain.

## Implementation Discipline

- **Do NOT implement fixes or features without proper specs or user approval.** When a bug or gap is found, propose the approach first — do not rush to code.
- **Never invent financial truth.** If data is missing (e.g., which lot was sold), show "unknown" or aggregate — do NOT fabricate tranche-level data from origin-level data.
- **Revert bad implementations immediately** when called out. Do not compound the mistake by patching on top.

## Spec Discipline

- **Every milestone MUST have 4 spec files:** requirements.md, design.md, tasks.md, test-plan.md. No exceptions.
- **Always create all 4 files together.** Do not create partial specs and wait to be asked for the rest.

## Project Identity

- **App:** Stock Plan Manager — lightweight stock plan (RSU / ESPP / Stock Options) management
- **Purpose:** Upload E*Trade Benefit History XLSX, view portfolio, income, tax analysis, sell guidance in USD + INR
- **Target users:** Any employee at a US firm receiving ESPP / RSU / Stock Option benefits. Single-tenant — each person runs own instance.
- **Stack:** Elixir + Phoenix 1.8 + LiveView + SQLite (ecto_sqlite3) + Bandit
- **Port:** 4002
- **DB:** SQLite at `tmp/stock_plan_dev.db`
- **Broker:** E*Trade ("Stock Plan" / "At Work") — single broker for now, multi-broker later
- **Future:** Will become a module in a unified wealth management umbrella app

---

## Architecture

```
E*Trade XLSX
     |
Bronze (append-only, raw audit layer)
     |
Silver (rebuildable per ingestion, current truth, FX-enriched)
     |
Gold (derived views, rebuildable, uses Silver FX data)
```

### Layer Responsibilities

| Layer | Mutability | Role |
|---|---|---|
| Bronze | Append-only | Raw source preservation. All uploads retained. Audit + reprocessing. |
| Silver | Rebuild per ACTIVE ingestion | Structured financial truth: grants, events, vesting schedules. FX-enriched (event-time USD/INR rate stored per event). DELETE + INSERT on each rebuild. |
| Gold | Rebuild from Silver | Derived views: portfolio, income, projections. Reads FX data from Silver events to build INR views. Current FX applied dynamically for live valuations only. |

### Key Design Decisions (Locked)

1. **No ledger system.** Medallion-only. Silver = event truth, not a separate ledger abstraction.
2. **Silver is NOT append-only.** Full rebuild allowed. User uploads replace previous data. Bronze is the immutable audit layer.
3. **Bronze != financial truth.** Bronze = source facts (what broker said). Silver = financial interpretation (what actually happened economically).
4. **1 ACTIVE ingestion per account.** New upload archives previous, rebuilds Silver + Gold. Guard rail (future): detect large data drift between uploads (e.g., significant grant count or total quantity change) and warn user before overwriting.
5. **Dual FX model.** Event-time FX stored on Silver events; current FX computed dynamically at Gold/UI.
6. **Income split.** Realized income (vested events) lives in Silver. Projected income has two tiers: (a) projected at Grant FMV and Vest FMV — deterministic, can be stored in Gold; (b) projected at current stock price — must be computed on the fly at UI layer, never stored. Current-price projections are NOT financial facts.
7. **SELL events in schema now.** SELL data ingested from the G&L_Expanded XLSX (sale price, proceeds, fees). Schema supports SELL from day one.
8. **"stock_plan" naming.** Industry standard: E*Trade ("StockPlan Connect"), Fidelity ("Stock Plan Services"), Schwab ("Stock Plan Services") all use "Stock Plan". ESOP is one of three plan types, not the umbrella term. Plan types: `RSU` / `ESPP` / `STOCK_OPTION`.

---

## E*Trade Benefit History XLSX — Source Format

Three sheets with parent-child row patterns. `Record Type` (column A) determines row type.

### Sheet: ESPP (23 columns)

**Parent** (`Record Type = Purchase`):
- Symbol, Purchase Date, Purchase Price, Purchased Qty, Net Shares
- Grant Date, Discount Percent, Grant Date FMV, Purchase Date FMV
- Qualified Plan?, Contribution Source

**Child** (`Record Type = Event`):
- Date (MM/DD/YYYY), Event Type (`PURCHASE` / `SELL`), Qty

### Sheet: Restricted Stock (43 columns)

**Parent** (`Record Type = Grant`):
- Symbol, Grant Date, Granted Qty, Vested Qty, Unvested Qty
- Grant Number (e.g., `RU422478`), Type (`RSU`), Status, Cancelled Qty
- Settlement Type, Award Price, Class

**Child** (`Record Type = Event`):
- Date, Event Type (`Shares released` / `Shares canceled` / `Shares withheld for taxes` / `Shares vested` / `Dividend reinvested`), Qty or Amount
- Tax columns (AH-AQ): Total Taxes Paid, Tax Description, Taxable Gain, Effective Tax Rate, Withholding Amount

**Child** (`Record Type = Vest Schedule`):
- Vest Date, Vesting Qty, Vested Qty, Unvested Qty, Vest Type, Expiration Date

### Sheet: Options (31 columns)

**Parent** (`Record Type = Grant`):
- Symbol, Grant Date, Granted Qty, Exercise Price
- Grant Number (e.g., `EF03554`), Type (`NQ` / `ISO`), Status

**Child** (`Record Type = Event`):
- Date, Event Type (`Shares granted` / `Shares vested` / `Shares exercised`), Qty

**Child** (`Record Type = Vest Schedule`):
- Vest Date, Vesting Qty, Expiration Date, Vest Type

**Totals** (`Record Type = Totals`): Skip during ingestion.

### Parsing Rules

1. `Record Type` column (A) determines row type: Grant/Purchase = parent, Event = child, Vest Schedule = schedule, Totals = skip
2. Child rows belong to the nearest preceding parent row
3. Grant Number links events to specific grants (ESPP has no grant number — use Purchase Date + Symbol as key)
4. Date formats: parent rows = DD-MMM-YYYY (e.g., `24-JAN-2025`), event rows = MM/DD/YYYY (e.g., `01/27/2014`)
5. Some numeric columns have string formatting (e.g., `$72.36`) — strip `$` and `,` during parse
6. Empty/None cells are common — child rows only populate their relevant columns

---

## Data Model

### Lifecycle Flows

```
RSU:   origin (grant)      → tranche (vest)     ────────────→ sale_allocation ← sale
ESPP:  origin (enrollment) → tranche (purchase)  ────────────→ sale_allocation ← sale
ESOP:  origin (grant)      → tranche (vest)      → exercise → sale_allocation ← sale
```

### Lot Sources (what creates sellable shares)

| Plan | Lot Source | Cost Basis | sale_allocation fields |
|---|---|---|---|
| RSU | Vested tranche (post-tax net shares) | vest_fmv | tranche_id set, exercise_id nil |
| ESPP | Purchase tranche (post-tax net shares) | buy_price (in tranche metadata) | tranche_id set, exercise_id nil |
| ESOP | Exercise (bought shares at strike) | exercise_price | tranche_id set, exercise_id set |

### ESPP Origin vs Tranche

| | Origin (enrollment) | Tranche (purchase) |
|---|---|---|
| Date | Grant Date (enrollment start) | Purchase Date |
| FMV | Grant Date FMV (lock-in price) | Purchase Date FMV |
| Qty | nil (quantities live on tranches) | Purchased Qty (gross) |
| Tax | — | Tax Collection Shares |
| Net | — | Purchased Qty - Tax = sellable |
| metadata | discount_percent, qualified_plan | buy_price (discounted cost basis) |
| grant_number | hash of `"ESPP:{symbol}:{grant_date}"` | — |
| Unique key | (ingestion_id, grant_number) | (origin_id, vest_date) |

---

### stock_plan_ingestions

| Column | Type | Notes |
|---|---|---|
| ingestion_id | TEXT PK | App-generated hex |
| account_id | TEXT | Single account for now |
| broker | TEXT | `ETRADE` |
| source_type | TEXT | `XLSX` / `PDF` |
| file_name | TEXT | Original upload filename |
| file_hash | TEXT | SHA256 of file — detect re-upload of same file |
| status | TEXT | `ACTIVE` / `ARCHIVED` |
| timestamps() | :utc_datetime_usec | inserted_at + updated_at |

**Constraint:** Exactly one ACTIVE ingestion per account_id.

### stock_plan_bronze_raw (Bronze — append-only)

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | App-generated hex |
| ingestion_id | TEXT FK → ingestions | on_delete: :restrict |
| sheet_name | TEXT | `ESPP` / `Restricted Stock` / `Options` (not validated at schema) |
| record_type | TEXT | `Grant` / `Purchase` / `Event` / `Vest Schedule` / `Totals` (not validated at schema) |
| row_index | INTEGER | 0-based position in sheet |
| parent_index | INTEGER | Row index of parent row (nil for parents). Persisted from M3 parser. |
| raw_row_json | TEXT | Full row as JSON with column headers as keys |
| row_hash | TEXT | SHA256 of raw_row_json — dedup within same ingestion |
| timestamps() | :utc_datetime_usec | inserted_at + updated_at |

### stock_plan_origins (Silver — parent allocations)

Represents: RSU grant, ESOP grant, or ESPP allotment (purchase).

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | App-generated hex |
| ingestion_id | TEXT FK → ingestions | on_delete: :restrict |
| account_id | TEXT | |
| symbol | TEXT | e.g., `ADBE` |
| plan_type | TEXT | `RSU` / `ESPP` / `ESOP` |
| grant_number | TEXT | Broker-assigned (RSU/ESOP). ESPP: computed hash of `"ESPP:{symbol}:{grant_date}"` |
| origin_date | :date | Grant date (RSU/ESOP) or purchase date (ESPP) |
| total_quantity | SafeDecimal | Total shares granted (RSU/ESOP). Nullable for ESPP (quantities live on tranches). |
| origin_fmv | SafeDecimal | FMV on origin_date |
| origin_fx_rate | SafeDecimal | USD/INR on origin_date |
| currency | TEXT | `USD` |
| status | TEXT | Broker-reported grant status |
| metadata_json | TEXT | Plan-type-specific details (see below) |
| timestamps() | :utc_datetime_usec | inserted_at + updated_at |

**Uniqueness:** `(ingestion_id, grant_number)` where grant_number is not null. Prevents duplicate grant imports.

**metadata_json by plan_type:**

```jsonc
// RSU
{"option_type": null}

// ESPP
{"lock_in_price": "150.00", "buy_price": "127.50", "discount_percent": "15", "buy_fmv": "160.00"}

// ESOP
{"strike_price": "72.36", "option_type": "NQ", "expiry_date": "2030-03-15"}
```

### stock_plan_tranches (Silver — vest schedule)

Children of origins for RSU and ESOP. Pre-populated from vest schedule. Updated when vest occurs.

**No unique constraint on tranches** — split vests, corrections, and multiple ESPP purchases on same date are valid. Dedup handled by Silver builder (M5).

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | App-generated hex |
| origin_id | TEXT FK → origins | on_delete: :restrict |
| ingestion_id | TEXT FK → ingestions | on_delete: :restrict |
| vest_date | :date | Scheduled or actual vest date |
| vest_quantity | SafeDecimal | Shares in this tranche |
| vest_fmv | SafeDecimal | FMV on vest date (null if unvested) |
| vest_fx_rate | SafeDecimal | USD/INR on vest date (null if unvested) |
| tax_withheld_qty | SafeDecimal | Shares withheld for tax (RSU only) |
| net_quantity | SafeDecimal | vest_quantity - tax_withheld_qty (sellable shares) |
| status | TEXT | See status table below |
| metadata_json | TEXT | Tax details, additional info |
| timestamps() | :utc_datetime_usec | inserted_at + updated_at |

**Tranche statuses by plan_type:**

| Status | RSU Meaning | ESOP Meaning |
|---|---|---|
| UNVESTED | Future scheduled shares | Future option rights |
| VESTED | Delivered shares / owned lot | Exercisable rights (not shares yet) |
| FORFEITED | Left company before vest | Unvested rights lost on exit |
| CANCELLED | Plan/admin correction | Plan/admin correction |
| EXPIRED | — | Vested but not exercised before expiry |

### stock_plan_exercises (Silver — ESOP only)

Converts vested ESOP tranche rights into owned shares. User-triggered.

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | App-generated hex |
| tranche_id | TEXT FK → tranches | on_delete: :restrict |
| ingestion_id | TEXT FK → ingestions | on_delete: :restrict |
| exercise_date | :date | Date of exercise |
| exercise_quantity | SafeDecimal | Shares exercised |
| exercise_fmv | SafeDecimal | FMV on exercise date |
| exercise_fx_rate | SafeDecimal | USD/INR on exercise date |
| exercise_price | SafeDecimal | Strike price paid per share |
| tax_withheld_qty | SafeDecimal | Shares withheld for tax |
| net_quantity | SafeDecimal | Sellable shares after tax |
| metadata_json | TEXT | Tax details |
| timestamps() | :utc_datetime_usec | inserted_at + updated_at |

### stock_plan_sales (Silver — all types)

Sell executions. User-triggered.

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | App-generated hex |
| ingestion_id | TEXT FK → ingestions | on_delete: :restrict |
| origin_id | TEXT FK → origins | on_delete: :restrict. Links sale to its grant/enrollment. |
| account_id | TEXT | |
| symbol | TEXT | |
| sale_date | :date | Trade date |
| total_quantity | SafeDecimal | Total shares sold in this order |
| sale_price | SafeDecimal | Price per share (nullable — nil from Benefit History, filled by G&L/Trade Conf) |
| sale_fx_rate | SafeDecimal | USD/INR on sale date |
| proceeds | SafeDecimal | total_quantity × sale_price |
| metadata_json | TEXT | Broker fees, G&L reference |
| timestamps() | :utc_datetime_usec | inserted_at + updated_at |

### stock_plan_sale_allocations (Silver — lot linkage)

Links one sale to one or more source lots. Enables FIFO / specific-lot tax calculations.

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | App-generated hex |
| sale_id | TEXT FK → sales | on_delete: :restrict |
| tranche_id | TEXT FK → tranches | on_delete: :restrict. Always populated (RSU/ESPP/ESOP). |
| exercise_id | TEXT FK → exercises | on_delete: :restrict. Nullable. Populated only for ESOP. |
| quantity | SafeDecimal | Shares consumed from this lot |
| sale_price | SafeDecimal | Per-share price for this allocation. Nullable — nil for a BH placeholder allocation, set when a G&L row prices the lot. |
| order_number | TEXT | Broker order/reference number from G&L. Nullable. Links allocation to its G&L row. |
| timestamps() | :utc_datetime_usec | inserted_at + updated_at |

**No polymorphic FKs.** All references are real DB-enforced foreign keys.
- RSU/ESPP: `tranche_id` = the lot, `exercise_id` = nil
- ESOP: `tranche_id` = the vested tranche, `exercise_id` = the specific exercise (the lot)

**All analytics are derived (computed in Gold/Tax layer, NEVER stored in M2):** `cost_basis_per_share`, `capital_gain`, `gain_type` (STCG/LTCG), `holding_days`, `total_proceeds`. Deterministic from source lot data + sale price — always recomputable.

**Available quantity (derived, never stored):** For any lot, available = `net_quantity` - sum of linked `sale_allocations.quantity`. Computed at query time.

---

### Type Strategy

| Layer | Dates | Timestamps | Decimals | Raw text |
|---|---|---|---|---|
| Bronze | TEXT (raw) | timestamps() | TEXT (raw) | TEXT |
| Silver | :date | timestamps() | SafeDecimal | TEXT (metadata_json) |
| Gold | :date | timestamps() | SafeDecimal | — |

**Design Principles:**
- Bronze preserves raw data as-is. Silver uses typed fields.
- Foreign keys enforced at DB level with `on_delete: :restrict`.
- Schema validations only on internal canonical enums (`plan_type`, `status`, `source_type`, `gain_type`).
- `metadata_json` holds plan-type-specific details that don't warrant their own columns.
- Sale allocations use polymorphic `source_type` + `source_id` to link to the correct lot source table.

### Deletion Order for Rebuilds

```
sale_allocations → sales → exercises → tranches → origins → bronze_raw (never deleted)
```

---

## Gold Layer (Derived Views)

All Gold views derived from Silver. Rebuilt on each ingestion. USD + INR dual views.

### Portfolio View

Per-grant current state:
- symbol, plan_type, grant_number
- vested_qty, unvested_qty, sellable_qty
- cost_basis_usd, cost_basis_inr (event-time FX)
- current_value_usd, current_value_inr (current FX)
- unrealized_pnl_usd, unrealized_pnl_inr

Groupable by: plan_type, vested/unvested, sellable/blocked, profit/loss

### Income View

Per-grant, per-tax-year:
- **Realized income:** RSU vest income (FMV * qty), ESPP discount income
- **Projected income (storable in Gold):** unvested_qty * grant_fmv, unvested_qty * vest_fmv — deterministic, stored
- **Projected income (live):** unvested_qty * current_stock_price — computed on the fly at UI, never stored

Chart: grant value at grant date vs realized income vs projected future income (at grant FMV, vest FMV, and current price)

### Tax View (Phase 2)

- Income tax liability (RSU vest)
- Capital gains (SELL: STCG vs LTCG based on holding period)
- ESPP classification (qualified vs disqualifying disposition)

### Vesting Schedule View

Upcoming vests from vesting_schedule_json:
- vest_date, quantity, grant_number, plan_type
- projected_value_usd (current price), projected_value_inr (current FX)

---

## FX Model

### Event-time FX (stored in Silver)

- `event_fx_rate`: USD/INR rate on event_date
- `event_value_inr`: computed value in INR at event time
- Used for: tax calculations, cost basis in INR, realized income in INR
- Immutable once stored for a given ingestion

### Current FX (dynamic at Gold/UI)

- Fetched or computed at query time
- Used for: current portfolio value, unrealized PnL, projected income
- Source: TBD (RBI reference rate API, or manual entry for Phase 1)

### Example (RSU Vest)

| Field | Value |
|---|---|
| Vest FMV | $100 |
| FX at vest | 80 |
| Cost basis INR | 8,000 |
| Current price | $120 |
| Current FX | 83 |
| Current value INR | 9,960 |

---

## Ingestion Pipeline

1. **Upload** — user uploads E*Trade Benefit History XLSX (grants + events), Holdings XLSX, and/or G&L_Expanded XLSX (sell events) via web UI
2. **Create ingestion** — generate ingestion_id, archive previous ACTIVE ingestion for this account
3. **Write Bronze** — parse XLSX sheets (Benefit History / Holdings / G&L_Expanded), write each row to bronze_raw (append-only)
4. **Rebuild Silver** — DELETE Silver rows for this account, parse Bronze for ACTIVE ingestion: extract grants (parent rows), extract events (child rows linked to grants), extract sell events (from G&L_Expanded), compute cost_basis, apply event-time FX
5. **Rebuild Gold** — DELETE Gold rows for this account, materialize portfolio/income/vesting views from Silver

### Rebuild Rule

Steps 4-5 are idempotent. `mix stock_plan.rebuild` deletes Silver + Gold for the ACTIVE ingestion and rebuilds from Bronze.

### Re-upload Same File

file_hash match on same account = warn user (no-op or confirm overwrite).

---

## Directory Structure

```
stock-plan-manager/
├── lib/
│   ├── stock_plan/                       # Business logic
│   │   ├── schema/                       # Ecto schemas (one file per table)
│   │   ├── types/
│   │   │   └── safe_decimal.ex           # SafeDecimal custom Ecto type (TEXT storage)
│   │   ├── ingestion/
│   │   │   ├── xlsx_parser.ex            # E*Trade Benefit History XLSX -> Bronze row structs
│   │   │   ├── holdings_parser.ex        # E*Trade Holdings (ByBenefitType) XLSX -> Bronze row structs
│   │   │   ├── gl_parser.ex              # E*Trade G&L_Expanded XLSX -> sell event structs
│   │   │   ├── bronze_writer.ex          # Bronze row structs -> DB
│   │   │   ├── silver_builder.ex         # Bronze -> Silver (grants + events + sells)
│   │   │   └── gold_builder.ex           # Silver -> Gold (portfolio + income)
│   │   ├── accounts.ex                   # Context: account CRUD
│   │   ├── ingestions.ex                 # Context: ingestion lifecycle
│   │   ├── grants.ex                     # Context: grant queries
│   │   ├── events.ex                     # Context: event queries
│   │   └── portfolio.ex                  # Context: gold layer queries
│   └── stock_plan_web/                   # Web layer
│       ├── components/
│       │   ├── core_components.ex
│       │   └── layouts/
│       ├── controllers/
│       │   └── upload_controller.ex      # XLSX upload endpoint
│       ├── live/
│       │   ├── upload_live.ex            # Upload UI
│       │   ├── portfolio_live.ex         # Portfolio view
│       │   ├── income_live.ex            # Income view
│       │   └── timeline_live.ex          # Vesting timeline
│       ├── router.ex
│       └── endpoint.ex
├── priv/
│   └── repo/
│       └── migrations/
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   └── runtime.exs
├── assets/
│   ├── css/app.css                       # Tailwind v4
│   └── js/app.js
├── docs/
│   ├── Highlevel_pdd.md
│   ├── pdd_DETAILED.md
│   └── sample-Etrade-BenefitHistory.xlsx
├── tmp/
│   └── stock_plan_dev.db                 # SQLite (gitignored)
├── mix.exs
└── CLAUDE.md
```

### Rules

1. **Schema modules contain zero business logic** — only `use Ecto.Schema`, `changeset/2`, field definitions.
2. **Context modules own all DB access** — no raw `Repo` calls outside context files.
3. **No raw SQL in contexts** — use `Ecto.Query` DSL. `execute/1` only in migrations.
4. **One LiveView per route** — paired `.ex` + `.html.heex`.
5. **Migrations are append-only** — never edit an existing migration. Always `mix ecto.gen.migration`.
6. **All IDs are app-generated hex strings** — `:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)`.
7. **SafeDecimal for all decimal fields** — never use `:decimal` directly on SQLite.

---

## Features — Phase Plan

### Phase 1 (Current)

1. **Ingestion:** Benefit History XLSX + Holdings XLSX + G&L_Expanded XLSX upload (sell events), Bronze write, Silver + Gold rebuild
2. **Portfolio view:** Per-grant breakdown, group/filter by plan_type, vested/unvested, sellable/blocked, profit/loss. USD + INR toggle.
3. **Income view:** Realized income (vested RSU, ESPP discount). Projected income (unvested * current price). Chart: grant value vs realized vs projected.
4. **Vesting schedule:** Upcoming vests with projected value
5. **FX:** Manual entry or static rates for Phase 1

### Phase 2 (Future)

1. **Tax engine:** Multi-layer — income tax (RSU vest), capital gains (SELL with STCG/LTCG), ESPP qualification rules
2. **Sell guidance:** Given "sell X shares" or "sell $Y worth", pick lots to minimize tax. Factor in already-executed sells in the FY.
3. **ITR documents:** Schedule FA (foreign assets), capital gains report, dividend reports
4. **Automated ingestion:** E*Trade API, email parsing, or headless browser
5. **Multi-broker:** Morgan Stanley, Schwab, Fidelity

---

## APIs

```
POST /upload                    -> Upload XLSX, trigger full pipeline
GET  /portfolio                 -> Portfolio view (LiveView)
GET  /income                    -> Income view (LiveView)
GET  /timeline                  -> Vesting timeline (LiveView)
```

---

## Development Commands

```bash
mix deps.get                    # Install dependencies
mix ecto.create                 # Create SQLite DB
mix ecto.migrate                # Run pending migrations
mix ecto.reset                  # Drop + recreate + migrate
mix phx.server                  # Start on port 4002
mix compile                     # Compile (0 warnings expected)
mix stock_plan.rebuild          # Rebuild Silver + Gold from Bronze
mix stock_plan.ingest <file>    # CLI ingestion (upload + full pipeline)
mix manual_test                 # Golden-file check: Portfolio + Capital Gains vs Sample-Data XLSX
./scripts/manual_test.sh        # Same (wrapper script)
```

---

## Key Invariants

1. **Exactly one ACTIVE ingestion per account.** New upload archives previous.
2. **Bronze is append-only.** All uploads retained for audit. Never delete Bronze rows.
3. **Silver is rebuildable from Bronze.** DELETE + INSERT on rebuild. No manual edits.
4. **Gold is rebuildable from Silver.** Derived views only. No facts in Gold.
5. **Projected income: two tiers.** Projections at Grant FMV / Vest FMV are deterministic and storable in Gold. Projections at current stock price are computed on the fly at UI — never stored.
6. **All queries scope to ACTIVE ingestion.** Archived data exists for audit/rollback only.
7. **No cross-ingestion mixing.** A query never joins rows from different ingestion_ids.
8. **Dedup via row_hash in Bronze.** Identical rows within same ingestion stored once.
9. **Event-time FX immutable per ingestion.** Historical rates don't change after Silver build.
10. **Explainability chain: UI -> Gold -> Silver -> Bronze.** Every displayed value traceable to source.
