defmodule StockPlan.History do
  @moduledoc """
  History context — lifetime analysis of RSU/ESPP economics.
  Queries Silver tables in batch; fans out by symbol in Elixir.
  No per-symbol query loops.
  """

  alias StockPlan.Repo
  alias StockPlan.Schema.{Ingestion, Origin, Tranche, Sale, SaleAllocation, Holding}
  alias StockPlan.{Portfolio, StockPrice, FX}
  alias StockPlan.Finance.XIRR
  import Ecto.Query
  require Logger

  @spec build(String.t()) :: map()
  def build(account_id) do
    symbols = Portfolio.owned_symbols(account_id)

    if symbols == [] do
      %{symbols: [], prices: %{}, prices_fetched_at: DateTime.utc_now(), rsu: %{}, espp: %{}}
    else
      current_prices = Map.new(symbols, fn s -> {s, StockPrice.current_price(s)} end)
      current_fx = FX.current_rate()
      today = Date.utc_today()

      {origins, tranches, sales} = load_raw_data(account_id)
      origins_by_id = Map.new(origins, &{&1.id, &1})
      holdings_vest_map = load_holdings_vest_map(account_id)
      tranches = enrich_unvested_qty(tranches, origins_by_id, holdings_vest_map)

      per_symbol =
        Map.new(symbols, fn symbol ->
          sym_origins = Enum.filter(origins, &(&1.symbol == symbol))

          sym_tranches =
            Enum.filter(tranches, fn t ->
              o = origins_by_id[t.origin_id]
              o != nil and o.symbol == symbol
            end)

          sym_sales = Enum.filter(sales, &(&1.symbol == symbol))
          price = current_prices[symbol]

          {symbol,
           %{
             rsu: compute_rsu_analysis(sym_origins, sym_tranches, price, current_fx),
             espp:
               compute_espp_analysis(
                 sym_origins,
                 sym_tranches,
                 sym_sales,
                 price,
                 current_fx,
                 today
               )
           }}
        end)

      %{
        symbols: symbols,
        prices: current_prices,
        prices_fetched_at: DateTime.utc_now(),
        rsu: Map.new(per_symbol, fn {s, d} -> {s, d.rsu} end),
        espp: Map.new(per_symbol, fn {s, d} -> {s, d.espp} end)
      }
    end
  end

  # ============================================================
  # Data loading — 3 queries, no per-symbol loops
  # ============================================================

  defp load_raw_data(account_id) do
    origins =
      Repo.all(
        from o in Origin,
          join: i in Ingestion,
          on: i.ingestion_id == o.ingestion_id,
          where: i.account_id == ^account_id and i.status == "ACTIVE",
          select: o
      )

    origin_ids = Enum.map(origins, & &1.id)

    tranches =
      if origin_ids == [],
        do: [],
        else: Repo.all(from t in Tranche, where: t.origin_id in ^origin_ids, select: t)

    sales = fetch_sales_with_allocations(origin_ids)
    {origins, tranches, sales}
  end

  defp fetch_sales_with_allocations([]), do: []

  defp fetch_sales_with_allocations(origin_ids) do
    sales = Repo.all(from s in Sale, where: s.origin_id in ^origin_ids, select: s)

    if sales == [] do
      []
    else
      sale_ids = Enum.map(sales, & &1.id)

      allocs =
        Repo.all(
          from a in SaleAllocation,
            join: t in Tranche,
            on: a.tranche_id == t.id,
            where: a.sale_id in ^sale_ids,
            select: %{
              sale_id: a.sale_id,
              tranche_id: a.tranche_id,
              quantity: a.quantity,
              origin_id: t.origin_id,
              vest_date: t.vest_date
            }
        )

      allocs_by_sale = Enum.group_by(allocs, & &1.sale_id)

      Enum.map(sales, fn s ->
        s |> Map.from_struct() |> Map.put(:allocations, allocs_by_sale[s.id] || [])
      end)
    end
  end

  # ============================================================
  # RSU analysis — income lens (§G)
  # ============================================================

  defp compute_rsu_analysis(origins, tranches, current_price, current_fx) do
    rsu_origins = Enum.filter(origins, &(&1.plan_type == "RSU"))

    if rsu_origins == [] do
      nil
    else
      %{
        summary: compute_rsu_summary(rsu_origins, tranches, current_price, current_fx),
        grants: compute_grant_rows(rsu_origins, tranches, current_price),
        income_by_year: compute_rsu_income_by_year(rsu_origins, tranches),
        grants_by_year: compute_grants_by_year(rsu_origins, current_fx)
      }
    end
  end

  defp compute_rsu_summary(rsu_origins, tranches, current_price, current_fx) do
    rsu_ids = MapSet.new(rsu_origins, & &1.id)

    vested =
      Enum.filter(tranches, &(&1.status == "VESTED" and MapSet.member?(rsu_ids, &1.origin_id)))

    unvested =
      Enum.filter(tranches, &(&1.status == "UNVESTED" and MapSet.member?(rsu_ids, &1.origin_id)))

    grant_count = length(rsu_origins)

    grant_promise_usd =
      Enum.reduce(rsu_origins, d0(), fn o, acc ->
        qty = o.total_quantity || d0()
        fmv = o.origin_fmv || d0()
        Decimal.add(acc, Decimal.mult(qty, fmv))
      end)

    income_recognized_usd =
      sum_product(vested, & &1.vest_quantity, fn t -> t.vest_fmv || t.vest_day_close end)

    vested_net_shares = sum_decimal(vested, & &1.net_quantity)
    unvested_gross_shares = sum_decimal(unvested, & &1.vest_quantity)

    still_to_vest_usd =
      if current_price do
        cp = safe_decimal(current_price)
        sum_decimal(unvested, fn t -> maybe_mul(t.vest_quantity, cp) end)
      end

    vest_vs_grant_drift_pct = compute_vest_vs_grant_drift(rsu_origins, tranches)

    %{
      grant_count: grant_count,
      grant_promise_usd: grant_promise_usd,
      grant_promise_inr: to_inr(grant_promise_usd, current_fx),
      income_recognized_usd: income_recognized_usd,
      income_recognized_inr: to_inr(income_recognized_usd, current_fx),
      still_to_vest_usd: still_to_vest_usd,
      still_to_vest_inr: to_inr(still_to_vest_usd, current_fx),
      vested_net_shares: vested_net_shares,
      unvested_gross_shares: unvested_gross_shares,
      vest_vs_grant_drift_pct: vest_vs_grant_drift_pct
    }
  end

  # drift = (income_recognized / vested_promise_at_grant - 1) × 100
  # vested_promise_at_grant = Σ (vested_gross_qty / granted_qty) × grant_promise per grant
  defp compute_vest_vs_grant_drift(rsu_origins, tranches) do
    tranches_by_origin = Enum.group_by(tranches, & &1.origin_id)

    {income, promise} =
      Enum.reduce(rsu_origins, {d0(), d0()}, fn o, {inc_acc, prom_acc} ->
        o_tranches = tranches_by_origin[o.id] || []
        vested = Enum.filter(o_tranches, &(&1.status == "VESTED"))

        vested_gross = sum_decimal(vested, & &1.vest_quantity)

        vest_income =
          sum_product(vested, & &1.vest_quantity, fn t -> t.vest_fmv || t.vest_day_close end)

        vested_promise =
          if o.total_quantity && o.origin_fmv && Decimal.gt?(o.total_quantity, d0()) do
            grant_promise = Decimal.mult(o.total_quantity, o.origin_fmv)
            Decimal.div(vested_gross, o.total_quantity) |> Decimal.mult(grant_promise)
          else
            d0()
          end

        {Decimal.add(inc_acc, vest_income), Decimal.add(prom_acc, vested_promise)}
      end)

    if Decimal.gt?(promise, d0()) do
      Decimal.div(income, promise)
      |> Decimal.sub(Decimal.new(1))
      |> Decimal.mult(Decimal.new(100))
    end
  end

  defp compute_rsu_income_by_year(rsu_origins, tranches) do
    rsu_ids = MapSet.new(rsu_origins, & &1.id)
    today = Date.utc_today()
    # Current FY start: Apr 1 of this year if we're in/after April, else Apr 1 of last year
    current_fy_start =
      if today.month >= 4, do: today.year, else: today.year - 1

    tranches
    |> Enum.filter(&(&1.status == "VESTED" and MapSet.member?(rsu_ids, &1.origin_id)))
    |> Enum.group_by(fn t ->
      # FY start year: Apr-Mar window
      if t.vest_date.month >= 4, do: t.vest_date.year, else: t.vest_date.year - 1
    end)
    |> Enum.reject(fn {fy_start, _} -> fy_start >= current_fy_start end)
    |> Enum.map(fn {fy_start, rows} ->
      value_inr =
        Enum.reduce(rows, d0(), fn t, acc ->
          qty = t.vest_quantity || d0()
          fmv = t.vest_fmv || t.vest_day_close || d0()
          fx = t.vest_fx_rate || d0()
          Decimal.add(acc, qty |> Decimal.mult(fmv) |> Decimal.mult(fx))
        end)

      fy_end_short = rem(fy_start + 1, 100) |> Integer.to_string() |> String.pad_leading(2, "0")

      %{
        year: "FY #{fy_start}-#{fy_end_short}",
        value_usd:
          sum_product(rows, & &1.vest_quantity, fn t -> t.vest_fmv || t.vest_day_close end),
        value_inr: value_inr
      }
    end)
    |> Enum.sort_by(& &1.year)
  end

  defp compute_grants_by_year(rsu_origins, current_fx) do
    rsu_origins
    |> Enum.group_by(& &1.origin_date.year)
    |> Enum.map(fn {year, origins} ->
      value_usd =
        Enum.reduce(origins, d0(), fn o, acc ->
          qty = o.total_quantity || d0()
          fmv = o.origin_fmv || d0()
          Decimal.add(acc, Decimal.mult(qty, fmv))
        end)

      %{year: year, value_usd: value_usd, value_inr: to_inr(value_usd, current_fx)}
    end)
    |> Enum.sort_by(& &1.year)
  end

  defp compute_grant_rows(rsu_origins, tranches, current_price) do
    cp = safe_decimal(current_price)
    tranches_by_origin = Enum.group_by(tranches, & &1.origin_id)

    rsu_origins
    |> Enum.map(fn o ->
      o_tranches = tranches_by_origin[o.id] || []
      vested = Enum.filter(o_tranches, &(&1.status == "VESTED"))
      unvested = Enum.filter(o_tranches, &(&1.status == "UNVESTED"))

      grant_promise_usd =
        if o.total_quantity && o.origin_fmv,
          do: Decimal.mult(o.total_quantity, o.origin_fmv),
          else: d0()

      recognized_usd =
        sum_product(vested, & &1.vest_quantity, fn t -> t.vest_fmv || t.vest_day_close end)

      still_to_vest_usd =
        if cp do
          sum_decimal(unvested, fn t -> maybe_mul(t.vest_quantity, cp) end)
        end

      vested_qty = sum_decimal(vested, & &1.vest_quantity)

      vested_pct =
        if o.total_quantity && Decimal.gt?(o.total_quantity, d0()) do
          Decimal.div(vested_qty, o.total_quantity) |> Decimal.mult(Decimal.new(100))
        end

      %{
        grant_number: o.grant_number,
        grant_date: o.origin_date,
        granted_qty: o.total_quantity,
        grant_promise_usd: grant_promise_usd,
        recognized_usd: recognized_usd,
        still_to_vest_usd: still_to_vest_usd,
        vested_pct: vested_pct
      }
    end)
    |> Enum.sort_by(& &1.grant_date, {:desc, Date})
  end

  # ============================================================
  # ESPP analysis
  # ============================================================

  defp compute_espp_analysis(origins, tranches, sales, current_price, current_fx, today) do
    espp_origins = Enum.filter(origins, &(&1.plan_type == "ESPP"))

    if espp_origins == [] do
      empty_espp()
    else
      espp_ids = MapSet.new(espp_origins, & &1.id)
      espp_origins_map = Map.new(espp_origins, &{&1.id, &1})

      espp_tranches =
        Enum.filter(tranches, &(&1.status == "VESTED" and MapSet.member?(espp_ids, &1.origin_id)))

      tranche_ids = Enum.map(espp_tranches, & &1.id)
      allocs_by_tranche = load_espp_allocs_by_tranche(tranche_ids)
      espp_sales = Enum.filter(sales, &MapSet.member?(espp_ids, &1.origin_id))

      cp = safe_decimal(current_price)
      lots = build_espp_lots(espp_tranches, espp_origins_map, allocs_by_tranche, cp, espp_sales)

      sold_lots = Enum.filter(lots, fn l -> Decimal.gt?(l.sold_qty, d0()) end)
      unsold_lots = Enum.filter(lots, fn l -> Decimal.gt?(l.held_qty, d0()) end)

      gross_purchased = sum_decimal(espp_tranches, & &1.vest_quantity)
      net_received = sum_decimal(espp_tranches, & &1.net_quantity)
      tax_withheld = safe_sub(gross_purchased, net_received)
      currently_held = sum_decimal(lots, & &1.held_qty)

      purchase_value = sum_decimal(lots, fn l -> maybe_mul(l.gross_shares, l.buy_price) end)

      # Net discount: (vest_fmv − buy_price) × net_shares (not gross)
      net_discount =
        sum_decimal(lots, fn l ->
          if l.purchase_fmv && l.buy_price && l.net_shares,
            do: Decimal.mult(Decimal.sub(l.purchase_fmv, l.buy_price), l.net_shares),
            else: d0()
        end)

      realized_proceeds = sum_lots_nullable(lots, :realized_proceeds)
      realized_pnl = sum_lots_nullable(lots, :realized_pnl)
      unrealized_pnl = sum_lots_nullable(lots, :unrealized_pnl)

      total_pnl =
        case {realized_pnl, unrealized_pnl} do
          {nil, nil} -> nil
          {r, u} -> Decimal.add(r || d0(), u || d0())
        end

      total_return_pct =
        if total_pnl && Decimal.gt?(purchase_value, d0()) do
          Decimal.div(total_pnl, purchase_value) |> Decimal.mult(Decimal.new(100))
        end

      sell_on_purchase = sum_decimal(lots, fn l -> l.if_sold_at_purchase || d0() end)
      xirr = compute_espp_xirr_from_lots(lots, cp, today)
      qual = compute_qualifying_split_from_lots(lots)
      {avg_return_pct, avg_day1_return_pct} = compute_avg_lot_returns(lots)

      %{
        summary: %{
          gross_purchased: gross_purchased,
          net_received: net_received,
          tax_withheld: tax_withheld,
          currently_held: currently_held,
          purchase_value_usd: purchase_value,
          purchase_value_inr: to_inr(purchase_value, current_fx),
          net_discount_usd: net_discount,
          net_discount_inr: to_inr(net_discount, current_fx),
          realized_proceeds_usd: realized_proceeds,
          realized_proceeds_inr: to_inr(realized_proceeds, current_fx),
          realized_pnl_usd: realized_pnl,
          realized_pnl_inr: to_inr(realized_pnl, current_fx),
          unrealized_pnl_usd: unrealized_pnl,
          unrealized_pnl_inr: to_inr(unrealized_pnl, current_fx),
          total_pnl_usd: total_pnl,
          total_pnl_inr: to_inr(total_pnl, current_fx),
          total_return_pct: total_return_pct,
          avg_return_pct: avg_return_pct,
          avg_day1_return_pct: avg_day1_return_pct,
          sell_on_purchase_usd: sell_on_purchase,
          sell_on_purchase_inr: to_inr(sell_on_purchase, current_fx),
          approximate_xirr: xirr
        },
        current_price: cp,
        lots: lots,
        sold_lots: sold_lots,
        unsold_lots: unsold_lots,
        qualifying_count: qual.qualifying_count,
        disqualifying_count: qual.disqualifying_count,
        qualifying_proceeds_usd: qual.qualifying_proceeds,
        disqualifying_proceeds_usd: qual.disqualifying_proceeds
      }
    end
  end

  defp empty_espp do
    %{
      summary: %{
        gross_purchased: d0(),
        net_received: d0(),
        tax_withheld: d0(),
        currently_held: d0(),
        purchase_value_usd: d0(),
        purchase_value_inr: nil,
        net_discount_usd: d0(),
        net_discount_inr: nil,
        realized_proceeds_usd: nil,
        realized_proceeds_inr: nil,
        realized_pnl_usd: nil,
        realized_pnl_inr: nil,
        unrealized_pnl_usd: nil,
        unrealized_pnl_inr: nil,
        total_pnl_usd: nil,
        total_pnl_inr: nil,
        total_return_pct: nil,
        avg_return_pct: nil,
        avg_day1_return_pct: nil,
        sell_on_purchase_usd: d0(),
        sell_on_purchase_inr: nil,
        approximate_xirr: nil
      },
      current_price: nil,
      lots: [],
      sold_lots: [],
      unsold_lots: [],
      qualifying_count: 0,
      disqualifying_count: 0,
      qualifying_proceeds_usd: d0(),
      disqualifying_proceeds_usd: d0()
    }
  end

  # Load SaleAllocations keyed by tranche_id.
  # COALESCE prefers the G&L-confirmed allocation price; falls back to Yahoo price on Sale.
  defp load_espp_allocs_by_tranche([]), do: %{}

  defp load_espp_allocs_by_tranche(tranche_ids) do
    Repo.all(
      from a in SaleAllocation,
        join: s in Sale,
        on: s.id == a.sale_id,
        where: a.tranche_id in ^tranche_ids,
        select: %{
          tranche_id: a.tranche_id,
          sold_qty: a.quantity,
          sale_price: fragment("COALESCE(?, ?)", a.sale_price, s.sale_price),
          sale_date: s.sale_date,
          symbol: s.symbol
        }
    )
    |> Enum.map(fn alloc ->
      price = alloc.sale_price || yahoo_price_safe(alloc.symbol, alloc.sale_date)
      %{alloc | sale_price: price}
    end)
    |> Enum.group_by(& &1.tranche_id)
  end

  defp yahoo_price_safe(symbol, date) when is_binary(symbol) and not is_nil(date) do
    try do
      StockPrice.get_close(symbol, date)
    rescue
      e ->
        Logger.warning(
          "Yahoo price fetch failed for #{symbol} on #{date} (history fallback): #{Exception.message(e)}"
        )

        nil
    end
  end

  defp yahoo_price_safe(_, _), do: nil

  defp build_espp_lots(tranches, origins_map, allocs_by_tranche, current_price, bh_sales) do
    Enum.map(tranches, fn t ->
      origin = origins_map[t.origin_id]
      meta = parse_metadata(t.metadata_json)
      buy_price = safe_decimal(meta["buy_price"])
      lookback_price = origin && origin.origin_fmv

      # Prefer G&L SaleAllocations (confirmed execution price).
      # Fall back to BH Sales: Yahoo close stored at ingestion time gives qty + proxy price.
      allocs = allocs_by_tranche[t.id] || []

      {sold_qty, allocs} =
        if allocs != [] do
          {sum_decimal(allocs, & &1.sold_qty), allocs}
        else
          bh_allocs = bh_allocs_for_tranche(bh_sales, t.origin_id, t.vest_date)
          {sum_decimal(bh_allocs, & &1.sold_qty), bh_allocs}
        end

      held_qty = safe_sub(t.net_quantity, sold_qty)

      # net_buy_price: read from metadata (persisted since Task 8). Fallback for old ingestions.
      net_buy_price =
        safe_decimal(meta["net_buy_price"]) ||
          compute_net_buy_price_fallback(buy_price, t.vest_quantity, t.net_quantity)

      sale_price =
        allocs
        |> Enum.reject(&is_nil(&1.sale_price))
        |> List.first()
        |> then(&(&1 && &1.sale_price))

      sale_date = allocs |> List.first() |> then(&(&1 && &1.sale_date))

      discount_pct =
        if buy_price && t.vest_fmv && Decimal.gt?(buy_price, d0()),
          do:
            Decimal.div(Decimal.sub(t.vest_fmv, buy_price), buy_price)
            |> Decimal.mult(Decimal.new(100))

      # total_discount: context field (plan benefit) — uses buy_price × gross_shares
      total_discount =
        if buy_price && t.vest_fmv && t.vest_quantity,
          do: Decimal.mult(Decimal.sub(t.vest_fmv, buy_price), t.vest_quantity)

      # All P&L math uses net_buy_price
      realized_pnl =
        if net_buy_price && Decimal.gt?(sold_qty, d0()) do
          result =
            Enum.reduce(allocs, d0(), fn a, acc ->
              sp = a.sale_price
              sq = a.sold_qty

              if sp && sq,
                do: Decimal.add(acc, Decimal.mult(Decimal.sub(sp, net_buy_price), sq)),
                else: acc
            end)

          if Decimal.gt?(result, d0()) or Decimal.lt?(result, d0()), do: result
        end

      realized_proceeds =
        if Decimal.gt?(sold_qty, d0()) do
          result =
            Enum.reduce(allocs, d0(), fn a, acc ->
              sp = a.sale_price
              sq = a.sold_qty
              if sp && sq, do: Decimal.add(acc, Decimal.mult(sp, sq)), else: acc
            end)

          if Decimal.gt?(result, d0()), do: result
        end

      pnl_pct =
        if realized_pnl && net_buy_price && Decimal.gt?(sold_qty, d0()) do
          cost_of_sold = Decimal.mult(net_buy_price, sold_qty)

          if Decimal.gt?(cost_of_sold, d0()),
            do: Decimal.div(realized_pnl, cost_of_sold) |> Decimal.mult(Decimal.new(100))
        end

      unrealized_pnl =
        if current_price && net_buy_price && Decimal.gt?(held_qty, d0()),
          do: Decimal.mult(Decimal.sub(current_price, net_buy_price), held_qty)

      %{
        purchase_date: t.vest_date,
        grant_date: origin && origin.origin_date,
        lookback_price: lookback_price,
        buy_price: buy_price,
        net_buy_price: net_buy_price,
        purchase_fmv: t.vest_fmv,
        discount_pct: discount_pct,
        gross_shares: t.vest_quantity,
        net_shares: t.net_quantity,
        tax_shares: t.tax_withheld_qty,
        sold_qty: sold_qty,
        held_qty: held_qty,
        allocs: allocs,
        sale_date: sale_date,
        sale_price: sale_price,
        if_sold_at_purchase: maybe_mul(t.vest_fmv, t.net_quantity),
        realized_pnl: realized_pnl,
        realized_proceeds: realized_proceeds,
        pnl_pct: pnl_pct,
        unrealized_pnl: unrealized_pnl,
        total_discount: total_discount
      }
    end)
    |> Enum.sort_by(& &1.purchase_date, Date)
  end

  # Fallback net_buy_price for tranches ingested before Task 8 (no metadata key yet).
  defp compute_net_buy_price_fallback(buy_price, gross, net)
       when not is_nil(buy_price) and not is_nil(gross) and not is_nil(net) do
    if Decimal.gt?(net, d0()) and not Decimal.equal?(gross, net),
      do: Decimal.div(Decimal.mult(buy_price, gross), net),
      else: buy_price
  end

  defp compute_net_buy_price_fallback(buy_price, _gross, _net), do: buy_price

  # Average per-lot return %: equal-weighted across lots (not value-weighted).
  # Returns {avg_total_pnl_pct, avg_day1_pct} where day-1 = exit at purchase-day FMV.
  defp compute_avg_lot_returns(lots) do
    d0 = d0()
    hundred = Decimal.new(100)

    {pnl_pcts, day1_pcts} =
      Enum.reduce(lots, {[], []}, fn l, {pnls, d1s} ->
        cost = if l.net_buy_price && l.net_shares, do: Decimal.mult(l.net_buy_price, l.net_shares)

        total_pnl_lot =
          case {l.realized_pnl, l.unrealized_pnl} do
            {nil, nil} -> nil
            {r, u} -> Decimal.add(r || d0, u || d0)
          end

        pnl_pct =
          if total_pnl_lot && cost && Decimal.gt?(cost, d0),
            do: Decimal.mult(Decimal.div(total_pnl_lot, cost), hundred)

        day1_pct =
          if l.if_sold_at_purchase && cost && Decimal.gt?(cost, d0),
            do: Decimal.mult(Decimal.div(Decimal.sub(l.if_sold_at_purchase, cost), cost), hundred)

        {
          if(pnl_pct, do: [pnl_pct | pnls], else: pnls),
          if(day1_pct, do: [day1_pct | d1s], else: d1s)
        }
      end)

    avg = fn
      [] -> nil
      vals -> Decimal.div(Enum.reduce(vals, d0, &Decimal.add/2), Decimal.new(length(vals)))
    end

    {avg.(pnl_pcts), avg.(day1_pcts)}
  end

  defp compute_espp_xirr_from_lots(lots, current_price, today) do
    flows =
      Enum.flat_map(lots, fn l ->
        outflow =
          if l.buy_price && l.gross_shares && Decimal.gt?(l.gross_shares, d0()) do
            amt = -(Decimal.mult(l.buy_price, l.gross_shares) |> Decimal.to_float())
            [{l.purchase_date, amt}]
          else
            []
          end

        sale_inflows =
          Enum.flat_map(l.allocs, fn a ->
            sp = safe_decimal(a.sale_price)
            sq = a.sold_qty

            if sp && sq && a.sale_date && Decimal.gt?(sq, d0()) do
              [{a.sale_date, Decimal.mult(sp, sq) |> Decimal.to_float()}]
            else
              []
            end
          end)

        held_inflow =
          if current_price && Decimal.gt?(l.held_qty, d0()) do
            [{today, Decimal.mult(current_price, l.held_qty) |> Decimal.to_float()}]
          else
            []
          end

        outflow ++ sale_inflows ++ held_inflow
      end)

    case XIRR.xirr(flows) do
      {:ok, rate} -> rate
      {:error, _} -> nil
    end
  end

  defp compute_qualifying_split_from_lots(lots) do
    Enum.reduce(
      lots,
      %{
        qualifying_count: 0,
        disqualifying_count: 0,
        qualifying_proceeds: d0(),
        disqualifying_proceeds: d0()
      },
      fn lot, acc ->
        if lot.sale_date && lot.grant_date && Decimal.gt?(lot.sold_qty, d0()) do
          years_from_grant = Date.diff(lot.sale_date, lot.grant_date) / 365.25
          years_from_purchase = Date.diff(lot.sale_date, lot.purchase_date) / 365.25
          qualifying = years_from_grant >= 2.0 and years_from_purchase >= 1.0
          proceeds = maybe_mul(lot.sale_price, lot.sold_qty) || d0()

          if qualifying do
            %{
              acc
              | qualifying_count: acc.qualifying_count + 1,
                qualifying_proceeds: Decimal.add(acc.qualifying_proceeds, proceeds)
            }
          else
            %{
              acc
              | disqualifying_count: acc.disqualifying_count + 1,
                disqualifying_proceeds: Decimal.add(acc.disqualifying_proceeds, proceeds)
            }
          end
        else
          acc
        end
      end
    )
  end

  # Returns alloc-like maps from BH Sales for a specific purchase lot.
  defp bh_allocs_for_tranche(sales, origin_id, purchase_date) do
    sales
    |> Enum.filter(fn s ->
      s.origin_id == origin_id and parse_purchase_date_from_metadata(s) == purchase_date
    end)
    |> Enum.map(fn s ->
      %{
        tranche_id: nil,
        sold_qty: s.total_quantity,
        sale_price: s.sale_price,
        sale_date: s.sale_date,
        symbol: s.symbol
      }
    end)
  end

  defp parse_purchase_date_from_metadata(%{metadata_json: json}) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"purchase_date" => date_str}} when is_binary(date_str) ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> date
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_purchase_date_from_metadata(_), do: nil

  # ============================================================
  # Helpers
  # ============================================================

  defp d0, do: Decimal.new(0)

  defp safe_decimal(nil), do: nil
  defp safe_decimal(v) when is_binary(v), do: Decimal.new(v)
  defp safe_decimal(%Decimal{} = v), do: v

  defp sum_decimal(list, fun) do
    Enum.reduce(list, d0(), fn item, acc ->
      Decimal.add(acc, fun.(item) || d0())
    end)
  end

  defp sum_product(list, f1, f2) do
    Enum.reduce(list, d0(), fn item, acc ->
      a = f1.(item)
      b = f2.(item)
      if a && b, do: Decimal.add(acc, Decimal.mult(a, b)), else: acc
    end)
  end

  defp safe_sub(a, b), do: Decimal.sub(a || d0(), b || d0())

  defp maybe_mul(nil, _), do: nil
  defp maybe_mul(_, nil), do: nil
  defp maybe_mul(a, b), do: Decimal.mult(a, b)

  defp to_inr(nil, _), do: nil
  defp to_inr(_, nil), do: nil
  defp to_inr(usd, fx), do: Decimal.mult(usd, fx)

  defp sum_lots_nullable(lots, field) do
    vals = Enum.map(lots, &Map.get(&1, field))

    if Enum.all?(vals, &is_nil/1),
      do: nil,
      else: Enum.reduce(vals, d0(), &Decimal.add(&2, &1 || d0()))
  end

  defp parse_metadata(nil), do: %{}

  defp parse_metadata(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  # UNVESTED tranches from BH have null vest_quantity — Holdings has the scheduled qty.
  # Build a {grant_number, vest_date} → vested_qty map from Holdings for enrichment.
  defp load_holdings_vest_map(account_id) do
    Repo.all(
      from h in Holding,
        join: i in Ingestion,
        on: i.ingestion_id == h.ingestion_id,
        where:
          h.account_id == ^account_id and i.status == "ACTIVE" and
            h.plan_type == "RSU" and h.status == "UNVESTED" and
            not is_nil(h.vested_qty),
        select: {h.grant_number, h.vest_date, h.vested_qty}
    )
    |> Map.new(fn {gn, vd, qty} -> {{gn, vd}, qty} end)
  end

  defp enrich_unvested_qty(tranches, _origins_by_id, holdings_vest_map)
       when map_size(holdings_vest_map) == 0,
       do: tranches

  defp enrich_unvested_qty(tranches, origins_by_id, holdings_vest_map) do
    Enum.map(tranches, fn t ->
      if t.vest_quantity == nil and t.status == "UNVESTED" do
        origin = origins_by_id[t.origin_id]
        key = origin && {origin.grant_number, t.vest_date}
        qty = key && Map.get(holdings_vest_map, key)
        if qty, do: %{t | vest_quantity: qty}, else: t
      else
        t
      end
    end)
  end
end
