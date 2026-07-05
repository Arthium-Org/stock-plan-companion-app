# Requirements: M22 — Multi-Symbol Support

## Introduction

Today the app silently assumes the user holds exactly one ticker symbol — ADBE (Adobe). The schema already stores `symbol` on every origin/tranche/sale, and most queries derive correctly per-symbol. The gap is the **presentation layer + a handful of hardcoded fallbacks** that ignore the symbol and substitute "ADBE" or "Adobe Inc.".

A user who joins a different employer, or who has stock from a previous employer in the same E*Trade account, currently sees wrong prices, wrong company names on tax exports, and wrong totals.

This milestone makes the app correct when the user holds 1+ symbols. There is no schema change.

---

## Requirement 1: Honest single-symbol → honest multi-symbol

**No silent fallback to ADBE anywhere.** Every place that today calls `StockPlan.StockPrice.current_price("ADBE")` must use the actual symbol from the origin/tranche/holding being displayed or computed.

### Affected call sites

```
lib/stock_plan_web/live/portfolio_live.ex:12
lib/stock_plan_web/live/sell_advisor_live.ex:10
lib/stock_plan/tax/sell_advisor.ex:57
lib/stock_plan/tax/sell_advisor_v2.ex:34
```

Each of these computes "current price" once at mount and uses it everywhere. When the user has multiple symbols, a single scalar is wrong — replace with a `%{symbol => current_price}` map and look up per row.

---

## Requirement 2: Stock metadata for ITR exports

Schedule FA CSV rows include legally required fields that today are hardcoded for Adobe:

```
"United States of America", "2", "Adobe Inc.(ADBE)",
"345 Park Ave; San Jose; CA; USA", "95110", "Company"
```

For multi-symbol support, each symbol needs:
- Legal entity name (e.g., "Adobe Inc.")
- Registered address (street; city; state; country)
- ZIP / postal code
- Country name + ITR country code (e.g., "United States of America" / "2")
- Nature of entity (almost always "Company" for listed stock)

**Source of truth:** a static lookup file (`priv/stock_meta.json` or similar) committed to the repo, keyed by symbol. The user does not enter this — it's curated. If the user holds a symbol we don't have metadata for, Schedule FA generation must surface a clear error (not silently emit a row with empty fields).

For the initial set we ship metadata for: **ADBE** (Adobe), plus any other symbol the developer's friends actually hold (TBD — add as encountered).

---

## Requirement 3: Portfolio view must show all symbols the user owns

Today the Portfolio page groups by grant within a single implicit symbol. With multi-symbol:

- The page header shows **all symbols the user owns** (e.g., "ADBE, MSFT") with per-symbol summary tiles at the top: held qty, cost basis, current value, P&L
- Below the header, grants are grouped by symbol then by plan_type (existing grouping continues within each symbol)
- USD/INR toggle still applies globally
- The hardcoded "Adobe (ADBE)" label at `portfolio_live.ex:369` becomes per-symbol

---

## Requirement 4: Tax Centre must work per-symbol

Schedule FA section currently produces one CSV. For multi-symbol:

- Each symbol generates its own block of CSV rows (one tax-year row per held tranche per symbol)
- The validation V1/V2/V3 errors must include the symbol in error messages
- Tax Centre UI surfaces per-symbol status (e.g., "ADBE: 3 entries · MSFT: 1 entry") and a single combined CSV download
- Schedule FSI (income tax on RSU vest) also generates per-symbol entries when applicable

---

## Requirement 5: Sell Advisor must scope to one symbol at a time

Sell Advisor takes a quantity or proceeds target and picks lots to minimize tax. This calculation is **per symbol** — you can't combine lots of ADBE and MSFT in one sell decision.

- The page gets a symbol selector at the top (dropdown if 2+ symbols, hidden if user owns only 1)
- All computation, current price lookup, and suggested-lot display reflect the selected symbol
- Default selection: the symbol with the most held shares

---

## Requirement 6: Ingestion handles per-symbol files

**Reality check** (from real E*Trade exports in `docs/Sample-Data/SampleUser - 5/`): E*Trade does **not** give one big BH or Holdings file containing all symbols. It gives:

- **One Benefit History file per symbol** (`BenefitHistory.xlsx` for ADBE, `BenefitHistory (1).xlsx` for CRM — the filename does not indicate which is which; symbol must be extracted from row data)
- **One Holdings file per symbol the user currently holds** — if the user has sold all shares of a symbol, E*Trade gives no Holdings file for it. A user with grants from a previous employer they fully cashed out has no Holdings for that symbol at all.
- **One shared G&L Expanded file per tax year** — already multi-symbol, no change needed.

This means the existing M9 upload flow (which expects ONE BH and ONE Holdings) is wrong for multi-symbol users. M22 must extend it:

### Upload page changes

| Slot | Max files today | Max files after M22 |
|---|---|---|
| Holdings | 1 | N (one per held symbol) |
| Benefit History | 1 | N (one per granted symbol) |
| G&L Expanded | 10 | 10 (no change) |

Files within a slot are processed independently; their symbol is determined at parse time from `data["Symbol"]`. The FileDetector continues to classify by file *type* (BH/Holdings/G&L) — it does not need to identify the symbol.

### Per-symbol archiving (new requirement)

Today `archive_previous_bh/1` archives ALL previously ACTIVE BH ingestions for the account. That breaks multi-symbol: re-uploading ADBE BH would archive the user's CRM BH.

After M22, archiving must be scoped per-symbol:

- `archive_previous_bh(account_id, symbol)` — archives only previous ACTIVE BH ingestions whose **dominant symbol** matches.
- `archive_previous_holdings(account_id, symbol)` — same shape.
- G&L: no change (no archiving today, no archiving after M22).

"Dominant symbol" means the symbol present in the majority of rows. E*Trade BH files contain ONE symbol throughout, so this is unambiguous in practice; for robustness, store the dominant symbol on the ingestion row (new column `dominant_symbol`).

### Silver rebuild

The Silver builder must consume ALL ACTIVE BH and Holdings ingestions, not just one. Today's `rebuild` already reads from Bronze for the account; verify it doesn't have a "first ingestion wins" race.

### Asymmetry: BH exists, Holdings doesn't

A user can have BH for a symbol (they were granted shares) but no Holdings (they sold everything). In that case:
- Portfolio shows zero held shares for that symbol — correct.
- Historical analysis (M24) still works from BH alone.
- Schedule FA / FSI still emit rows for the years that had income or sales, regardless of current holdings.

This is the SampleUser-5 case: ADBE has BH but no Holdings; CRM has both.

---

## Requirement 7: Zero data migration

Existing single-symbol installs (every current user, since the app has shipped to friends) must keep working with no manual steps. Specifically:

- Existing SQLite databases continue to function without migration scripts
- A user who only holds ADBE sees no visible change in the UI (no empty "select symbol" dropdowns, no extra navigation)
- Stock metadata for ADBE is preloaded so existing installs don't break Schedule FA

---

## Requirement 8: Explicit ACTIVE ingestion semantics

Today the codebase has `get_active_holdings(account_id)` and similar helpers that return **the one** ACTIVE row for a category. Post-M22 there are N ACTIVE BH and N ACTIVE Holdings rows (one per symbol). The ambiguous "the active ingestion" concept doesn't work anymore.

Replace with explicit per-symbol contracts:

| Helper | Returns | Notes |
|---|---|---|
| `active_bh(account_id, symbol)` | one `%Ingestion{}` or nil | The ACTIVE BH for that symbol; nil if user has no BH for that symbol |
| `active_holdings(account_id, symbol)` | one `%Ingestion{}` or nil | Same shape |
| `active_bh_symbols(account_id)` | `[String.t()]` | Distinct symbols with at least one ACTIVE BH |
| `active_holdings_symbols(account_id)` | `[String.t()]` | Distinct symbols with at least one ACTIVE Holdings |
| `any_active_bh?(account_id)` | boolean | Used by `validate_active_bh/1` (G&L ingest precondition) — replaces the existing function with same contract |
| `active_gl_for_year(account_id, year)` | list of `%Ingestion{}` | G&L stays year-scoped; multiple G&L files per year may legitimately coexist |

All previous call-sites of `get_active_holdings/1` need migration. Audit + update before M22 ships:

- `lib/stock_plan/ingestions.ex:103` — replace with per-symbol form; callers update accordingly.
- Any UploadChecks readiness logic that asked "is there ACTIVE Holdings?" should switch to "list ACTIVE Holdings symbols" and reason per-symbol.

---

## Requirement 9: Symbol universe — Portfolio vs History/Tax distinction

Different consumers want different definitions of "the user's symbols":

| Consumer | Symbol set | Source |
|---|---|---|
| **Portfolio page** | Currently-held symbols (held qty > 0) | Aggregate over Silver: distinct `origin.symbol` where any tranche or exercise has remaining net qty after sale allocations |
| **History page** (M24) | All symbols the user has EVER held | `DISTINCT origins.symbol` across all ACTIVE ingestions |
| **Tax Centre / Schedule FA / FSI** | All symbols with relevant tax events in the requested CY | Joined: origins ∪ sales ∪ exercises filtered by tax year |
| **Sell Advisor** | Currently-held symbols (same as Portfolio) | Same source as Portfolio |

The earlier draft of `Portfolio.user_symbols/1` ambiguously said "active ingestion." That's wrong: a user who sold all their ADBE (no Holdings file) but kept their CRM should see:

- Portfolio: only CRM
- History: both ADBE and CRM (ADBE's historical economics still matter)
- Schedule FA for CY where ADBE was sold: includes ADBE rows
- Sell Advisor selector: only CRM

Module placement:

- `Portfolio.held_symbols/1` — currently-held
- `History.owned_symbols/1` (or `StockPlan.Origins.all_symbols/1`) — all-time
- Both derive directly from Silver; no caching needed for v1.

Existing code using a single `user_symbols/1` must be updated to call the right one per use case.

---

## Requirement 10: Cross-file symbol consistency check

Once N BH and N Holdings files are supported, the user can mistakenly upload BH for ADBE and Holdings for MSFT in the same session — files genuinely don't match. Detect and warn (don't block — "sold out" is a valid case where BH exists without Holdings).

Add to `UploadChecks.check/1`:

- **BH without Holdings warning** (`:info` severity): "You have BH for {symbol} but no Holdings file. If you sold all shares, ignore. Otherwise, upload a Holdings export for {symbol}."
- **Holdings without BH warning** (`:warning` severity): "You have Holdings for {symbol} but no BH file. Tax features for {symbol} will be limited until you upload BH."

The asymmetry in severity reflects: BH-without-Holdings is likely benign (sold-out scenario); Holdings-without-BH is more likely a mistake or a missing upload (the user can't reasonably have current holdings without having ever been granted shares).

Surfaced in the existing UploadChecks nudge list + sticky banner.

---

## Out of Scope

- Multi-tenant / multi-account support (still single-tenant, single-account)
- User-entered symbol metadata (no UI to add new symbols' metadata at runtime; curated file only)
- Foreign exchange listings (e.g., London-listed ticker variants — assume US listing only)
- Currency other than USD for stock (RSU in EUR, GBP, etc. — not supported)
- Splits/dividends/corporate actions per symbol (existing behavior unchanged)

---

## Definition of Done

- [ ] No source file contains a hardcoded "ADBE" outside of the metadata lookup file and tests
- [ ] User with 2+ symbols sees correct totals, prices, and tax outputs for each
- [ ] User with 1 symbol sees no UI clutter (no empty selector, no per-symbol headers if redundant)
- [ ] Schedule FA CSV contains correct legal name + address per symbol from metadata file
- [ ] `mix compile` 0 warnings, `mix test` all pass with new multi-symbol fixtures
- [ ] Existing single-symbol install upgrades cleanly with no manual steps
