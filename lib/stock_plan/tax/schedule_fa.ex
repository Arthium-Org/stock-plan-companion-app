defmodule StockPlan.Tax.ScheduleFA do
  @moduledoc """
  Schedule FA (Foreign Assets) — computes per-lot disclosure rows for a calendar year.
  One row per tranche held at any point during the CY. All values in INR (Rule 115 FX rates).

  M26: P1 (G&L coverage) and P2 (Holdings availability) are hard gates.
  No soft-degradation — either both pass or the build fails with {:error, message}.
  """

  alias StockPlan.Repo
  alias StockPlan.Schema.{Origin, Tranche, Sale, SaleAllocation, Holding}
  alias StockPlan.Tax.TrancheTimeline
  alias StockPlan.{StockPrice, FX, StockMeta}
  import Ecto.Query

  # ============================================================
  # Public API
  # ============================================================

  @doc """
  Build Schedule FA data for a calendar year.

      {:ok, rows, warnings}          — success; warnings are V1/V3 from TrancheTimeline
      {:error, message}              — P1 or P2 hard block
      {:error, {:missing_meta, syms}} — stock metadata missing for symbols in rows
  """
  def build(account_id, calendar_year) do
    bh_sales = load_bh_sales(account_id)
    allocations = load_allocations(account_id)

    with :ok <- check_gl_coverage_for_fa_year(bh_sales, allocations, calendar_year),
         :ok <- check_holdings_available(account_id, bh_sales) do
      {timelines, validation} = TrancheTimeline.build(account_id)

      if timelines == [] do
        {:ok, [], validation.warnings}
      else
        cy_states =
          timelines
          |> compute_cy_state(calendar_year)
          |> Enum.reject(fn s -> Decimal.equal?(s.start_count, Decimal.new(0)) end)

        rows =
          cy_states
          |> build_fa_rows_from_state(calendar_year)
          |> aggregate_by_date()

        case check_meta_coverage(rows) do
          :ok -> {:ok, rows, validation.warnings}
          {:error, missing} -> {:error, {:missing_meta, missing}}
        end
      end
    end
  end

  @doc """
  Run P1 + P2 pre-checks for a calendar year without building rows.
  Used by UploadChecks to determine FA readiness for the upload badge.

      :ok                — P1 and P2 pass
      {:error, message}  — P1 or P2 failed
  """
  def pre_check(account_id, calendar_year) do
    bh_sales = load_bh_sales(account_id)
    allocations = load_allocations(account_id)

    with :ok <- check_gl_coverage_for_fa_year(bh_sales, allocations, calendar_year),
         :ok <- check_holdings_available(account_id, bh_sales) do
      :ok
    end
  end

  @doc """
  Legacy build — returns a flat list (no validation).
  Used by existing callers that expect the old return format.
  """
  def build_legacy(account_id, calendar_year) do
    cy_start = Date.new!(calendar_year, 1, 1)
    cy_end = Date.new!(calendar_year, 12, 31)

    tranches_with_origins = fetch_tranches(account_id, cy_end)

    if tranches_with_origins == [] do
      []
    else
      tranche_ids = Enum.map(tranches_with_origins, fn {t, _o} -> t.id end)
      sales_by_tranche = fetch_sales_by_tranche(tranche_ids)

      symbols = tranches_with_origins |> Enum.map(fn {_t, o} -> o.symbol end) |> Enum.uniq()
      price_series_map = fetch_price_series(symbols, cy_start, cy_end)

      dec31_fx = FX.get_rate(cy_end)

      tranches_with_origins
      |> Enum.map(fn {tranche, origin} ->
        build_row(tranche, origin, sales_by_tranche, price_series_map, cy_start, cy_end, dec31_fx)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.date_acquired, Date)
    end
  end

  @doc "Generate CSV content from FA rows."
  def to_csv(rows) do
    headers = [
      "Country/Region name",
      "Country Name and Code",
      "Name of entity",
      "Address of entity",
      "ZIP Code",
      "Nature of entity",
      "Date of acquiring the interest",
      "Initial value of the investment",
      "Peak value of investment during the Period",
      "Closing balance",
      "Total gross amount paid/credited with respect to the holding during the period",
      "Total gross proceeds from sale or redemption of investment during the period"
    ]

    lines = [Enum.join(headers, ",")] ++ Enum.map(rows, &row_to_csv/1)
    Enum.join(lines, "\n")
  end

  @doc false
  def row_to_csv(row) do
    meta = StockMeta.get!(row.symbol)

    fields = [
      meta["country"],
      meta["country_code"],
      "#{meta["legal_name"]}(#{row.symbol})",
      meta["address"],
      meta["zip"],
      meta["nature_of_entity"],
      format_csv_date(row.date_acquired),
      round_inr_or_dash(row.initial_value_inr),
      round_inr_or_dash(row.peak_value_inr),
      round_inr_or_dash(row.closing_value_inr),
      round_inr_or_dash(row.income_from_asset),
      round_inr_or_dash(row.sale_proceeds_inr)
    ]

    Enum.map(fields, &csv_field/1) |> Enum.join(",")
  end

  # ============================================================
  # P1: G&L coverage gate
  # ============================================================

  defp check_gl_coverage_for_fa_year(bh_sales, allocations, calendar_year) do
    cy_start = Date.new!(calendar_year, 1, 1)

    gl_dates =
      allocations
      |> Enum.map(& &1.sale_date)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    missing =
      bh_sales
      |> Enum.filter(&(Date.compare(&1.sale_date, cy_start) != :lt))
      |> Enum.map(& &1.sale_date)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(gl_dates, &1))
      |> Enum.sort()

    if missing == [] do
      :ok
    else
      dates_str = Enum.map_join(missing, ", ", &Date.to_iso8601/1)

      {:error,
       "G&L missing for sell dates: #{dates_str}. " <>
         "Upload G&L covering sales in or after #{calendar_year}."}
    end
  end

  # ============================================================
  # P2: Holdings availability gate (direct DB — no timelines needed)
  # ============================================================

  defp check_holdings_available(account_id, bh_sales) do
    if holdings_uploaded?(account_id) do
      :ok
    else
      check_origins_resolvable(account_id, bh_sales)
    end
  end

  defp holdings_uploaded?(account_id) do
    Repo.exists?(from h in Holding, where: h.account_id == ^account_id)
  end

  defp check_origins_resolvable(account_id, bh_sales) do
    origin_data = load_vested_origins_with_totals(account_id)
    bh_by_origin = Enum.group_by(bh_sales, & &1.origin_id)
    tolerance = Decimal.new(2)

    unresolved =
      Enum.reject(origin_data, fn {origin_id, _grant_number, total_released} ->
        bh_sold =
          bh_by_origin
          |> Map.get(origin_id, [])
          |> Enum.reduce(Decimal.new(0), fn s, acc -> Decimal.add(acc, s.total_quantity) end)

        Decimal.lt?(Decimal.abs(Decimal.sub(bh_sold, total_released)), tolerance)
      end)

    if unresolved == [] do
      :ok
    else
      grants =
        unresolved
        |> Enum.map(fn {_id, grant_number, _total} -> grant_number end)
        |> Enum.uniq()
        |> Enum.join(", ")

      {:error,
       "Holdings unavailable for grants: #{grants}. " <>
         "Upload Holdings (ByBenefitType) or ensure all sales are in Benefit History."}
    end
  end

  defp load_vested_origins_with_totals(account_id) do
    Repo.all(
      from t in Tranche,
        join: o in Origin,
        on: t.origin_id == o.id,
        where: o.account_id == ^account_id and t.status == "VESTED",
        select: %{
          origin_id: o.id,
          grant_number: o.grant_number,
          net_quantity: t.net_quantity
        }
    )
    |> Enum.group_by(& &1.origin_id)
    |> Enum.map(fn {origin_id, rows} ->
      total_released =
        Enum.reduce(rows, Decimal.new(0), fn r, acc ->
          Decimal.add(acc, r.net_quantity || Decimal.new(0))
        end)

      {origin_id, hd(rows).grant_number, total_released}
    end)
  end

  # ============================================================
  # CY state algorithm (Rules 1–3)
  # ============================================================

  defp compute_cy_state(timelines, calendar_year) do
    cy_start = Date.new!(calendar_year, 1, 1)
    cy_end = Date.new!(calendar_year, 12, 31)

    Enum.map(timelines, fn t ->
      cond do
        # Rule 2: vested after CY — excluded
        Date.compare(t.vest_date, cy_end) == :gt ->
          state(t, Decimal.new(0), Decimal.new(0), Decimal.new(0))

        # Rule 1: vested during CY (cy_start <= vest_date <= cy_end)
        Date.compare(t.vest_date, cy_start) != :lt ->
          cy_sale = sum_sells_in_range(t.sells, cy_start, cy_end)
          state(t, t.net_quantity, Decimal.sub(t.net_quantity, cy_sale), cy_sale)

        # Rule 3: vested before CY
        true ->
          cy_sale = sum_sells_in_range(t.sells, cy_start, cy_end)
          beyond = sum_sells_after(t.sells, cy_end)
          holdings = effective_holdings(t)
          start_count = Decimal.add(Decimal.add(cy_sale, beyond), holdings)
          end_count = Decimal.add(beyond, holdings)
          state(t, start_count, end_count, cy_sale)
      end
    end)
  end

  defp state(t, start_count, end_count, cy_sale) do
    %{timeline: t, start_count: start_count, end_count: end_count, cy_sale: cy_sale}
  end

  defp effective_holdings(t), do: t.holdings_qty || Decimal.new(0)

  defp sum_sells_in_range(sells, from_date, to_date) do
    sells
    |> Enum.filter(fn s ->
      Date.compare(s.date, from_date) != :lt and Date.compare(s.date, to_date) != :gt
    end)
    |> Enum.reduce(Decimal.new(0), fn s, acc -> Decimal.add(acc, s.quantity) end)
  end

  defp sum_sells_after(sells, date) do
    sells
    |> Enum.filter(fn s -> Date.compare(s.date, date) == :gt end)
    |> Enum.reduce(Decimal.new(0), fn s, acc -> Decimal.add(acc, s.quantity) end)
  end

  # ============================================================
  # FA row builder (M26)
  # ============================================================

  defp build_fa_rows_from_state(cy_states, calendar_year) do
    cy_start = Date.new!(calendar_year, 1, 1)
    cy_end = Date.new!(calendar_year, 12, 31)

    symbols =
      cy_states
      |> Enum.map(fn s -> s.timeline.symbol end)
      |> Enum.uniq()

    price_series_map = fetch_price_series(symbols, cy_start, cy_end)
    dec31_fx = FX.get_rate(cy_end)

    Enum.map(cy_states, fn %{timeline: t, start_count: start_count, end_count: end_count} ->
      cost_basis = t.cost_basis
      vest_fx = t.vest_fx_rate
      price_series = Map.get(price_series_map, t.symbol, %{})

      initial_value_inr = safe_mult3(cost_basis, start_count, vest_fx)

      sells_during_cy_for_peak =
        t.sells
        |> Enum.filter(fn s ->
          Date.compare(s.date, cy_start) != :lt and Date.compare(s.date, cy_end) != :gt
        end)
        |> Enum.sort_by(fn s -> Date.to_iso8601(s.date) end)
        |> Enum.map(fn s -> %{sale_date: s.date, quantity: s.quantity} end)

      {peak_value_inr, peak_price_usd, peak_date, peak_fx_rate} =
        compute_peak(
          start_count,
          sells_during_cy_for_peak,
          price_series,
          cy_start,
          cy_end,
          t.vest_date
        )

      dec31_price = get_dec31_price(price_series, cy_end)

      closing_value_inr =
        if Decimal.gt?(end_count, Decimal.new(0)) and dec31_price != nil and dec31_fx != nil do
          safe_mult3(dec31_price, end_count, dec31_fx)
        else
          Decimal.new(0)
        end

      sale_proceeds_inr = compute_state_sale_proceeds_inr(t, cy_start, cy_end)

      %{
        plan_type: t.plan_type,
        symbol: t.symbol,
        date_acquired: t.vest_date,
        quantity_start: start_count,
        quantity_held: end_count,
        initial_value_inr: initial_value_inr || Decimal.new(0),
        peak_value_inr: peak_value_inr || Decimal.new(0),
        peak_price_usd: peak_price_usd,
        peak_date: peak_date,
        peak_fx_rate: peak_fx_rate,
        closing_value_inr: closing_value_inr,
        sale_proceeds_inr: sale_proceeds_inr,
        income_from_asset: Decimal.new(0),
        cost_basis_per_share: cost_basis
      }
    end)
    |> Enum.sort_by(& &1.date_acquired, Date)
  end

  defp compute_state_sale_proceeds_inr(timeline, cy_start, cy_end) do
    timeline.sells
    |> Enum.filter(fn s ->
      Date.compare(s.date, cy_start) != :lt and Date.compare(s.date, cy_end) != :gt
    end)
    |> Enum.reduce(Decimal.new(0), fn s, acc ->
      fx = if s.price != nil, do: FX.get_rate(s.date), else: nil

      case safe_mult3(s.quantity, s.price, fx) do
        nil -> acc
        val -> Decimal.add(acc, val)
      end
    end)
  end

  # ============================================================
  # Data loading (M26)
  # ============================================================

  defp load_bh_sales(account_id) do
    Repo.all(
      from s in Sale,
        join: o in Origin,
        on: s.origin_id == o.id,
        where: s.account_id == ^account_id,
        select: %{
          sale_date: s.sale_date,
          plan_type: o.plan_type,
          origin_id: s.origin_id,
          total_quantity: s.total_quantity
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
          sale_date: s.sale_date,
          plan_type: o.plan_type
        }
    )
  end

  # ============================================================
  # Meta coverage check
  # ============================================================

  defp check_meta_coverage(rows) do
    missing =
      rows
      |> Enum.map(& &1.symbol)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reject(&StockMeta.known?/1)
      |> Enum.sort()

    if missing == [], do: :ok, else: {:error, missing}
  end

  # ============================================================
  # Row aggregation
  # ============================================================

  defp aggregate_by_date(rows) do
    rows
    |> Enum.group_by(fn r -> {r.date_acquired, r.symbol, r.cost_basis_per_share} end)
    |> Enum.map(fn {{date, symbol, cost_basis}, group} ->
      if length(group) == 1 do
        hd(group)
      else
        plan_type =
          group |> Enum.map(& &1.plan_type) |> Enum.uniq() |> Enum.join("/")

        %{
          date_acquired: date,
          symbol: symbol,
          plan_type: plan_type,
          quantity_start: sum_field(group, :quantity_start),
          quantity_held: sum_field(group, :quantity_held),
          initial_value_inr: sum_field(group, :initial_value_inr),
          peak_value_inr: sum_field(group, :peak_value_inr),
          peak_price_usd: hd(group).peak_price_usd,
          peak_date: best_peak_date(group),
          peak_fx_rate: hd(group).peak_fx_rate,
          closing_value_inr: sum_field(group, :closing_value_inr),
          sale_proceeds_inr: sum_field(group, :sale_proceeds_inr),
          income_from_asset: sum_field(group, :income_from_asset),
          cost_basis_per_share: cost_basis
        }
      end
    end)
    |> Enum.sort_by(fn r ->
      {r.symbol || "", r.date_acquired && Date.to_iso8601(r.date_acquired)}
    end)
  end

  # ============================================================
  # Price + peak helpers
  # ============================================================

  defp compute_peak(qty_start, sales_during_cy, price_series, cy_start, cy_end, vest_date) do
    effective_start =
      if Date.compare(vest_date, cy_start) == :gt, do: vest_date, else: cy_start

    intervals = build_intervals(effective_start, qty_start, sales_during_cy, cy_end)

    intervals
    |> Enum.map(fn {from, to, qty} ->
      {peak_price, peak_date} = max_price_in_range(price_series, from, to)

      if peak_price != nil and Decimal.gt?(qty, Decimal.new(0)) do
        peak_fx = FX.get_rate(peak_date)

        if peak_fx != nil do
          value = safe_mult3(peak_price, qty, peak_fx)
          {value, peak_price, peak_date, peak_fx}
        else
          nil
        end
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> {Decimal.new(0), nil, nil, nil}
      entries -> Enum.max_by(entries, fn {val, _, _, _} -> Decimal.to_float(val) end)
    end
  end

  defp build_intervals(start_date, qty_start, sales, cy_end) do
    {intervals, _} =
      Enum.reduce(sales, {[], {start_date, qty_start}}, fn sale, {acc, {from, qty}} ->
        interval = {from, sale.sale_date, qty}
        new_qty = Decimal.sub(qty, sale.quantity)
        {[interval | acc], {sale.sale_date, new_qty}}
      end)

    {last_from, last_qty} =
      case sales do
        [] -> {start_date, qty_start}
        _ -> {List.last(sales).sale_date, Decimal.sub(qty_start, sum_quantities(sales))}
      end

    final_interval =
      if Decimal.gt?(last_qty, Decimal.new(0)) and Date.compare(last_from, cy_end) != :gt do
        {last_from, cy_end, last_qty}
      else
        nil
      end

    all = Enum.reverse(intervals) ++ List.wrap(final_interval)
    Enum.reject(all, fn {_f, _t, q} -> Decimal.compare(q, Decimal.new(0)) != :gt end)
  end

  defp max_price_in_range(price_series, from, to) do
    price_series
    |> Enum.filter(fn {date, _price} ->
      Date.compare(date, from) != :lt and Date.compare(date, to) != :gt
    end)
    |> case do
      [] ->
        {nil, nil}

      prices ->
        Enum.max_by(prices, fn {_d, p} -> Decimal.to_float(parse_price(p)) end)
        |> then(fn {date, price} -> {parse_price(price), date} end)
    end
  end

  defp get_dec31_price(price_series, cy_end) do
    price_series
    |> Enum.filter(fn {date, _} -> Date.compare(date, cy_end) != :gt end)
    |> Enum.sort_by(fn {date, _} -> Date.to_iso8601(date) end, :desc)
    |> case do
      [{_d, price} | _] -> parse_price(price)
      [] -> nil
    end
  end

  defp fetch_price_series(symbols, from_date, to_date) do
    symbols
    |> Enum.map(fn symbol ->
      {symbol, StockPrice.get_close_range(symbol, from_date, to_date)}
    end)
    |> Map.new()
  end

  # ============================================================
  # Shared helpers
  # ============================================================

  defp sum_field(rows, field) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc ->
      val = Map.get(row, field)
      if val, do: Decimal.add(acc, val), else: acc
    end)
  end

  defp best_peak_date(group) do
    group
    |> Enum.reject(fn r -> r.peak_value_inr == nil end)
    |> Enum.max_by(fn r -> Decimal.to_float(r.peak_value_inr) end, fn -> nil end)
    |> then(fn
      nil -> nil
      r -> r.peak_date
    end)
  end

  defp safe_mult3(nil, _, _), do: nil
  defp safe_mult3(_, nil, _), do: nil
  defp safe_mult3(_, _, nil), do: nil
  defp safe_mult3(a, b, c), do: Decimal.mult(Decimal.mult(a, b), c)

  defp parse_price(p) when is_binary(p), do: Decimal.new(p)
  defp parse_price(%Decimal{} = d), do: d
  defp parse_price(nil), do: nil

  defp sum_quantities(allocs) do
    Enum.reduce(allocs, Decimal.new(0), fn a, acc -> Decimal.add(acc, a.quantity) end)
  end

  # ============================================================
  # CSV helpers
  # ============================================================

  defp format_csv_date(nil), do: "-"
  defp format_csv_date(%Date{} = d), do: Date.to_iso8601(d)

  defp round_inr_or_dash(nil), do: "-"

  defp round_inr_or_dash(%Decimal{} = d) do
    if Decimal.equal?(d, Decimal.new(0)),
      do: "-",
      else: Decimal.round(d, 0) |> Decimal.to_string()
  end

  defp csv_field(value) when is_binary(value) do
    # ITR Schedule FA upload rejects commas in fields (breaks CSV parsing), and
    # also rejects both quoted values and semicolons. Double space is the only
    # separator the form accepts inside a field (e.g. address). Verified working.
    cleaned = String.replace(value, ",", "  ")

    if String.contains?(cleaned, ["\"", "\n"]) do
      "\"#{String.replace(cleaned, "\"", "\"\"")}\""
    else
      cleaned
    end
  end

  defp csv_field(value), do: to_string(value)

  # ============================================================
  # Legacy private helpers (used by build_legacy only)
  # ============================================================

  defp fetch_tranches(account_id, cy_end) do
    Repo.all(
      from t in Tranche,
        join: o in Origin,
        on: t.origin_id == o.id,
        where:
          o.account_id == ^account_id and
            t.status == "VESTED" and
            t.vest_date <= ^cy_end,
        select: {t, o}
    )
  end

  defp fetch_sales_by_tranche(tranche_ids) do
    Repo.all(
      from a in SaleAllocation,
        join: s in Sale,
        on: a.sale_id == s.id,
        where: a.tranche_id in ^tranche_ids,
        select: %{
          tranche_id: a.tranche_id,
          sale_date: s.sale_date,
          quantity: a.quantity,
          total_quantity: s.total_quantity,
          sale_price: s.sale_price,
          sale_fx_rate: s.sale_fx_rate,
          proceeds: s.proceeds
        }
    )
    |> Enum.group_by(& &1.tranche_id)
  end

  defp build_row(tranche, origin, sales_by_tranche, price_series_map, cy_start, cy_end, dec31_fx) do
    allocs = Map.get(sales_by_tranche, tranche.id, [])
    net_qty = tranche.net_quantity || tranche.vest_quantity || Decimal.new(0)

    sold_before_cy =
      allocs
      |> Enum.filter(fn a -> Date.compare(a.sale_date, cy_start) == :lt end)
      |> sum_quantities()

    if Decimal.compare(sold_before_cy, net_qty) != :lt do
      nil
    else
      sales_during_cy =
        allocs
        |> Enum.filter(fn a ->
          Date.compare(a.sale_date, cy_start) != :lt and
            Date.compare(a.sale_date, cy_end) != :gt
        end)
        |> Enum.sort_by(& &1.sale_date, Date)

      sold_during_cy = sum_quantities(sales_during_cy)
      total_sold = Decimal.add(sold_before_cy, sold_during_cy)
      qty_dec31 = Decimal.sub(net_qty, total_sold)
      qty_cy_start = Decimal.sub(net_qty, sold_before_cy)

      cost_basis = resolve_cost_basis(tranche, origin)
      vest_fx = tranche.vest_fx_rate
      initial_value_inr = safe_mult3(cost_basis, qty_cy_start, vest_fx)

      price_series = Map.get(price_series_map, origin.symbol, %{})

      {peak_value_inr, peak_price_usd, peak_date, peak_fx_rate} =
        compute_peak(
          qty_cy_start,
          sales_during_cy,
          price_series,
          cy_start,
          cy_end,
          tranche.vest_date
        )

      dec31_price = get_dec31_price(price_series, cy_end)

      closing_value_inr =
        if Decimal.gt?(qty_dec31, Decimal.new(0)) and dec31_price != nil and dec31_fx != nil do
          safe_mult3(dec31_price, qty_dec31, dec31_fx)
        else
          Decimal.new(0)
        end

      sale_proceeds_inr = compute_sale_proceeds_inr(sales_during_cy)

      %{
        plan_type: origin.plan_type,
        symbol: origin.symbol,
        date_acquired: tranche.vest_date,
        quantity_held: qty_dec31,
        quantity_start: qty_cy_start,
        initial_value_inr: initial_value_inr || Decimal.new(0),
        peak_value_inr: peak_value_inr || Decimal.new(0),
        peak_price_usd: peak_price_usd,
        peak_date: peak_date,
        peak_fx_rate: peak_fx_rate,
        closing_value_inr: closing_value_inr,
        sale_proceeds_inr: sale_proceeds_inr,
        income_from_asset: Decimal.new(0),
        cost_basis_per_share: cost_basis
      }
    end
  end

  defp compute_sale_proceeds_inr(sales_during_cy) do
    Enum.reduce(sales_during_cy, Decimal.new(0), fn sale, acc ->
      proceeds_usd =
        cond do
          sale.sale_price != nil ->
            Decimal.mult(sale.quantity, sale.sale_price)

          sale.proceeds != nil and sale.total_quantity != nil and
              Decimal.gt?(sale.total_quantity, Decimal.new(0)) ->
            Decimal.mult(sale.proceeds, Decimal.div(sale.quantity, sale.total_quantity))

          true ->
            nil
        end

      if proceeds_usd != nil do
        fx = sale.sale_fx_rate || FX.get_rate(sale.sale_date)
        if fx != nil, do: Decimal.add(acc, Decimal.mult(proceeds_usd, fx)), else: acc
      else
        acc
      end
    end)
  end

  defp resolve_cost_basis(tranche, origin) do
    case origin.plan_type do
      "RSU" -> tranche.cost_basis_broker || tranche.vest_fmv || tranche.vest_day_close
      "ESPP" -> tranche.cost_basis_broker || tranche.vest_fmv
      _ -> tranche.vest_fmv
    end
  end
end
