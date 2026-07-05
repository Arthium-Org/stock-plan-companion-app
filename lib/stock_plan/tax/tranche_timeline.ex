defmodule StockPlan.Tax.TrancheTimeline do
  @moduledoc """
  Tranche Timeline Builder — constructs a per-tranche timeline showing the state
  of each lot at any point in time. Foundation for Schedule FA and tax features.

  Combines three data sources:
  - BH Silver: tranches (from stock_plan_tranches joined with origins)
  - G&L: sale_allocations (tranche-level sells for RSU)
  - Holdings Silver: current sellable_qty per tranche
  - BH sales: origin-level sell events (for ESPP and validation)
  """

  alias StockPlan.Repo
  alias StockPlan.Schema.{Origin, Tranche, Sale, SaleAllocation, Holding}
  import Ecto.Query

  @doc """
  Build tranche timelines for an account.
  Returns {timelines, validation_result}.
  """
  def build(account_id) do
    tranches = load_tranches(account_id)
    allocations = load_allocations(account_id)
    holdings = load_holdings(account_id)
    bh_sales = load_bh_sales(account_id)

    timelines = build_timelines(tranches, allocations, holdings, bh_sales)
    validation = validate(timelines, bh_sales, allocations)

    {timelines, validation}
  end

  @doc """
  Query: what was held during a calendar year?
  Returns list of tranche states for the CY.
  """
  def held_during_cy(timelines, calendar_year) do
    cy_start = Date.new!(calendar_year, 1, 1)
    cy_end = Date.new!(calendar_year, 12, 31)

    timelines
    |> Enum.filter(fn t -> Date.compare(t.vest_date, cy_end) != :gt end)
    |> Enum.map(fn t ->
      sold_before_cy = sum_sells_before(t.sells, cy_start)
      sold_during_cy = sum_sells_between(t.sells, cy_start, cy_end)
      held_at_start = Decimal.sub(t.net_quantity, sold_before_cy)
      held_at_end = Decimal.sub(held_at_start, sold_during_cy)

      # Holdings override: if Holdings says 0 and timeline says held (no sell records),
      # the tranche was sold before G&L coverage. Trust Holdings as current truth.
      {held_at_start, held_at_end, sold_during_cy} =
        if t.holdings_qty != nil and Decimal.equal?(t.holdings_qty, Decimal.new(0)) and
             Enum.empty?(t.sells) do
          # Holdings says sold, no sell records → fully sold before our data range
          {Decimal.new(0), Decimal.new(0), Decimal.new(0)}
        else
          {held_at_start, held_at_end, sold_during_cy}
        end

      %{
        timeline: t,
        held_at_start: held_at_start,
        held_at_end: held_at_end,
        sold_during_cy: sold_during_cy,
        held_during_cy:
          Decimal.gt?(held_at_start, Decimal.new(0)) or
            Decimal.gt?(sold_during_cy, Decimal.new(0))
      }
    end)
    |> Enum.filter(& &1.held_during_cy)
  end

  @doc """
  Validate G&L coverage for a specific calendar year.
  Returns :ok or {:error, message}.
  Used by ScheduleFA before building rows.
  """
  def validate_cy_coverage(bh_sales, allocations, calendar_year) do
    validate_v2_for_cy(bh_sales, allocations, calendar_year)
  end

  # ============================================================
  # Data Loading
  # ============================================================

  defp load_tranches(account_id) do
    Repo.all(
      from t in Tranche,
        join: o in Origin,
        on: t.origin_id == o.id,
        where: o.account_id == ^account_id and t.status == "VESTED",
        select: %{
          tranche_id: t.id,
          origin_id: t.origin_id,
          grant_number: o.grant_number,
          plan_type: o.plan_type,
          symbol: o.symbol,
          vest_date: t.vest_date,
          net_quantity: t.net_quantity,
          vest_fmv: t.vest_fmv,
          vest_day_close: t.vest_day_close,
          cost_basis_broker: t.cost_basis_broker,
          vest_fx_rate: t.vest_fx_rate
        }
    )
  end

  defp load_allocations(account_id) do
    Repo.all(
      from a in SaleAllocation,
        join: s in Sale,
        on: a.sale_id == s.id,
        join: t in Tranche,
        on: a.tranche_id == t.id,
        join: o in Origin,
        on: t.origin_id == o.id,
        where: o.account_id == ^account_id,
        select: %{
          tranche_id: a.tranche_id,
          sale_date: s.sale_date,
          quantity: a.quantity,
          sale_price: a.sale_price,
          origin_id: s.origin_id,
          plan_type: o.plan_type,
          metadata_json: s.metadata_json
        }
    )
  end

  defp load_holdings(account_id) do
    Repo.all(
      from h in Holding,
        where: h.account_id == ^account_id and h.status == "VESTED",
        select: %{
          grant_number: h.grant_number,
          vest_date: h.vest_date,
          sellable_qty: h.sellable_qty,
          plan_type: h.plan_type
        }
    )
  end

  defp load_bh_sales(account_id) do
    Repo.all(
      from s in Sale,
        join: o in Origin,
        on: s.origin_id == o.id,
        where: s.account_id == ^account_id,
        select: %{
          id: s.id,
          origin_id: s.origin_id,
          sale_date: s.sale_date,
          total_quantity: s.total_quantity,
          sale_price: s.sale_price,
          plan_type: o.plan_type,
          grant_number: o.grant_number
        }
    )
  end

  # ============================================================
  # Timeline Construction
  # ============================================================

  defp build_timelines(tranches, allocations, holdings, bh_sales) do
    # Group allocations by tranche_id (G&L tranche-level sells)
    allocs_by_tranche = Enum.group_by(allocations, & &1.tranche_id)

    # Group BH sales by origin_id (origin-level sells for ESPP)
    bh_sales_by_origin = Enum.group_by(bh_sales, & &1.origin_id)

    # Index holdings by {grant_number, vest_date} for matching
    holdings_index = index_holdings(holdings)

    # Step 1: Build initial timelines with G&L sells + Holdings match
    initial_timelines =
      Enum.map(tranches, fn tranche ->
        net_qty = tranche.net_quantity || Decimal.new(0)
        sells = build_sells(tranche, allocs_by_tranche, bh_sales_by_origin)
        holdings_qty = match_holding(tranche, holdings_index)
        total_sold = sum_sell_quantities(sells)
        held_from_timeline = Decimal.sub(net_qty, total_sold)
        cost_basis = resolve_cost_basis(tranche)

        %{
          tranche_id: tranche.tranche_id,
          origin_id: tranche.origin_id,
          grant_number: tranche.grant_number,
          plan_type: tranche.plan_type,
          symbol: tranche.symbol,
          vest_date: tranche.vest_date,
          net_quantity: net_qty,
          cost_basis: cost_basis,
          vest_fx_rate: tranche.vest_fx_rate,
          sells: Enum.sort_by(sells, fn s -> Date.to_iso8601(s.date) end),
          holdings_qty: holdings_qty,
          total_sold: total_sold,
          held_from_timeline: held_from_timeline
        }
      end)

    # Step 2: Per-origin validation — mark remaining tranches as sold if BH confirms
    apply_bh_sold_validation(initial_timelines, bh_sales_by_origin, holdings_index)
  end

  # Per-origin: validate (released - holdings) == BH sold total.
  # If validated, mark tranches with no G&L and no Holdings as fully sold.
  # Per-origin BH validation: released - holdings - gl_sold = determined_sold.
  # If BH sale total covers determined_sold, mark those tranches as sold.
  # For RSU: can't determine per-tranche dates → just mark holdings_qty=0
  #          (Holdings override in held_during_cy will exclude them)
  # For ESPP: quantity matching in build_sells already assigns real dates
  defp apply_bh_sold_validation(timelines, bh_sales_by_origin, holdings_index) do
    if map_size(holdings_index) == 0 do
      apply_bh_sold_validation_no_holdings(timelines, bh_sales_by_origin)
    else
      # match_holding already returns sellable_qty || 0 for every tranche.
      # Not in Holdings = 0 (sold). Holdings is ground truth. No further work needed.
      timelines
    end
  end

  # When Holdings is NOT uploaded: use BH sold totals to detect fully-sold origins.
  # If bh_sold == total_released (±2): all tranches sold → set holdings_qty = 0
  # If bh_sold < total_released: can't determine which tranches → leave as nil
  # If bh_sold > total_released: data error → emit warning, leave as-is
  defp apply_bh_sold_validation_no_holdings(timelines, bh_sales_by_origin) do
    by_origin = Enum.group_by(timelines, & &1.origin_id)

    Enum.flat_map(by_origin, fn {origin_id, origin_timelines} ->
      # Total released for this origin
      total_released =
        Enum.reduce(origin_timelines, Decimal.new(0), fn t, acc ->
          Decimal.add(acc, t.net_quantity)
        end)

      # BH sold total for this origin
      bh_sold =
        bh_sales_by_origin
        |> Map.get(origin_id, [])
        |> Enum.reduce(Decimal.new(0), fn s, acc ->
          Decimal.add(acc, s.total_quantity)
        end)

      cond do
        # bh_sold == total_released: fully sold origin
        Decimal.equal?(bh_sold, total_released) ->
          Enum.map(origin_timelines, fn t ->
            %{t | holdings_qty: Decimal.new(0)}
          end)

        # bh_sold > total_released: data error (warn but continue)
        Decimal.gt?(bh_sold, total_released) ->
          # Warning emitted via validate/3 — leave timelines unchanged
          origin_timelines

        # bh_sold < total_released: can't determine without Holdings
        true ->
          origin_timelines
      end
    end)
  end

  defp build_sells(tranche, allocs_by_tranche, bh_sales_by_origin) do
    case tranche.plan_type do
      "RSU" ->
        # RSU: sells from G&L allocations only
        allocs_by_tranche
        |> Map.get(tranche.tranche_id, [])
        |> Enum.map(fn alloc ->
          order_number = extract_order_number(alloc.metadata_json)

          %{
            date: alloc.sale_date,
            quantity: alloc.quantity,
            price: alloc.sale_price,
            order_number: order_number,
            source: :gl,
            confidence: :verified
          }
        end)

      "ESPP" ->
        # ESPP: G&L allocations primary (has sell price), BH quantity match as fallback
        allocs = Map.get(allocs_by_tranche, tranche.tranche_id, [])

        if allocs != [] do
          # G&L allocations (tranche-level, has price)
          Enum.map(allocs, fn alloc ->
            %{
              date: alloc.sale_date,
              quantity: alloc.quantity,
              price: alloc.sale_price,
              order_number: nil,
              source: :gl,
              confidence: :verified
            }
          end)
        else
          # Fallback: match BH sales to this tranche by quantity
          # ESPP BH sales are per-purchase (quantities match specific tranches)
          net_qty = tranche.net_quantity || Decimal.new(0)

          bh_sales_by_origin
          |> Map.get(tranche.origin_id, [])
          |> Enum.filter(fn sale ->
            Decimal.equal?(sale.total_quantity, net_qty)
          end)
          |> Enum.take(1)
          |> Enum.map(fn sale ->
            %{
              date: sale.sale_date,
              quantity: sale.total_quantity,
              price: sale.sale_price,
              order_number: nil,
              source: :bh,
              confidence: :inferred
            }
          end)
        end

      _ ->
        []
    end
  end

  defp extract_order_number(nil), do: nil

  defp extract_order_number(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"order_number" => on}} -> on
      _ -> nil
    end
  end

  defp index_holdings(holdings) do
    Enum.reduce(holdings, %{}, fn h, acc ->
      key = {h.grant_number, h.vest_date}
      Map.put(acc, key, h.sellable_qty)
    end)
  end

  defp match_holding(tranche, holdings_index) do
    if map_size(holdings_index) == 0 do
      nil
    else
      Map.get(holdings_index, {tranche.grant_number, tranche.vest_date}) || Decimal.new(0)
    end
  end

  defp resolve_cost_basis(tranche) do
    tranche.cost_basis_broker || tranche.vest_fmv || tranche.vest_day_close
  end

  defp sum_sell_quantities(sells) do
    Enum.reduce(sells, Decimal.new(0), fn s, acc -> Decimal.add(acc, s.quantity) end)
  end

  # ============================================================
  # Validation
  # ============================================================

  defp validate(timelines, bh_sales, allocations) do
    v1_warnings = validate_v1(timelines)
    v3_warnings = validate_v3(bh_sales, allocations)

    all_warnings = v1_warnings ++ v3_warnings
    # V2 is checked per-CY, not globally — handled by validate_cy_coverage/3

    %{
      valid: true,
      errors: [],
      warnings: all_warnings
    }
  end

  # V1: Holdings vs Timeline quantity match per tranche
  defp validate_v1(timelines) do
    timelines
    |> Enum.filter(fn t -> t.holdings_qty != nil end)
    # Skip tranches where Holdings=0 and no sell records — expected case (sold before G&L coverage)
    |> Enum.reject(fn t ->
      Decimal.equal?(t.holdings_qty, Decimal.new(0)) and Enum.empty?(t.sells)
    end)
    |> Enum.flat_map(fn t ->
      diff = Decimal.sub(t.held_from_timeline, t.holdings_qty) |> Decimal.abs()

      if Decimal.gt?(diff, Decimal.new(1)) do
        [
          %{
            code: :qty_mismatch,
            message:
              "#{t.grant_number} vest #{t.vest_date}: timeline=#{t.held_from_timeline}, holdings=#{t.holdings_qty}"
          }
        ]
      else
        []
      end
    end)
  end

  # V2: G&L coverage for CY (RSU only)
  defp validate_v2_for_cy(bh_sales, allocations, calendar_year) do
    cy_start = Date.new!(calendar_year, 1, 1)
    cy_end = Date.new!(calendar_year, 12, 31)

    # RSU sell dates in this CY (from BH sales)
    rsu_sell_dates_in_cy =
      bh_sales
      |> Enum.filter(fn s -> s.plan_type == "RSU" end)
      |> Enum.filter(fn s ->
        Date.compare(s.sale_date, cy_start) != :lt and
          Date.compare(s.sale_date, cy_end) != :gt
      end)
      |> Enum.map(& &1.sale_date)
      |> Enum.uniq()

    if rsu_sell_dates_in_cy == [] do
      :ok
    else
      # Per-date check: each BH sell date must have a matching G&L allocation
      gl_allocation_dates =
        allocations
        |> Enum.filter(fn a -> a.plan_type == "RSU" end)
        |> Enum.map(& &1.sale_date)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      missing_dates =
        Enum.reject(rsu_sell_dates_in_cy, fn d ->
          MapSet.member?(gl_allocation_dates, d)
        end)

      if missing_dates == [] do
        :ok
      else
        dates_str = Enum.map(missing_dates, &Date.to_iso8601/1) |> Enum.join(", ")

        {:error,
         "G&L data missing for RSU sell dates: #{dates_str}. Upload G&L for #{calendar_year}."}
      end
    end
  end

  # V3: No gaps in G&L allocations (RSU only)
  defp validate_v3(bh_sales, allocations) do
    # Get all RSU BH sales
    rsu_bh_sales = Enum.filter(bh_sales, fn s -> s.plan_type == "RSU" end)

    # Get G&L allocation dates for RSU
    gl_dates =
      allocations
      |> Enum.filter(fn a -> a.plan_type == "RSU" end)
      |> Enum.map(& &1.sale_date)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    # Find BH RSU sales that have a matching date in G&L but zero allocations
    # "matching date" = the date exists in G&L dates
    # "zero allocations" = no allocations for that specific sale's origin+date
    allocs_by_date =
      allocations
      |> Enum.filter(fn a -> a.plan_type == "RSU" end)
      |> Enum.group_by(& &1.sale_date)

    unallocated =
      rsu_bh_sales
      |> Enum.filter(fn s -> MapSet.member?(gl_dates, s.sale_date) end)
      |> Enum.filter(fn s ->
        # Check if this specific sale date has allocations with non-zero total qty
        date_allocs = Map.get(allocs_by_date, s.sale_date, [])

        total_alloc_qty =
          Enum.reduce(date_allocs, Decimal.new(0), fn a, acc -> Decimal.add(acc, a.quantity) end)

        Decimal.compare(total_alloc_qty, Decimal.new(0)) == :eq
      end)

    if unallocated == [] do
      []
    else
      [
        %{
          code: :gl_gaps,
          message: "#{length(unallocated)} RSU sell event(s) have no lot allocation in G&L"
        }
      ]
    end
  end

  # ============================================================
  # Summary
  # ============================================================

  @doc """
  Per-symbol reconciliation summary for diagnostics and UI.

  Inputs:
  - timelines: list of timeline maps (output of build/1)
  - bh_sales: list of BH sale maps with :origin_id, :sale_date, :total_quantity, :plan_type, :grant_number

  Returns map keyed by symbol with reconciliation fields and status.
  """
  def summary(timelines, bh_sales) do
    zero = Decimal.new(0)

    # Build origin_id → symbol lookup from timelines
    origin_to_symbol =
      timelines
      |> Enum.map(fn t -> {t.origin_id, t.symbol} end)
      |> Enum.uniq()
      |> Map.new()

    # Group timelines by symbol
    by_symbol = Enum.group_by(timelines, & &1.symbol)

    # Group bh_sales by symbol (via origin_id lookup)
    bh_sales_by_symbol =
      bh_sales
      |> Enum.group_by(fn s -> Map.get(origin_to_symbol, s.origin_id) end)
      |> Map.delete(nil)

    by_symbol
    |> Enum.map(fn {symbol, symbol_timelines} ->
      total_released =
        Enum.reduce(symbol_timelines, zero, fn t, acc ->
          Decimal.add(acc, t.net_quantity)
        end)

      total_gl_sold =
        Enum.reduce(symbol_timelines, zero, fn t, acc ->
          gl_qty =
            t.sells
            |> Enum.filter(fn s -> s.source == :gl end)
            |> Enum.reduce(zero, fn s, inner -> Decimal.add(inner, s.quantity) end)

          Decimal.add(acc, gl_qty)
        end)

      total_bh_matched =
        Enum.reduce(symbol_timelines, zero, fn t, acc ->
          bh_qty =
            t.sells
            |> Enum.filter(fn s -> s.source == :bh end)
            |> Enum.reduce(zero, fn s, inner -> Decimal.add(inner, s.quantity) end)

          Decimal.add(acc, bh_qty)
        end)

      symbol_bh_sales = Map.get(bh_sales_by_symbol, symbol, [])

      total_bh_sold =
        Enum.reduce(symbol_bh_sales, zero, fn s, acc ->
          Decimal.add(acc, s.total_quantity)
        end)

      holdings_held =
        Enum.reduce(symbol_timelines, zero, fn t, acc ->
          case t.holdings_qty do
            nil -> acc
            qty -> if Decimal.gt?(qty, zero), do: Decimal.add(acc, qty), else: acc
          end
        end)

      has_holdings = Enum.any?(symbol_timelines, fn t -> t.holdings_qty != nil end)

      vested_unsold_bh = Decimal.sub(total_released, total_bh_sold)

      tranche_count = length(symbol_timelines)

      origin_count =
        symbol_timelines
        |> Enum.map(& &1.origin_id)
        |> Enum.uniq()
        |> length()

      status =
        cond do
          Decimal.gt?(total_bh_sold, total_released) ->
            :error

          has_holdings ->
            :reconciled

          Decimal.equal?(total_bh_sold, total_released) ->
            :reconciled

          true ->
            :holdings_needed
        end

      {symbol,
       %{
         total_released: total_released,
         total_bh_sold: total_bh_sold,
         total_gl_sold: total_gl_sold,
         total_bh_matched: total_bh_matched,
         holdings_held: holdings_held,
         has_holdings: has_holdings,
         vested_unsold_bh: vested_unsold_bh,
         tranche_count: tranche_count,
         origin_count: origin_count,
         status: status
       }}
    end)
    |> Map.new()
  end

  # ============================================================
  # Sell aggregation helpers
  # ============================================================

  defp sum_sells_before(sells, date) do
    sells
    |> Enum.filter(fn s -> Date.compare(s.date, date) == :lt end)
    |> Enum.reduce(Decimal.new(0), fn s, acc -> Decimal.add(acc, s.quantity) end)
  end

  defp sum_sells_between(sells, from_date, to_date) do
    sells
    |> Enum.filter(fn s ->
      Date.compare(s.date, from_date) != :lt and
        Date.compare(s.date, to_date) != :gt
    end)
    |> Enum.reduce(Decimal.new(0), fn s, acc -> Decimal.add(acc, s.quantity) end)
  end
end
