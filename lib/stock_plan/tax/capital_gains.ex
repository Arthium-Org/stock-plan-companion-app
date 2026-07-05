defmodule StockPlan.Tax.CapitalGains do
  @moduledoc """
  Capital Gains computation for an Indian Financial Year (Apr-Mar).
  Returns per-lot gain/loss rows and a summary with STCG/LTCG totals.
  """

  alias StockPlan.Repo
  alias StockPlan.Schema.{Origin, Tranche, Sale, SaleAllocation}
  import Ecto.Query

  @doc """
  Build capital gains for a Financial Year.
  FY 2024-25 → fy_start_year = 2024, period Apr 1 2024 to Mar 31 2025.
  Returns {rows, summary}.
  """
  def build(account_id, fy_start_year) do
    fy_start = Date.new!(fy_start_year, 4, 1)
    fy_end = Date.new!(fy_start_year + 1, 3, 31)

    # 1. Find all sales in the FY period
    sales = fetch_sales(account_id, fy_start, fy_end)

    if sales == [] do
      {[], zero_summary()}
    else
      # 2. Get allocations for these sales
      sale_ids = Enum.map(sales, & &1.id)
      allocations = fetch_allocations(sale_ids)

      # 3. Split into covered (have G&L allocations with a usable price) and uncovered sales.
      # A sale is covered iff it has at least one allocation with a non-nil sale_price OR
      # the sale itself has a non-nil sale_price — matching UploadChecks coverage signal.
      sales_by_id = Map.new(sales, &{&1.id, &1})

      covered_ids =
        MapSet.new(
          Enum.filter(allocations, fn {sale_id, allocs} ->
            sale = Map.get(sales_by_id, sale_id)

            Enum.any?(allocs, fn a -> a.sale_price != nil end) ||
              (sale != nil && sale.sale_price != nil)
          end),
          fn {sale_id, _} -> sale_id end
        )

      {covered_sales, uncovered_sales} =
        Enum.split_with(sales, fn s -> MapSet.member?(covered_ids, s.id) end)

      warning =
        if uncovered_sales != [] do
          dates =
            uncovered_sales
            |> Enum.map(& &1.sale_date)
            |> Enum.uniq()
            |> Enum.sort()
            |> Enum.map(&Date.to_iso8601/1)
            |> Enum.join(", ")

          fy_end_short =
            (fy_start_year + 1) |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")

          "G&L data not available. Sale(s) on #{dates} cannot be computed — upload G&L Expanded for FY#{fy_start_year}-#{fy_end_short}."
        end

      if covered_sales == [] do
        # No G&L coverage at all for this FY — return empty rows with warning
        {[], %{zero_summary() | warning: warning}}
      else
        # 4. Build rows from covered sales only
        rows = build_rows(covered_sales, allocations)

        # 5. Compute summary, attach warning
        summary = compute_summary(rows) |> Map.put(:warning, warning)

        {rows, summary}
      end
    end
  end

  # ============================================================
  # Private
  # ============================================================

  defp fetch_sales(account_id, fy_start, fy_end) do
    Repo.all(
      from s in Sale,
        join: o in Origin,
        on: s.origin_id == o.id,
        where:
          s.account_id == ^account_id and
            s.sale_date >= ^fy_start and
            s.sale_date <= ^fy_end,
        select: %{
          id: s.id,
          sale_date: s.sale_date,
          total_quantity: s.total_quantity,
          sale_price: s.sale_price,
          sale_fx_rate: s.sale_fx_rate,
          proceeds: s.proceeds,
          origin_id: s.origin_id,
          plan_type: o.plan_type,
          grant_number: o.grant_number,
          symbol: o.symbol
        }
    )
  end

  defp fetch_allocations(sale_ids) do
    Repo.all(
      from a in SaleAllocation,
        join: t in Tranche,
        on: a.tranche_id == t.id,
        join: o in Origin,
        on: t.origin_id == o.id,
        where: a.sale_id in ^sale_ids,
        select: %{
          sale_id: a.sale_id,
          tranche_id: a.tranche_id,
          quantity: a.quantity,
          sale_price: a.sale_price,
          order_number: a.order_number,
          vest_date: t.vest_date,
          vest_fmv: t.vest_fmv,
          vest_day_close: t.vest_day_close,
          vest_fx_rate: t.vest_fx_rate,
          cost_basis_broker: t.cost_basis_broker,
          plan_type: o.plan_type,
          grant_number: o.grant_number
        }
    )
    |> Enum.group_by(& &1.sale_id)
  end

  defp build_rows(sales, allocations) do
    Enum.flat_map(sales, fn sale ->
      case Map.get(allocations, sale.id) do
        nil ->
          # Sale without allocations — unknown lot
          [build_unknown_row(sale)]

        [] ->
          [build_unknown_row(sale)]

        allocs ->
          Enum.map(allocs, fn alloc -> build_allocated_row(sale, alloc) end)
      end
    end)
  end

  defp build_allocated_row(sale, alloc) do
    # Cost basis determination
    {cost_basis_per_share, cost_basis_source} = resolve_cost_basis(alloc)

    # Compute gains first (needed for 4-way classification)
    qty = alloc.quantity
    # Price from allocation (G&L data), fallback to sale (BH data)
    sale_price = alloc.sale_price || sale.sale_price

    # USD calculations
    {proceeds_usd, cost_basis_usd, gain_loss_usd} =
      compute_gain_usd(sale_price, cost_basis_per_share, qty)

    # INR calculations
    vest_fx = alloc.vest_fx_rate
    sale_fx = sale.sale_fx_rate

    {proceeds_inr, cost_basis_inr, gain_loss_inr} =
      compute_gain_inr(sale_price, cost_basis_per_share, qty, sale_fx, vest_fx)

    # 4-way holding period + gain/loss classification
    acquire_date = alloc.vest_date

    gain_positive =
      case gain_loss_inr do
        nil -> true
        val -> not Decimal.negative?(val)
      end

    {holding_days, gain_type} = classify_holding(acquire_date, sale.sale_date, gain_positive)

    %{
      sale_date: sale.sale_date,
      symbol: sale.symbol,
      plan_type: alloc.plan_type,
      grant_number: alloc.grant_number,
      order_number: alloc.order_number,
      vest_date: alloc.vest_date,
      quantity: qty,
      sale_price: sale_price,
      cost_basis_per_share: cost_basis_per_share,
      cost_basis_source: cost_basis_source,
      holding_days: holding_days,
      gain_type: gain_type,
      proceeds_usd: proceeds_usd,
      cost_basis_usd: cost_basis_usd,
      gain_loss_usd: gain_loss_usd,
      proceeds_inr: proceeds_inr,
      cost_basis_inr: cost_basis_inr,
      gain_loss_inr: gain_loss_inr,
      warning: nil
    }
  end

  defp build_unknown_row(sale) do
    sale_fx = sale.sale_fx_rate

    proceeds_usd =
      if sale.sale_price != nil do
        Decimal.mult(sale.sale_price, sale.total_quantity)
      else
        sale.proceeds
      end

    proceeds_inr =
      if proceeds_usd != nil and sale_fx != nil do
        Decimal.mult(proceeds_usd, sale_fx)
      else
        nil
      end

    %{
      sale_date: sale.sale_date,
      symbol: sale.symbol,
      plan_type: sale.plan_type,
      grant_number: sale.grant_number,
      order_number: nil,
      vest_date: nil,
      quantity: sale.total_quantity,
      sale_price: sale.sale_price,
      cost_basis_per_share: nil,
      cost_basis_source: :unavailable,
      holding_days: nil,
      gain_type: :unknown,
      proceeds_usd: proceeds_usd,
      cost_basis_usd: nil,
      gain_loss_usd: nil,
      proceeds_inr: proceeds_inr,
      cost_basis_inr: nil,
      gain_loss_inr: nil,
      warning: "Lot details unavailable — upload G&L Expanded for this FY"
    }
  end

  defp resolve_cost_basis(alloc) do
    cond do
      alloc.cost_basis_broker != nil -> {alloc.cost_basis_broker, :broker}
      alloc.vest_fmv != nil -> {alloc.vest_fmv, :actual_fmv}
      alloc.vest_day_close != nil -> {alloc.vest_day_close, :market_close}
      true -> {nil, :unavailable}
    end
  end

  defp classify_holding(nil, _sale_date, _gain_positive), do: {nil, :unknown}

  defp classify_holding(acquire_date, sale_date, gain_positive) do
    holding_days = Date.diff(sale_date, acquire_date)
    threshold = Date.shift(acquire_date, year: 2)
    long_term = Date.compare(sale_date, threshold) == :gt

    gain_type =
      case {long_term, gain_positive} do
        {true, true} -> :LTCG
        {true, false} -> :LTCL
        {false, true} -> :STCG
        {false, false} -> :STCL
      end

    {holding_days, gain_type}
  end

  defp compute_gain_usd(nil, _cost_basis, _qty), do: {nil, nil, nil}

  defp compute_gain_usd(sale_price, cost_basis_per_share, qty) do
    proceeds = Decimal.mult(sale_price, qty)

    if cost_basis_per_share != nil do
      cost = Decimal.mult(cost_basis_per_share, qty)
      gain = Decimal.sub(proceeds, cost)
      {proceeds, cost, gain}
    else
      {proceeds, nil, nil}
    end
  end

  defp compute_gain_inr(nil, _cost_basis, _qty, _sale_fx, _vest_fx), do: {nil, nil, nil}

  defp compute_gain_inr(sale_price, cost_basis_per_share, qty, sale_fx, vest_fx) do
    proceeds_inr =
      if sale_fx != nil do
        Decimal.mult(Decimal.mult(sale_price, qty), sale_fx)
      else
        nil
      end

    cost_basis_inr =
      if cost_basis_per_share != nil and vest_fx != nil do
        Decimal.mult(Decimal.mult(cost_basis_per_share, qty), vest_fx)
      else
        nil
      end

    gain_loss_inr =
      if proceeds_inr != nil and cost_basis_inr != nil do
        Decimal.sub(proceeds_inr, cost_basis_inr)
      else
        nil
      end

    {proceeds_inr, cost_basis_inr, gain_loss_inr}
  end

  defp compute_summary(rows) do
    stcg_rows = Enum.filter(rows, &(&1.gain_type in [:STCG, :STCL]))
    ltcg_rows = Enum.filter(rows, &(&1.gain_type in [:LTCG, :LTCL]))
    unknown_rows = Enum.filter(rows, &(&1.gain_type == :unknown))

    stcg_usd = sum_field(stcg_rows, :gain_loss_usd)
    stcg_inr = sum_field(stcg_rows, :gain_loss_inr)
    ltcg_usd = sum_field(ltcg_rows, :gain_loss_usd)
    ltcg_inr = sum_field(ltcg_rows, :gain_loss_inr)

    %{
      stcg_usd: stcg_usd,
      stcg_inr: stcg_inr,
      ltcg_usd: ltcg_usd,
      ltcg_inr: ltcg_inr,
      net_gain_usd: Decimal.add(stcg_usd, ltcg_usd),
      net_gain_inr: Decimal.add(stcg_inr, ltcg_inr),
      # Total sale proceeds and cost of acquisition (for ITR)
      st_proceeds_inr: sum_field(stcg_rows, :proceeds_inr),
      st_cost_inr: sum_field(stcg_rows, :cost_basis_inr),
      lt_proceeds_inr: sum_field(ltcg_rows, :proceeds_inr),
      lt_cost_inr: sum_field(ltcg_rows, :cost_basis_inr),
      total_proceeds_inr: sum_field(rows, :proceeds_inr),
      total_cost_inr: sum_field(rows, :cost_basis_inr),
      unknown_count: length(unknown_rows),
      warning: nil
    }
  end

  defp sum_field(rows, field) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc ->
      case Map.get(row, field) do
        nil -> acc
        val -> Decimal.add(acc, val)
      end
    end)
  end

  defp zero_summary do
    %{
      stcg_usd: Decimal.new(0),
      stcg_inr: Decimal.new(0),
      ltcg_usd: Decimal.new(0),
      ltcg_inr: Decimal.new(0),
      net_gain_usd: Decimal.new(0),
      net_gain_inr: Decimal.new(0),
      st_proceeds_inr: Decimal.new(0),
      st_cost_inr: Decimal.new(0),
      lt_proceeds_inr: Decimal.new(0),
      lt_cost_inr: Decimal.new(0),
      total_proceeds_inr: Decimal.new(0),
      total_cost_inr: Decimal.new(0),
      unknown_count: 0,
      warning: nil
    }
  end
end
