defmodule StockPlan.Ingestion.SilverBuilder do
  @moduledoc false

  alias StockPlan.Repo
  alias StockPlan.Schema.{Ingestion, Origin, Tranche, Exercise, Sale, SaleAllocation, BronzeRaw}
  alias StockPlan.Ingestion.ValueNormalizer, as: VN
  alias StockPlan.ID
  import Ecto.Query
  require Logger

  @spec build(String.t()) :: {:ok, map()} | {:error, atom()}
  def build(account_id) do
    with {:ok, bh_ings} <- find_benefit_histories(account_id) do
      gl_ingestions = find_gl_ingestions(account_id)

      Repo.transaction(fn ->
        delete_silver(account_id)

        # Phase 1: Benefit History → origins, tranches, sales (per BH ingestion)
        phase1_counts =
          Enum.reduce(bh_ings, zero_phase1(), fn bh_ing, acc ->
            bh_rows = load_bronze(bh_ing.ingestion_id)
            counts = process_all_sheets(bh_ing, bh_rows)

            %{
              origins: acc.origins + counts.origins,
              tranches: acc.tranches + counts.tranches,
              sales: acc.sales + counts.sales,
              allocations: acc.allocations + counts.allocations,
              warnings: acc.warnings ++ counts.warnings
            }
          end)

        # Phase 2: G&L → enrich tranches, update sales, create RSU allocations
        # G&L spans all symbols and matches against tranches across all BH ingestions.
        {gl_counts, gl_warnings} = process_gl_phase(hd(bh_ings), gl_ingestions)

        # Phase 3: FX rates → fill origin_fx_rate, vest_fx_rate, sale_fx_rate
        fx_counts = enrich_fx_rates(account_id)

        # Phase 4: Stock prices → fill vest_day_close on VESTED tranches + origin_fmv on RSU origins
        stock_counts = enrich_stock_prices(account_id)
        enrich_rsu_origin_fmv(account_id)

        %{
          origins: phase1_counts.origins,
          tranches: phase1_counts.tranches,
          sales: phase1_counts.sales + gl_counts.sales_created,
          allocations: phase1_counts.allocations + gl_counts.allocations_created,
          updated_tranches: gl_counts.updated_tranches,
          matched_sales: gl_counts.matched_sales,
          fx_enriched: fx_counts,
          stock_prices_enriched: stock_counts,
          warnings: phase1_counts.warnings ++ gl_warnings
        }
      end)
    end
  end

  defp zero_phase1, do: %{origins: 0, tranches: 0, sales: 0, allocations: 0, warnings: []}

  defp find_benefit_histories(account_id) do
    bh_list =
      Repo.all(
        from i in Ingestion,
          where:
            i.account_id == ^account_id and i.status == "ACTIVE" and
              i.category == "BENEFIT_HISTORY",
          order_by: i.inserted_at
      )

    case bh_list do
      [] -> {:error, :no_benefit_history}
      ings -> {:ok, ings}
    end
  end

  defp find_gl_ingestions(account_id) do
    Repo.all(
      from i in Ingestion,
        where:
          i.account_id == ^account_id and i.status == "ACTIVE" and i.category == "GL_EXPANDED"
    )
  end

  defp delete_silver(account_id) do
    sale_ids = Repo.all(from s in Sale, where: s.account_id == ^account_id, select: s.id)
    Repo.delete_all(from a in SaleAllocation, where: a.sale_id in ^sale_ids)
    Repo.delete_all(from s in Sale, where: s.account_id == ^account_id)

    origin_ids = Repo.all(from o in Origin, where: o.account_id == ^account_id, select: o.id)
    tranche_ids = Repo.all(from t in Tranche, where: t.origin_id in ^origin_ids, select: t.id)
    Repo.delete_all(from e in Exercise, where: e.tranche_id in ^tranche_ids)
    Repo.delete_all(from t in Tranche, where: t.origin_id in ^origin_ids)
    Repo.delete_all(from o in Origin, where: o.account_id == ^account_id)
  end

  defp load_bronze(ingestion_id) do
    Repo.all(
      from r in BronzeRaw,
        where: r.ingestion_id == ^ingestion_id,
        order_by: [asc: r.sheet_name, asc: r.row_index]
    )
  end

  defp process_all_sheets(ing, bronze_rows) do
    grouped = Enum.group_by(bronze_rows, & &1.sheet_name)
    warnings = []

    {rsu_counts, w1} = process_rsu(ing, Map.get(grouped, "Restricted Stock", []))
    {espp_counts, w2} = process_espp(ing, Map.get(grouped, "ESPP", []))
    {esop_counts, w3} = process_esop(ing, Map.get(grouped, "Options", []))

    %{
      origins: rsu_counts.origins + espp_counts.origins + esop_counts.origins,
      tranches: rsu_counts.tranches + espp_counts.tranches + esop_counts.tranches,
      sales: rsu_counts.sales + espp_counts.sales + esop_counts.sales,
      allocations: rsu_counts.allocations + espp_counts.allocations + esop_counts.allocations,
      warnings: warnings ++ w1 ++ w2 ++ w3
    }
  end

  # --- RSU Processing ---

  defp process_rsu(_ing, []), do: {zero_counts(), []}

  defp process_rsu(ing, rows) do
    groups = group_by_parent(rows)
    warnings = []

    counts =
      Enum.reduce(groups, zero_counts(), fn {parent, children}, acc ->
        data = Jason.decode!(parent.raw_row_json)

        origin =
          insert_origin!(ing, %{
            symbol: data["Symbol"],
            plan_type: "RSU",
            grant_number: data["Grant Number"],
            origin_date: VN.parse_date(data["Grant Date"]),
            total_quantity: VN.clean_number(data["Granted Qty."]),
            origin_fmv: nil,
            status: data["Status"],
            metadata_json: nil
          })

        {tranche_count, sale_count} = process_rsu_children(ing, origin, children)

        %{
          acc
          | origins: acc.origins + 1,
            tranches: acc.tranches + tranche_count,
            sales: acc.sales + sale_count
        }
      end)

    {counts, warnings}
  end

  defp process_rsu_children(ing, origin, children) do
    vest_schedules = Enum.filter(children, &(&1.record_type == "Vest Schedule"))
    events = Enum.filter(children, &(&1.record_type == "Event"))

    # Create UNVESTED tranches from vest schedule
    tranches =
      Enum.map(vest_schedules, fn row ->
        data = Jason.decode!(row.raw_row_json)
        vest_date = VN.parse_date(data["Vest Date"])
        vesting_qty = VN.clean_number(data["Vesting Qty"])

        if vest_date do
          insert_tranche!(ing, origin, %{
            vest_date: vest_date,
            vest_quantity: vesting_qty,
            status: "UNVESTED"
          })
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Group events by date for vest/release pairing
    events_by_date =
      events
      |> Enum.map(fn row -> {row, Jason.decode!(row.raw_row_json)} end)
      |> Enum.group_by(fn {_, data} -> VN.parse_date(data["Date"]) end)

    vest_count = length(tranches)

    {extra_tranches, sale_count} =
      Enum.reduce(events_by_date, {0, 0}, fn {date, event_rows}, {t_acc, s_acc} ->
        typed =
          Enum.map(event_rows, fn {_row, data} ->
            {data["Event Type"], VN.clean_number(data["Qty. or Amount"]), data}
          end)

        vested_qty = sum_qty(typed, "Shares vested")
        released_qty = sum_qty(typed, "Shares released")
        sold_events = Enum.filter(typed, fn {type, _, _} -> type == "Shares sold" end)

        # Update or create tranche for vest/release pair
        t_extra =
          if vested_qty do
            tranche = find_tranche_in_list(tranches, date)

            if tranche do
              update_tranche_vested!(tranche, vested_qty, released_qty)
              0
            else
              # No vest schedule entry — create tranche from event
              insert_tranche!(ing, origin, %{
                vest_date: date,
                vest_quantity: vested_qty,
                vest_fmv: nil,
                net_quantity: released_qty,
                tax_withheld_qty: compute_tax(vested_qty, released_qty),
                status: "VESTED"
              })

              1
            end
          else
            0
          end

        # Create sale — aggregate qty across all sold events on this date
        s_new =
          if sold_events != [] and date do
            total_sold =
              Enum.reduce(sold_events, Decimal.new(0), fn {_, qty, _}, acc ->
                if qty, do: Decimal.add(acc, Decimal.new(qty)), else: acc
              end)

            if Decimal.gt?(total_sold, Decimal.new(0)) do
              insert_sale!(ing, origin, %{
                sale_date: date,
                total_quantity: Decimal.to_string(total_sold)
              })

              1
            else
              0
            end
          else
            0
          end

        {t_acc + t_extra, s_acc + s_new}
      end)

    # Mark remaining UNVESTED tranches as FORFEITED when cancellation events exist
    has_cancellations =
      Enum.any?(events, fn row ->
        data = Jason.decode!(row.raw_row_json)
        data["Event Type"] == "Shares canceled"
      end)

    if has_cancellations do
      Repo.update_all(
        from(t in Tranche, where: t.origin_id == ^origin.id and t.status == "UNVESTED"),
        set: [status: "FORFEITED"]
      )
    end

    {vest_count + extra_tranches, sale_count}
  end

  # --- ESPP Processing ---

  defp process_espp(_ing, []), do: {zero_counts(), []}

  defp process_espp(ing, rows) do
    groups = group_by_parent(rows)
    warnings = []

    # Group purchases by Grant Date (enrollment period)
    purchases_by_enrollment =
      Enum.group_by(groups, fn {parent, _children} ->
        data = Jason.decode!(parent.raw_row_json)
        {data["Symbol"], data["Grant Date"]}
      end)

    counts =
      Enum.reduce(purchases_by_enrollment, zero_counts(), fn {{symbol, grant_date_str},
                                                              purchase_groups},
                                                             acc ->
        grant_date = VN.parse_date(grant_date_str)
        first_data = Jason.decode!(elem(hd(purchase_groups), 0).raw_row_json)

        grant_number = compute_espp_grant_number(symbol, grant_date)

        origin =
          insert_origin!(ing, %{
            symbol: symbol,
            plan_type: "ESPP",
            grant_number: grant_number,
            origin_date: grant_date,
            total_quantity: nil,
            origin_fmv: VN.clean_number(first_data["Grant Date FMV"]),
            metadata_json:
              Jason.encode!(%{
                discount_percent: VN.clean_number(first_data["Discount Percent"]),
                qualified_plan: first_data["Qualified Plan?"]
              })
          })

        {tranche_count, sale_count} =
          Enum.reduce(purchase_groups, {0, 0}, fn {parent, children}, {tc, sc} ->
            data = Jason.decode!(parent.raw_row_json)
            purchase_date = VN.parse_date(data["Purchase Date"])
            gross_str = VN.clean_number(data["Purchased Qty."])
            net_str = VN.clean_number(data["Net Shares"])
            buy_price_str = VN.clean_number(data["Purchase Price"])
            net_buy_price_str = compute_net_buy_price(buy_price_str, gross_str, net_str)

            insert_tranche!(ing, origin, %{
              vest_date: purchase_date,
              vest_quantity: gross_str,
              vest_fmv: VN.clean_number(data["Purchase Date FMV"]),
              tax_withheld_qty: VN.clean_number_keep_zero(data["Tax Collection Shares"]),
              net_quantity: net_str,
              status: "VESTED",
              metadata_json:
                Jason.encode!(%{
                  buy_price: buy_price_str,
                  net_buy_price: net_buy_price_str
                })
            })

            # Process SELL events (skip PURCHASE events)
            sell_events =
              children
              |> Enum.filter(&(&1.record_type == "Event"))
              |> Enum.map(fn row -> Jason.decode!(row.raw_row_json) end)
              |> Enum.filter(fn data -> data["Event Type"] == "SELL" end)

            # BH creates Sale records with date + quantity + Yahoo close (as proxy sale price).
            # purchase_date stored in metadata_json so History can match sale → tranche.
            # SaleAllocations are only created by G&L Phase 2 (confirmed execution prices).
            new_sales =
              Enum.reduce(sell_events, 0, fn event_data, sc2 ->
                sale_date = VN.parse_date(event_data["Date"])
                qty = VN.clean_number(event_data["Qty"])

                if sale_date && qty do
                  sale_price = yahoo_close_safe(origin.symbol, sale_date)

                  insert_sale!(ing, origin, %{
                    sale_date: sale_date,
                    total_quantity: qty,
                    sale_price: sale_price,
                    metadata_json:
                      Jason.encode!(%{
                        purchase_date: purchase_date && Date.to_iso8601(purchase_date)
                      })
                  })

                  sc2 + 1
                else
                  sc2
                end
              end)

            {tc + 1, sc + new_sales}
          end)

        %{
          acc
          | origins: acc.origins + 1,
            tranches: acc.tranches + tranche_count,
            sales: acc.sales + sale_count
        }
      end)

    {counts, warnings}
  end

  # --- ESOP Processing (unsupported) ---

  defp process_esop(_ing, []), do: {zero_counts(), []}

  defp process_esop(_ing, _rows) do
    {zero_counts(),
     ["Stock Options (ESOP) detected but not supported. Options data will be skipped."]}
  end

  # --- Helpers ---

  defp group_by_parent(rows) do
    parents = Enum.filter(rows, &(&1.record_type in ["Grant", "Purchase"]))

    Enum.map(parents, fn parent ->
      children = Enum.filter(rows, &(&1.parent_index == parent.row_index))
      {parent, children}
    end)
  end

  defp insert_origin!(ing, attrs) do
    %Origin{}
    |> Origin.changeset(
      Map.merge(attrs, %{
        id: ID.generate(),
        ingestion_id: ing.ingestion_id,
        account_id: ing.account_id,
        currency: "USD"
      })
    )
    |> Repo.insert!()
  end

  defp insert_tranche!(ing, origin, attrs) do
    %Tranche{}
    |> Tranche.changeset(
      Map.merge(attrs, %{
        id: ID.generate(),
        origin_id: origin.id,
        ingestion_id: ing.ingestion_id
      })
    )
    |> Repo.insert!()
  end

  defp insert_sale!(ing, origin, attrs) do
    %Sale{}
    |> Sale.changeset(
      Map.merge(attrs, %{
        id: ID.generate(),
        ingestion_id: ing.ingestion_id,
        origin_id: origin.id,
        account_id: ing.account_id,
        symbol: origin.symbol
      })
    )
    |> Repo.insert!()
  end

  defp update_tranche_vested!(tranche, vested_qty, released_qty) do
    tax = compute_tax(vested_qty, released_qty)

    tranche
    |> Tranche.changeset(%{
      vest_quantity: vested_qty,
      net_quantity: released_qty,
      tax_withheld_qty: tax,
      status: "VESTED"
    })
    |> Repo.update!()
  end

  defp find_tranche_in_list(tranches, date) do
    Enum.find(tranches, fn t -> t.vest_date == date end)
  end

  defp compute_tax(nil, _), do: nil
  defp compute_tax(_, nil), do: nil

  defp compute_tax(vested, released) do
    v = Decimal.new(vested)
    r = Decimal.new(released)
    Decimal.sub(v, r) |> Decimal.to_string()
  end

  defp sum_qty(typed_events, event_type) do
    typed_events
    |> Enum.filter(fn {type, _, _} -> type == event_type end)
    |> Enum.map(fn {_, qty, _} -> qty end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        nil

      qtys ->
        Enum.reduce(qtys, Decimal.new(0), fn q, acc -> Decimal.add(acc, Decimal.new(q)) end)
        |> Decimal.to_string()
    end
  end

  defp compute_espp_grant_number(symbol, %Date{} = grant_date) do
    :crypto.hash(:sha256, "ESPP:#{symbol}:#{Date.to_iso8601(grant_date)}")
    |> Base.encode16(case: :lower)
    |> String.slice(0..15)
  end

  # net_buy_price = (buy_price × gross) / net — effective cost per received share.
  # Falls back to buy_price when there is no tax withholding (gross == net) or data is missing.
  defp compute_net_buy_price(buy_price_str, gross_str, net_str)
       when is_binary(buy_price_str) and is_binary(gross_str) and is_binary(net_str) do
    g = Decimal.new(gross_str)
    n = Decimal.new(net_str)

    if Decimal.gt?(n, Decimal.new(0)) and not Decimal.equal?(g, n) do
      Decimal.div(Decimal.mult(Decimal.new(buy_price_str), g), n) |> Decimal.to_string()
    else
      buy_price_str
    end
  end

  defp compute_net_buy_price(buy_price_str, _gross, _net), do: buy_price_str

  defp zero_counts, do: %{origins: 0, tranches: 0, sales: 0, allocations: 0}

  # --- Phase 2: G&L Enrichment ---

  defp process_gl_phase(_bh_ing, []),
    do: {%{updated_tranches: 0, matched_sales: 0, sales_created: 0, allocations_created: 0}, []}

  defp process_gl_phase(bh_ing, gl_ingestions) do
    aggregated_lots = aggregate_gl_bronze(gl_ingestions)

    Enum.reduce(
      aggregated_lots,
      {%{updated_tranches: 0, matched_sales: 0, sales_created: 0, allocations_created: 0}, []},
      fn lot, {counts, warnings} ->
        case process_aggregated_lot(bh_ing.account_id, lot) do
          {:ok, result} ->
            new_counts = %{
              counts
              | updated_tranches: counts.updated_tranches + result.tranches_updated,
                matched_sales: counts.matched_sales + result.sales_matched,
                sales_created: counts.sales_created + result.sales_created,
                allocations_created: counts.allocations_created + result.allocations_created
            }

            {new_counts, warnings}

          {:warning, msg} ->
            {counts, [msg | warnings]}
        end
      end
    )
    |> then(fn {counts, warnings} ->
      {counts, Enum.reverse(warnings)}
    end)
  end

  defp aggregate_gl_bronze(gl_ingestions) do
    ing_ids = Enum.map(gl_ingestions, & &1.ingestion_id)
    ing_timestamps = Map.new(gl_ingestions, &{&1.ingestion_id, &1.inserted_at})

    bronze_rows =
      Repo.all(
        from r in BronzeRaw,
          where: r.ingestion_id in ^ing_ids and r.record_type == "Sell",
          select: {r.ingestion_id, r.raw_row_json}
      )

    # Per (symbol, sale_date): keep only rows from the ingestion with the latest inserted_at
    latest_ing_by_sale =
      bronze_rows
      |> Enum.reduce(%{}, fn {ing_id, raw}, acc ->
        data = Jason.decode!(raw)
        key = {data["Symbol"], VN.parse_date(data["Date Sold"])}
        ing_time = Map.fetch!(ing_timestamps, ing_id)

        Map.update(acc, key, {ing_id, ing_time}, fn {cur_id, cur_time} ->
          if DateTime.compare(ing_time, cur_time) == :gt,
            do: {ing_id, ing_time},
            else: {cur_id, cur_time}
        end)
      end)
      |> Map.new(fn {key, {ing_id, _}} -> {key, ing_id} end)

    surviving =
      Enum.filter(bronze_rows, fn {ing_id, raw} ->
        data = Jason.decode!(raw)
        key = {data["Symbol"], VN.parse_date(data["Date Sold"])}
        Map.get(latest_ing_by_sale, key) == ing_id
      end)

    # Group by plan-type-specific key, then sum quantities
    # RS:   (symbol, "RS",   grant_number, vest_date,     sale_date, order, price)
    # ESPP: (symbol, "ESPP", grant_date,   purchase_date, sale_date, order, price)
    surviving
    |> Enum.group_by(fn {_ing_id, raw} ->
      data = Jason.decode!(raw)
      plan_type = data["Plan Type"]

      {tranche_key, tranche_date} =
        if plan_type == "ESPP" do
          {VN.parse_date(data["Grant Date"]),
           VN.parse_date(data["Purchase Date"]) || VN.parse_date(data["Date Acquired"])}
        else
          {data["Grant Number"], VN.parse_date(data["Vest Date"])}
        end

      {data["Symbol"], plan_type, tranche_key, tranche_date, VN.parse_date(data["Date Sold"]),
       to_string_safe(data["Order Number"]), VN.clean_number(data["Proceeds Per Share"])}
    end)
    |> Enum.map(fn {key, rows} ->
      {symbol, plan_type, tranche_key, tranche_date, sale_date, order_number, price} = key

      total_qty =
        rows
        |> Enum.map(fn {_ing_id, raw} ->
          Decimal.new(VN.clean_number(Jason.decode!(raw)["Quantity"]))
        end)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
        |> Decimal.to_string()

      vest_fmv =
        rows
        |> Enum.map(fn {_ing_id, raw} -> Jason.decode!(raw)["Vest Date FMV"] end)
        |> Enum.find(&(&1 != nil))
        |> then(&VN.clean_number/1)

      %{
        symbol: symbol,
        plan_type: plan_type,
        # RS: grant_number string; ESPP: grant_date %Date{}
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

  defp process_aggregated_lot(account_id, %{plan_type: "RS"} = lot) do
    with {:ok, origin} <- find_origin_by_grant(account_id, lot.tranche_key),
         {:ok, tranche} <- find_tranche_by_date(origin.id, lot.tranche_date) do
      t_updated = fill_tranche_fmv(tranche, lot.vest_fmv)

      alloc_created =
        case find_bh_sale(origin.id, lot.sale_date) do
          nil ->
            0

          sale ->
            upsert_gl_allocation(
              sale,
              tranche,
              lot.aggregated_quantity,
              lot.proceeds_per_share,
              lot.order_number
            )
        end

      {:ok,
       %{
         tranches_updated: t_updated,
         sales_matched: if(alloc_created > 0, do: 1, else: 0),
         sales_created: 0,
         allocations_created: alloc_created
       }}
    else
      {:error, msg} ->
        {:warning, %{type: :unmatched_gl, sheet: "G&L_Expanded", row_index: nil, message: msg}}
    end
  end

  defp process_aggregated_lot(account_id, %{plan_type: "ESPP"} = lot) do
    with {:ok, origin} <- find_espp_origin(account_id, lot.tranche_key),
         {:ok, tranche} <- find_tranche_by_date(origin.id, lot.tranche_date) do
      alloc_created =
        case find_bh_sale_espp(origin.id, lot.sale_date, lot.aggregated_quantity) do
          nil ->
            0

          sale ->
            upsert_gl_allocation(
              sale,
              tranche,
              lot.aggregated_quantity,
              lot.proceeds_per_share,
              lot.order_number
            )
        end

      {:ok,
       %{
         tranches_updated: 0,
         sales_matched: if(alloc_created > 0, do: 1, else: 0),
         sales_created: 0,
         allocations_created: alloc_created
       }}
    else
      {:error, msg} ->
        {:warning, %{type: :unmatched_gl, sheet: "G&L_Expanded", row_index: nil, message: msg}}
    end
  end

  defp process_aggregated_lot(_account_id, lot) do
    {:warning,
     %{
       type: :unknown_plan,
       sheet: "G&L_Expanded",
       row_index: nil,
       message: "Unknown G&L plan type: #{lot.plan_type}"
     }}
  end

  defp find_origin_by_grant(account_id, grant_number) do
    case Repo.one(
           from o in Origin,
             where: o.account_id == ^account_id and o.grant_number == ^grant_number,
             limit: 1
         ) do
      nil -> {:error, "Origin not found for grant #{grant_number}"}
      origin -> {:ok, origin}
    end
  end

  defp find_espp_origin(account_id, grant_date) do
    case Repo.one(
           from o in Origin,
             where:
               o.account_id == ^account_id and o.plan_type == "ESPP" and
                 o.origin_date == ^grant_date,
             limit: 1
         ) do
      nil -> {:error, "ESPP origin not found for grant date #{grant_date}"}
      origin -> {:ok, origin}
    end
  end

  defp find_tranche_by_date(_origin_id, nil), do: {:error, "No vest date"}

  defp find_tranche_by_date(origin_id, vest_date) do
    case Repo.one(
           from t in Tranche,
             where: t.origin_id == ^origin_id and t.vest_date == ^vest_date,
             limit: 1
         ) do
      nil -> {:error, "Tranche not found for vest_date #{vest_date}"}
      tranche -> {:ok, tranche}
    end
  end

  defp fill_tranche_fmv(_tranche, nil), do: 0

  defp fill_tranche_fmv(%{vest_fmv: nil} = tranche, fmv) do
    tranche |> Tranche.changeset(%{vest_fmv: fmv}) |> Repo.update!()
    1
  end

  defp fill_tranche_fmv(_tranche, _fmv), do: 0

  defp find_bh_sale(origin_id, sale_date) do
    Repo.one(
      from s in Sale,
        where: s.origin_id == ^origin_id and s.sale_date == ^sale_date,
        limit: 1
    )
  end

  # ESPP: match by origin + date + quantity
  # Multiple ESPP purchase lots from same enrollment can be sold on the same date
  defp find_bh_sale_espp(origin_id, sale_date, quantity) do
    qty_decimal = if quantity, do: Decimal.new(quantity), else: nil

    if qty_decimal do
      Repo.one(
        from s in Sale,
          where:
            s.origin_id == ^origin_id and s.sale_date == ^sale_date and
              s.total_quantity == ^qty_decimal,
          limit: 1
      )
    else
      find_bh_sale(origin_id, sale_date)
    end
  end

  defp upsert_gl_allocation(sale, tranche, quantity, proceeds_per_share, order_number) do
    # Drop BH placeholder (nil price) only — preserve all G&L allocations
    Repo.delete_all(
      from a in SaleAllocation,
        where: a.sale_id == ^sale.id and a.tranche_id == ^tranche.id and is_nil(a.sale_price)
    )

    price_decimal = if proceeds_per_share, do: Decimal.new(proceeds_per_share), else: nil
    qty_decimal = if quantity, do: Decimal.new(quantity), else: nil

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
        quantity: quantity,
        sale_price: proceeds_per_share,
        order_number: order_number
      })
      |> Repo.insert!()

      1
    end
  end

  defp yahoo_close_safe(symbol, date) when is_binary(symbol) and not is_nil(date) do
    alias StockPlan.StockPrice

    try do
      StockPrice.get_close(symbol, date)
    rescue
      e ->
        Logger.warning(
          "Yahoo price fetch failed for #{symbol} on #{date}: #{Exception.message(e)}"
        )

        nil
    end
  end

  defp yahoo_close_safe(_, _), do: nil

  defp to_string_safe(nil), do: nil
  defp to_string_safe(v) when is_binary(v), do: v
  defp to_string_safe(v) when is_number(v), do: Integer.to_string(trunc(v))
  defp to_string_safe(v), do: to_string(v)

  # --- Phase 3: FX Rate Enrichment ---

  defp enrich_fx_rates(account_id) do
    alias StockPlan.FX

    # Origins: fill origin_fx_rate
    origins_updated =
      Repo.all(from o in Origin, where: o.account_id == ^account_id and is_nil(o.origin_fx_rate))
      |> Enum.reduce(0, fn origin, count ->
        case FX.get_rate_string(origin.origin_date) do
          nil ->
            count

          rate ->
            origin |> Origin.changeset(%{origin_fx_rate: rate}) |> Repo.update!()
            count + 1
        end
      end)

    # Tranches: fill vest_fx_rate (VESTED only)
    tranches_updated =
      Repo.all(
        from t in Tranche,
          join: o in Origin,
          on: t.origin_id == o.id,
          where: o.account_id == ^account_id and t.status == "VESTED" and is_nil(t.vest_fx_rate)
      )
      |> Enum.reduce(0, fn tranche, count ->
        case FX.get_rate_string(tranche.vest_date) do
          nil ->
            count

          rate ->
            tranche |> Tranche.changeset(%{vest_fx_rate: rate}) |> Repo.update!()
            count + 1
        end
      end)

    # Sales: fill sale_fx_rate
    sales_updated =
      Repo.all(from s in Sale, where: s.account_id == ^account_id and is_nil(s.sale_fx_rate))
      |> Enum.reduce(0, fn sale, count ->
        case FX.get_rate_string(sale.sale_date) do
          nil ->
            count

          rate ->
            sale |> Sale.changeset(%{sale_fx_rate: rate}) |> Repo.update!()
            count + 1
        end
      end)

    %{origins: origins_updated, tranches: tranches_updated, sales: sales_updated}
  end

  # --- Phase 4: Stock Price Enrichment ---

  defp enrich_stock_prices(account_id) do
    alias StockPlan.StockPrice

    # Get all VESTED tranches without vest_day_close, with their origin's symbol
    tranche_data =
      Repo.all(
        from t in Tranche,
          join: o in Origin,
          on: t.origin_id == o.id,
          where:
            o.account_id == ^account_id and t.status == "VESTED" and is_nil(t.vest_day_close),
          select: {t, o.symbol}
      )

    if tranche_data == [] do
      %{tranches: 0}
    else
      # Group by symbol, fetch price range per symbol
      by_symbol = Enum.group_by(tranche_data, fn {_t, symbol} -> symbol end)

      total_updated =
        Enum.reduce(by_symbol, 0, fn {symbol, pairs}, acc ->
          dates = Enum.map(pairs, fn {t, _} -> t.vest_date end) |> Enum.reject(&is_nil/1)

          if dates == [] do
            acc
          else
            min_date = Enum.min(dates, Date)
            max_date = Enum.max(dates, Date)
            prices = StockPrice.get_close_range(symbol, min_date, Date.add(max_date, 5))

            updated =
              Enum.reduce(pairs, 0, fn {tranche, _}, count ->
                price = find_closest_price(prices, tranche.vest_date)

                case price do
                  nil ->
                    count

                  p ->
                    tranche |> Tranche.changeset(%{vest_day_close: p}) |> Repo.update!()
                    count + 1
                end
              end)

            acc + updated
          end
        end)

      %{tranches: total_updated}
    end
  end

  defp enrich_rsu_origin_fmv(account_id) do
    alias StockPlan.StockPrice

    origins =
      Repo.all(
        from o in Origin,
          where: o.account_id == ^account_id and o.plan_type == "RSU" and is_nil(o.origin_fmv),
          select: o
      )

    if origins == [] do
      :ok
    else
      by_symbol = Enum.group_by(origins, & &1.symbol)

      Enum.each(by_symbol, fn {symbol, syms_origins} ->
        dates = Enum.map(syms_origins, & &1.origin_date) |> Enum.reject(&is_nil/1)

        if dates != [] do
          min_date = Enum.min(dates, Date)
          max_date = Enum.max(dates, Date)
          prices = StockPrice.get_close_range(symbol, min_date, Date.add(max_date, 5))

          Enum.each(syms_origins, fn origin ->
            price = find_closest_price(prices, origin.origin_date)

            if price do
              origin
              |> Origin.changeset(%{origin_fmv: price})
              |> Repo.update!()
            end
          end)
        end
      end)

      :ok
    end
  end

  defp find_closest_price(prices, date) when is_map(prices) and not is_nil(date) do
    # Find closest trading day >= date (next business day)
    # Broker processes weekend/holiday vests on next trading day — use that day's price
    prices
    |> Enum.filter(fn {d, _} -> Date.compare(d, date) != :lt end)
    |> Enum.sort_by(fn {d, _} -> Date.to_iso8601(d) end, :asc)
    |> case do
      [{_d, price} | _] -> price
      [] -> nil
    end
  end

  defp find_closest_price(_, _), do: nil
end
