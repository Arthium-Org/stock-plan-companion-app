# Design: G&L Allocation Aggregation

## Current flow (broken)

```
process_gl_phase
  └─ for each Bronze G&L row:
       process_gl_row
         → find_bh_sale(origin_id, sale_date)
         → find_tranche_by_date(origin_id, vest_date)
         → create_gl_allocation(sale, tranche, qty, price, order)
               ↳ dedup check: (sale_id, tranche_id, qty, price, order) → skip if exists
               ↳ BUG: drops wash-sale sub-lots with same qty+price
```

---

## New flow

```
process_gl_phase
  └─ aggregate_gl_bronze(gl_ingestions)   ← NEW pre-aggregation step
       1. fetch all Bronze G&L rows for account across all GL ingestions
       2. per (symbol, sale_date): keep rows from latest inserted_at ingestion only
       3. per plan-type-specific key (grant_number+vest_date for RS; grant_date+purchase_date for ESPP):
            sum quantities → one AggregatedLot struct
  └─ for each AggregatedLot:
       process_aggregated_lot
         → RS: find_origin_by_grant + find_tranche_by_date(vest_date) + fill_tranche_fmv
         → ESPP: find_espp_origin(grant_date) + find_tranche_by_date(purchase_date)
         → find_bh_sale (RS) or find_bh_sale_espp (ESPP, aggregated_quantity)
         → upsert_gl_allocation(sale, tranche, aggregated_qty, price, order)
               ↳ dedup: (sale_id, tranche_id, order_number, sale_price) — no qty in key
               ↳ if exists: update quantity; if not: insert
```

---

## `aggregate_gl_bronze/1`

Bronze G&L rows already have `record_type: "Sell"` (the GL parser filters at ingest time),
so the Bronze query filters on `record_type` as a safety guard.

```elixir
defp aggregate_gl_bronze(gl_ingestions) do
  ing_ids = Enum.map(gl_ingestions, & &1.ingestion_id)

  # Build a lookup: ingestion_id → inserted_at for timestamp comparison
  ing_timestamps = Map.new(gl_ingestions, &{&1.ingestion_id, &1.inserted_at})

  # Fetch all G&L Bronze rows for these ingestions (Sell rows only)
  bronze_rows = Repo.all(
    from r in BronzeRaw,
      where: r.ingestion_id in ^ing_ids and r.record_type == "Sell",
      select: {r.ingestion_id, r.raw_row_json}
  )

  # Build a map: {symbol, sale_date} → ingestion_id with the latest inserted_at
  latest_ing_by_sale =
    bronze_rows
    |> Enum.reduce(%{}, fn {ing_id, raw}, acc ->
      data = Jason.decode!(raw)
      symbol = data["Symbol"]
      sale_date = VN.parse_date(data["Date Sold"])
      key = {symbol, sale_date}
      ing_time = Map.fetch!(ing_timestamps, ing_id)

      Map.update(acc, key, {ing_id, ing_time}, fn {existing_id, existing_time} ->
        if DateTime.compare(ing_time, existing_time) == :gt,
          do: {ing_id, ing_time},
          else: {existing_id, existing_time}
      end)
    end)
    |> Map.new(fn {key, {ing_id, _time}} -> {key, ing_id} end)

  # Discard rows not from the latest ingestion for their (symbol, sale_date)
  surviving =
    Enum.filter(bronze_rows, fn {ing_id, raw} ->
      data = Jason.decode!(raw)
      symbol = data["Symbol"]
      sale_date = VN.parse_date(data["Date Sold"])
      Map.get(latest_ing_by_sale, {symbol, sale_date}) == ing_id
    end)

  # Aggregate by plan-type-specific key:
  #   RS:   (symbol, "RS",   grant_number, vest_date,     sale_date, order, price)
  #   ESPP: (symbol, "ESPP", grant_date,   purchase_date, sale_date, order, price)
  # ESPP Grant Number is always "--" — use Grant Date for origin lookup instead.
  surviving
  |> Enum.group_by(fn {_ing_id, raw} ->
    data = Jason.decode!(raw)
    plan_type = data["Plan Type"]

    {tranche_key, tranche_date} =
      if plan_type == "ESPP" do
        {VN.parse_date(data["Grant Date"]), VN.parse_date(data["Purchase Date"])}
      else
        {data["Grant Number"], VN.parse_date(data["Vest Date"])}
      end

    {
      data["Symbol"],
      plan_type,
      tranche_key,
      tranche_date,
      VN.parse_date(data["Date Sold"]),
      to_string(data["Order Number"] || ""),
      VN.clean_number(data["Proceeds Per Share"])
    }
  end)
  |> Enum.map(fn {key, rows} ->
    {symbol, plan_type, tranche_key, tranche_date, sale_date, order_number, price} = key

    total_qty =
      rows
      |> Enum.map(fn {_ing_id, raw} ->
        data = Jason.decode!(raw)
        Decimal.new(VN.clean_number(data["Quantity"]))
      end)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    # Carry vest_fmv from the first row that has it — used by fill_tranche_fmv
    vest_fmv =
      rows
      |> Enum.map(fn {_ing_id, raw} -> Jason.decode!(raw)["Vest Date FMV"] end)
      |> Enum.find(&(&1 != nil))
      |> then(&VN.clean_number/1)

    %{
      symbol: symbol,
      plan_type: plan_type,
      # RS: grant_number; ESPP: grant_date (Date struct)
      tranche_key: tranche_key,
      # RS: vest_date; ESPP: purchase_date
      tranche_date: tranche_date,
      sale_date: sale_date,
      order_number: order_number,
      proceeds_per_share: price,
      aggregated_quantity: total_qty,
      vest_fmv: vest_fmv
    }
  end)
end
```

---

## `upsert_gl_allocation/5`

Replaces `create_gl_allocation/5`. Key change: dedup does **not** include quantity.
Two lots can share `(sale_id, tranche_id, order_number, sale_price)` only when they have
different aggregated quantities (price variation case — different sub-lot groups).
Wait — this is not possible: if price is in the grouping key, two groups with different
prices produce different aggregated lots, which are looked up separately. So the upsert
key `(sale_id, tranche_id, order_number, sale_price)` is unique per aggregated lot. ✓

```elixir
defp upsert_gl_allocation(sale, tranche, quantity, proceeds_per_share, order_number) do
  # Drop BH placeholder (nil price) only — same as before
  Repo.delete_all(
    from a in SaleAllocation,
      where: a.sale_id == ^sale.id and a.tranche_id == ^tranche.id and is_nil(a.sale_price)
  )

  price_decimal = Decimal.new(proceeds_per_share)
  qty_decimal = Decimal.new(quantity)

  existing =
    Repo.one(
      from a in SaleAllocation,
        where:
          a.sale_id == ^sale.id and a.tranche_id == ^tranche.id and
            a.order_number == ^order_number and a.sale_price == ^price_decimal,
        limit: 1
    )

  if existing do
    existing
    |> SaleAllocation.changeset(%{quantity: qty_decimal})
    |> Repo.update!()
    0
  else
    %SaleAllocation{}
    |> SaleAllocation.changeset(%{
      id: ID.generate(),
      sale_id: sale.id,
      tranche_id: tranche.id,
      quantity: qty_decimal,
      sale_price: price_decimal,
      order_number: order_number
    })
    |> Repo.insert!()
    1
  end
end
```

---

## Cross-file "latest wins" — use inserted_at, not ingestion_id

`ingestion_id` is `crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)` — random
bytes, **not monotonic**. Lexicographic comparison does not identify the later upload.

Use `ingestion.inserted_at` (`%DateTime{}`, UTC) for ordering. The ingestion struct is
already loaded in `process_gl_phase/2` — pass the full list to `aggregate_gl_bronze/1`
so timestamp comparison is available without an extra DB query.

---

## `process_aggregated_lot/2` — origin + tranche lookup

Dispatches by `plan_type`, mirroring current `process_gl_row/3` branching:

**RSU / ESOP (`plan_type == "RS"`):**
```elixir
find_origin_by_grant(account_id, lot.tranche_key)   # tranche_key = grant_number
find_tranche_by_date(origin.id, lot.tranche_date)   # tranche_date = vest_date
find_bh_sale(origin.id, lot.sale_date)
fill_tranche_fmv(tranche, lot.vest_fmv)             # enrich if nil — same as before
```

**ESPP (`plan_type == "ESPP"`):**
```elixir
find_espp_origin(account_id, lot.tranche_key)       # tranche_key = grant_date (%Date{})
find_tranche_by_date(origin.id, lot.tranche_date)   # tranche_date = purchase_date
find_bh_sale_espp(origin.id, lot.sale_date, lot.aggregated_quantity)
# No fill_tranche_fmv for ESPP (no Vest Date FMV column in ESPP G&L rows)
```

`lot.vest_fmv` is the first non-nil `Vest Date FMV` from any row in the group (carried
on the aggregated lot struct). `fill_tranche_fmv` is called per lot with this value,
preserving the existing "enrich if nil" behavior from `process_gl_row/3`.

---

## What is deleted

- `create_gl_allocation/5` — replaced by `upsert_gl_allocation/5`
- Row-by-row Bronze iteration in `process_gl_phase` — replaced by pre-aggregation step

## What is unchanged

- `find_bh_sale/2` and `find_bh_sale_espp/3`
- `find_tranche_by_date/2`
- `sale_allocation` schema
- Capital Gains queries
- Schedule FA queries
- Manual test lot_key (already includes price)

---

## File

`lib/stock_plan/ingestion/silver_builder.ex` — `process_gl_phase/2` and helpers.
