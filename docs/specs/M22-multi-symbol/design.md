# Design: M22 — Multi-Symbol Support

## Approach

Multi-symbol support is **mostly a presentation-layer fix** with one new module (stock metadata). The schema, ingestion, Silver builder, and most Gold queries already key by symbol. The work is:

1. New module: `StockPlan.StockMeta` — lookup table for legal name, address, country code, etc.
2. Replace hardcoded `current_price("ADBE")` scalar with `%{symbol => price}` map throughout
3. UI components show per-symbol breakdown when there are multiple symbols, collapse to "no selector" when there's just one
4. Schedule FA + Schedule FSI emit one block per symbol
5. Sell Advisor adds a symbol selector

No schema migration. No new Ecto schemas.

---

## Module: `StockPlan.StockMeta`

```elixir
defmodule StockPlan.StockMeta do
  @meta_path "stock_meta.json"  # priv/stock_meta.json

  @spec get(String.t()) :: {:ok, map()} | {:error, :unknown_symbol}
  def get(symbol)

  # Bang variant — raises StockMetaUnknownSymbolError on unknown symbol.
  # Schedule FA's row_to_csv/1 uses this; callers must pre-validate via
  # known?/1 to surface a clear error instead of crashing.
  @spec get!(String.t()) :: map()
  def get!(symbol)

  @spec all() :: %{String.t() => map()}
  def all()

  @spec known?(String.t()) :: boolean()
  def known?(symbol)
end
```

### Data shape (per symbol)

```jsonc
{
  "ADBE": {
    "legal_name": "Adobe Inc.",
    "display_name": "Adobe",
    "country": "United States of America",
    "country_code": "2",
    "address": "345 Park Ave; San Jose; CA; USA",
    "zip": "95110",
    "nature_of_entity": "Company"
  },
  "MSFT": {
    "legal_name": "Microsoft Corporation",
    "display_name": "Microsoft",
    "country": "United States of America",
    "country_code": "2",
    "address": "One Microsoft Way; Redmond; WA; USA",
    "zip": "98052",
    "nature_of_entity": "Company"
  }
}
```

**File location:** `priv/stock_meta.json` (loaded via `:code.priv_dir(:stock_plan)` so it works in releases).

**Loading:** lazy + cached via `:persistent_term`. First call to `get/1` reads + parses the JSON; subsequent calls hit the term store. No GenServer needed (data is static per release).

**Error model:** `get/1` returns `{:error, :unknown_symbol}` for symbols not in the file. Callers (notably Schedule FA) treat this as a hard error — generate a clear "missing metadata for ABC; add to priv/stock_meta.json" message rather than emitting bad data.

---

## Replacing the hardcoded scalar current_price

### Current pattern (single-symbol assumption)

```elixir
def mount(_, _, socket) do
  current_price = StockPlan.StockPrice.current_price("ADBE")
  # ... uses current_price as a scalar
end
```

### New pattern — pick the right symbol set per consumer

Portfolio and Sell Advisor scope to **currently held** symbols. History,
Tax Centre, and Schedule FA scope to **all symbols ever owned** (so
fully-exited symbols still appear in tax filings and historical
analysis). The two helpers come from the symbol-universe split documented
in Requirement 9 and implemented in M22's tasks 2.1–2.2.

```elixir
# Portfolio / Sell Advisor: currently held only
def mount(_, _, socket) do
  symbols = Portfolio.held_symbols(@account_id)  # User5: ["CRM"]
  prices  = Map.new(symbols, fn s -> {s, StockPlan.StockPrice.current_price(s)} end)
  # rows look up prices[row.symbol]
end

# History / Tax / Schedule FA: all symbols ever owned
def mount(_, _, socket) do
  symbols = Portfolio.owned_symbols(@account_id)  # User5: ["ADBE", "CRM"]
  prices  = Map.new(symbols, fn s -> {s, StockPlan.StockPrice.current_price(s)} end)
  # ...
end
```

No more single `user_symbols/1` helper — that's been removed precisely
because "the user's symbols" depends on what the consumer is asking. Code
calling the old name must be updated to pick `held_symbols/1` or
`owned_symbols/1` based on its purpose.

**Source — no longer "the active ingestion":** with per-symbol ACTIVE
ingestions (one per symbol per category), there is no single "active
ingestion." Both helpers traverse Silver directly:

- `held_symbols/1` — aggregates origins/tranches/sale_allocations to find
  symbols with remaining net qty > 0. Reuses the existing
  `Portfolio.build/1` aggregation logic; just projects to the symbol axis.
- `owned_symbols/1` — `SELECT DISTINCT o.symbol FROM stock_plan_origins o
  JOIN stock_plan_ingestions i ON i.ingestion_id = o.ingestion_id WHERE
  i.account_id = ? AND i.status = "ACTIVE"`. This collects every symbol
  that has *any* origin under *any* ACTIVE ingestion — exactly what
  History and Tax consumers need.

---

## UI: collapsing vs splitting

The single-symbol case is the dominant one — preserve that UX. The rule:

| User holds | Portfolio header | Sell Advisor selector | Tax pages |
|---|---|---|---|
| 1 symbol | Inline ("ADBE — total value: $X") | Hidden | Single block (status quo) |
| 2+ symbols | Per-symbol summary tiles row | Dropdown shown, defaulted to largest holding | Stacked blocks, one per symbol, with a "Combined" tab toggle |

This avoids cluttering the dominant user's experience.

---

## Schedule FA changes

Today `row_to_csv/1` in `lib/stock_plan/tax/schedule_fa.ex` has hardcoded fields:

```elixir
fields = [
  "United States of America",
  "2",
  "Adobe Inc.(ADBE)",
  "345 Park Ave; San Jose; CA; USA",
  "95110",
  "Company",
  ...
]
```

Replace with:

```elixir
meta = StockMeta.get!(row.symbol)
fields = [
  meta.country,
  meta.country_code,
  "#{meta.legal_name}(#{row.symbol})",
  meta.address,
  meta.zip,
  meta.nature_of_entity,
  ...
]
```

Each Schedule FA row already carries `symbol` (added during M21 timeline integration — verify), so the row-level lookup just works.

`StockMeta.get!/1` raises if unknown — but the upstream build function should pre-validate and return `{:error, {:missing_meta, ["ABC"]}}` so the UI shows a clear message before any CSV generation happens.

---

## Sell Advisor symbol selector

`SellAdvisorLive` currently:

1. Loads all of user's vested-and-held lots
2. Takes a target quantity or USD amount
3. Picks lots

For multi-symbol:

1. Add `@symbol` to socket assigns
2. Add `Portfolio.held_symbols/1` lookup at mount (currently held only — exited symbols don't appear in the selector)
3. Default `@symbol` to symbol with largest held qty
4. Filter loaded lots to `lot.symbol == @symbol`
5. `current_price` becomes `StockPrice.current_price(@symbol)` (already takes symbol arg, just wire it)
6. Add a `<select>` in the template that triggers `phx-change="select_symbol"` → updates `@symbol` and re-runs the lot pick

Don't try to support cross-symbol sells — that's a different problem (portfolio rebalancing, out of scope).

---

## Tax Centre per-symbol blocks

`TaxCentreLive` currently has tabs for: Schedule FA, Schedule FSI, Capital Gains.

For multi-symbol:

- Each tab continues to exist
- Within each tab, when 2+ symbols, the content is **stacked blocks**, one per symbol, with a separator/header per block
- A subtle "Combined CSV" download button at the top that produces a single CSV with rows from all symbols (this is what the user actually wants for filing)
- When only 1 symbol, no per-symbol header — current layout

---

## Ingestion: real changes required (revised)

> The earlier draft of this section assumed BH and Holdings were single multi-symbol files. Real E*Trade data (see SampleUser-5) shows they are per-symbol. This section is rewritten accordingly.

### One small schema addition

Add a nullable column `dominant_symbol :: text` to `stock_plan_ingestions`. Populated during BH and Holdings ingestion only (G&L stays null since it spans all symbols). Indexed `(account_id, category, dominant_symbol, status)` for the per-symbol archive lookup.

Migration is additive and safe — existing single-symbol installs get backfilled from their existing row data on first launch after upgrade (or accept nulls; the per-symbol archive logic treats null as "any symbol", preserving today's behavior).

### Symbol extraction at ingestion time

After XLSX parse, before Bronze write, scan the parsed rows for `data["Symbol"]` (BH) or the equivalent column (Holdings). Compute the dominant symbol (most frequent non-empty value, defensive against future broker formats that mix symbols). Store on the new column.

Function naming:
- **`Ingestions.extract_file_symbol/1`** — public helper. Takes parsed rows, returns `{:ok, "ADBE"}` or `{:error, :no_symbol}`. The name reflects intent: "what is this file's symbol?" — E*Trade gives one symbol per file in practice.
- The COLUMN remains `dominant_symbol` on the ingestion row. That's still accurate (it's the dominant symbol of the file's rows, even if the count is unanimous) and defensive against future brokers that might ship multi-symbol files where we'd need the majority-wins heuristic.

If no symbol can be determined (malformed file with no Symbol column or all blanks), reject the ingestion with a clear error.

### Ingestions context: explicit per-symbol API

The legacy `get_active_holdings/1` (and any callers asking "what's THE active X?") is removed and replaced with explicit per-symbol helpers. Implementation in `lib/stock_plan/ingestions.ex`:

```elixir
@spec active_bh(String.t(), String.t()) :: Ingestion.t() | nil
def active_bh(account_id, symbol) do
  Repo.one(
    from i in Ingestion,
      where: i.account_id == ^account_id and i.status == "ACTIVE"
              and i.category == "BENEFIT_HISTORY"
              and i.dominant_symbol == ^symbol,
      limit: 1
  )
end

@spec active_holdings(String.t(), String.t()) :: Ingestion.t() | nil
def active_holdings(account_id, symbol), do: # same shape

@spec active_bh_symbols(String.t()) :: [String.t()]
def active_bh_symbols(account_id) do
  Repo.all(
    from i in Ingestion,
      where: i.account_id == ^account_id and i.status == "ACTIVE"
              and i.category == "BENEFIT_HISTORY"
              and not is_nil(i.dominant_symbol),
      distinct: true,
      select: i.dominant_symbol,
      order_by: i.dominant_symbol
  )
end

@spec active_holdings_symbols(String.t()) :: [String.t()]
def active_holdings_symbols(account_id), do: # same shape

@spec any_active_bh?(String.t()) :: boolean
def any_active_bh?(account_id) do
  Repo.exists?(
    from i in Ingestion,
      where: i.account_id == ^account_id and i.status == "ACTIVE"
              and i.category == "BENEFIT_HISTORY"
  )
end
```

`validate_active_bh/1` (the G&L ingest precondition) becomes a thin wrapper around `any_active_bh?/1` for backward compatibility.

### Symbol universe — two distinct helpers

Per Requirement 9:

```elixir
# Portfolio + Sell Advisor: currently held only
@spec held_symbols(String.t()) :: [String.t()]
def held_symbols(account_id) do
  # Distinct symbols where any origin has remaining net holdings.
  # Derived from Silver: vested qty - sale_allocations qty > 0 (or exercise qty for ESOP).
  # Implementation reuses existing Portfolio.build/1 aggregation; just project to symbol.
end

# History + Tax + Schedule FA: every symbol ever owned
@spec owned_symbols(String.t()) :: [String.t()]
def owned_symbols(account_id) do
  Repo.all(
    from o in Origin,
      join: i in Ingestion, on: i.ingestion_id == o.ingestion_id,
      where: i.account_id == ^account_id and i.status == "ACTIVE",
      distinct: true,
      select: o.symbol,
      order_by: o.symbol
  )
end
```

Replacement guidance for code that previously called a single `user_symbols/1`:

- Portfolio mount, Sell Advisor mount → `Portfolio.held_symbols/1`
- History (M24), Tax Centre tabs, Schedule FA build → `Portfolio.owned_symbols/1` (or move to a dedicated module)

### Per-symbol archiving

```elixir
defp archive_previous_bh(account_id, symbol) do
  Repo.update_all(
    from(i in Ingestion,
      where: i.account_id == ^account_id and i.status == "ACTIVE"
              and i.category == "BENEFIT_HISTORY"
              and i.dominant_symbol == ^symbol),
    set: [status: "ARCHIVED", updated_at: DateTime.utc_now()]
  )
end
```

Identical shape for `archive_previous_holdings/2`. The ingest functions become:

```elixir
def ingest_benefit_history(account_id, file_path) do
  with :ok <- validate_file(file_path),
       {:ok, file_hash} <- compute_hash(file_path),
       :ok <- check_duplicate(account_id, file_hash),
       {:ok, rows, parse_warnings} <- XlsxParser.parse(file_path),
       {:ok, symbol} <- extract_dominant_symbol(rows) do
    Repo.transaction(fn ->
      archive_previous_bh(account_id, symbol)
      {:ok, ing} = create_ingestion(account_id, file_path, file_hash, "BENEFIT_HISTORY", symbol)
      # ... rest unchanged
    end)
  end
end
```

`create_ingestion/5` writes the symbol to the new column.

### Silver rebuild — multi-ACTIVE inputs

Today the Silver builder iterates over ACTIVE Bronze for the account. With per-symbol ingestions, there will be MULTIPLE ACTIVE BH rows (one per symbol). Verify the builder doesn't have a `limit: 1` anywhere on its source query. If it does, drop the limit.

Origins are keyed by `(ingestion_id, grant_number)` — already per-symbol-safe because each ingestion is one symbol.

### Upload UI: bump max_entries

```elixir
|> allow_upload(:benefit_history, accept: ~w(.xlsx), max_entries: 5, max_file_size: @max_file_size)
|> allow_upload(:holdings,        accept: ~w(.xlsx), max_entries: 5, max_file_size: @max_file_size)
```

Five is generous — most users have 1 or 2 employers. The per-file status chain (already in place from the M9 redesign) handles multiple file processing cleanly.

### Per-file status detail line

When status transitions to `:done` for a BH or Holdings ingestion, the summary line now includes the detected symbol: `"ADBE — 23 origins · 146 tranches · 93 sales"`. This gives the user immediate confirmation that the correct file was parsed.

### Asymmetric coverage (BH without Holdings)

A user can have BH for ADBE (fully sold out) but no Holdings for ADBE (E*Trade doesn't generate one). The downstream code must not assume Holdings exists for every symbol. Today's M21 timeline already handles this via Holdings-or-BH fallback; verify it doesn't regress.

### UploadChecks updates

The readiness checker should list distinct ACTIVE symbols separately:

```
Symbols detected:
  ADBE  · BH ✓  · Holdings ✗ (fully sold)
  CRM   · BH ✓  · Holdings ✓
G&L Expanded: 2023, 2024, 2025
```

This gives the user a clear picture of what data is loaded per symbol.

### Cross-file consistency nudges

Two new nudge codes surface mismatches between BH and Holdings symbol sets:

```elixir
defp check_symbol_consistency(account_id) do
  bh_symbols       = Ingestions.active_bh_symbols(account_id)       |> MapSet.new()
  holdings_symbols = Ingestions.active_holdings_symbols(account_id) |> MapSet.new()

  bh_only       = MapSet.difference(bh_symbols, holdings_symbols)
  holdings_only = MapSet.difference(holdings_symbols, bh_symbols)

  Enum.map(bh_only, fn s ->
    %{
      severity: :info,
      code: :bh_without_holdings,
      reason: "BH for #{s} but no Holdings file uploaded",
      impact: "If you sold all #{s} shares this is expected. Otherwise, Portfolio + Sell Advisor for #{s} won't be accurate.",
      action: "Upload Holdings (ByBenefitType) for #{s} from E*Trade, or ignore if fully sold",
      metadata: %{symbol: s}
    }
  end) ++
    Enum.map(holdings_only, fn s ->
      %{
        severity: :warning,
        code: :holdings_without_bh,
        reason: "Holdings for #{s} but no BH file uploaded",
        impact: "Tax features (Schedule FA, Capital Gains, Schedule FSI) for #{s} can't be computed without BH",
        action: "Upload Benefit History for #{s}",
        metadata: %{symbol: s}
      }
    end)
end
```

Severity asymmetry rationale:
- BH-without-Holdings is benign in the common sold-out case → `:info`.
- Holdings-without-BH almost always means a missing upload → `:warning`.

Neither is `:error` — uploads should never be blocked.

---

## Migration: minimal but not zero

- Schema: one ALTER TABLE adding `dominant_symbol` nullable. Idempotent migration.
- Existing single-symbol installs: backfill `dominant_symbol` from BH/Holdings row data on first launch after upgrade (a one-shot Task in Application.start). For nulls left over (e.g., parse failure), per-symbol archive falls back to global archive (matches today's behavior).
- A user with an existing single-symbol DB sees identical UX (single-symbol path).
- `priv/stock_meta.json` ships in the release.

---

## Open questions

1. **Source of company addresses** — Manually curated. We add entries as we encounter new symbols among users. Acceptable scope creep limit: ≤10 symbols in the initial commit; more added on demand.
2. **Cap on symbol count** — No hard cap. UI is designed for 1–5 symbols; degrades gracefully if a user has 20+. Not optimized for that case.
3. **Ticker change handling** — If a company gets acquired (e.g., $LNKD → integrated into MSFT after acquisition), what happens? Out of scope. The user's broker data will reflect whatever symbol the broker reports; we just display it.
4. **Stock price API rate limits** — N symbols means N times more Yahoo Finance calls. The existing 15-min cache should still cover it for low symbol counts. Revisit if it becomes a problem.
