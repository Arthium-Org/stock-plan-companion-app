defmodule StockPlan.ManualTest.BHReconciliation do
  @moduledoc false

  alias StockPlan.ManualTest.Result
  alias StockPlan.Repo
  alias StockPlan.Schema.{Sale, SaleAllocation, Origin}
  import Ecto.Query

  @tolerance 2

  @doc """
  For each sale in the account's Silver layer, verify that the sum of
  sale_allocation.quantity is within ±#{@tolerance} of sale.total_quantity.

  BH sell events record total qty sold per date; G&L allocations split that
  across individual lots. Small rounding differences (up to ±#{@tolerance} shares)
  are tolerated; larger gaps indicate a tranche-matching failure.

  Returns a `Result.t()` (warning, not hard fail when tolerance exceeded).
  """
  @spec verify(String.t()) :: Result.t()
  def verify(account_id) do
    section = "BH Reconciliation — sale qty vs allocation sum"

    sales =
      Repo.all(
        from s in Sale,
          where: s.account_id == ^account_id,
          select: %{
            id: s.id,
            origin_id: s.origin_id,
            symbol: s.symbol,
            sale_date: s.sale_date,
            total_quantity: s.total_quantity
          }
      )

    if sales == [] do
      Result.pass(section, "No sales found — nothing to reconcile", [])
    else
      alloc_sums = build_alloc_sums(Enum.map(sales, & &1.id))

      origins =
        sales
        |> Enum.map(& &1.origin_id)
        |> Enum.uniq()
        |> fetch_origins()

      discrepancies =
        Enum.flat_map(sales, fn sale ->
          alloc_total = Map.get(alloc_sums, sale.id, Decimal.new(0))
          diff = Decimal.abs(Decimal.sub(alloc_total, sale.total_quantity || Decimal.new(0)))

          if Decimal.gt?(diff, Decimal.new(@tolerance)) do
            grant = origins[sale.origin_id] || "?"

            [
              "sale #{sale.id} #{sale.symbol} #{Date.to_iso8601(sale.sale_date)} " <>
                "grant=#{grant} bh_qty=#{Decimal.to_string(sale.total_quantity || Decimal.new(0))} " <>
                "alloc_sum=#{Decimal.to_string(alloc_total)} diff=#{Decimal.to_string(diff)}"
            ]
          else
            []
          end
        end)

      details =
        [
          "account: #{account_id}",
          "sales checked: #{length(sales)}",
          "tolerance: ±#{@tolerance} shares"
        ] ++
          build_row_details(sales, alloc_sums, origins)

      warn_details =
        if discrepancies == [] do
          []
        else
          [
            "WARN: #{length(discrepancies)} sale(s) have allocation gap > ±#{@tolerance} (expected for sells without G&L files):"
            | discrepancies
          ]
        end

      Result.pass(
        section,
        if(discrepancies == [],
          do:
            "All #{length(sales)} BH sales reconcile with G&L allocations (within ±#{@tolerance})",
          else:
            "#{length(discrepancies)} sale(s) exceed ±#{@tolerance} — likely missing G&L files for those FYs"
        ),
        details ++ warn_details
      )
    end
  end

  defp build_alloc_sums(sale_ids) when sale_ids == [], do: %{}

  defp build_alloc_sums(sale_ids) do
    Repo.all(
      from a in SaleAllocation,
        where: a.sale_id in ^sale_ids,
        group_by: a.sale_id,
        select: {a.sale_id, sum(a.quantity)}
    )
    |> Map.new(fn {sale_id, total} ->
      decimal_total =
        cond do
          total == nil -> Decimal.new(0)
          is_struct(total, Decimal) -> total
          is_float(total) -> Decimal.from_float(total)
          is_integer(total) -> Decimal.new(total)
          is_binary(total) -> Decimal.new(total)
          true -> Decimal.new(0)
        end

      {sale_id, decimal_total}
    end)
  end

  defp fetch_origins(origin_ids) when origin_ids == [], do: %{}

  defp fetch_origins(origin_ids) do
    Repo.all(
      from o in Origin,
        where: o.id in ^origin_ids,
        select: {o.id, o.grant_number}
    )
    |> Map.new()
  end

  defp build_row_details(sales, alloc_sums, origins) do
    sales
    |> Enum.sort_by(&{&1.sale_date, &1.symbol})
    |> Enum.map(fn sale ->
      alloc_total = Map.get(alloc_sums, sale.id, Decimal.new(0))
      diff = Decimal.abs(Decimal.sub(alloc_total, sale.total_quantity || Decimal.new(0)))
      grant = origins[sale.origin_id] || "?"
      ok = if Decimal.compare(diff, Decimal.new(@tolerance)) != :gt, do: "OK", else: "WARN"

      "  #{ok} #{Date.to_iso8601(sale.sale_date)} #{sale.symbol} #{grant} " <>
        "bh=#{Decimal.to_string(sale.total_quantity || Decimal.new(0))} " <>
        "alloc=#{Decimal.to_string(alloc_total)} diff=#{Decimal.to_string(diff)}"
    end)
  end
end
