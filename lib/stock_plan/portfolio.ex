defmodule StockPlan.Portfolio do
  @moduledoc """
  Read-only portfolio context. Builds hierarchical holding data
  grouped by plan_type → origin → tranches.

  Source priority:
    1. Holdings Silver (stock_plan_holdings) — when Holdings ingestion exists
    2. BH Silver (stock_plan_tranches) — fallback when no Holdings
  """

  alias StockPlan.Repo
  alias StockPlan.Schema.{Ingestion, Holding, Origin}
  import Ecto.Query

  require Logger

  @doc """
  Build hierarchical portfolio holdings for an account.
  Returns %{"ESPP" => [origin_groups], "RSU" => [origin_groups]}.
  Source: Holdings Silver only. Returns empty groups when no Holdings ingestion exists.
  """
  def build(account_id) do
    build_from_holdings(account_id)
  end

  @doc "Flatten hierarchical data to a flat list of holding rows."
  def flat_holdings(hierarchical) do
    hierarchical
    |> Map.values()
    |> List.flatten()
    |> Enum.flat_map(& &1.tranches)
  end

  @doc "Compute summary from flat holdings list + current price string."
  def compute_summary(holdings, current_price_str) when is_list(holdings) do
    price = parse_decimal(current_price_str)

    vested = Enum.filter(holdings, &(&1.status == "VESTED"))
    unvested = Enum.filter(holdings, &(&1.status == "UNVESTED"))

    current_value = sum_value(vested, price)
    potential_value = sum_value(unvested, price)

    %{
      current_value: current_value,
      potential_value: potential_value,
      total_value: Decimal.add(current_value, potential_value),
      vested_shares: sum_qty(vested),
      unvested_shares: sum_qty(unvested),
      unvested_count: length(unvested),
      by_plan_type: build_plan_type_summary(holdings, price)
    }
  end

  @doc "Sum quantities from a list of holding rows. Public for LiveView use."
  def sum_qty_pub(holdings), do: sum_qty(holdings)

  @doc """
  Symbols the user CURRENTLY holds (sellable_qty > 0 or any unvested).
  Used by Portfolio + Sell Advisor. Returns sorted distinct list.
  """
  @spec held_symbols(String.t()) :: [String.t()]
  def held_symbols(account_id) do
    account_id
    |> build()
    |> flat_holdings()
    |> Enum.map(& &1.symbol)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Symbols the user has EVER owned (across all ACTIVE ingestions).
  Used by History + Tax Centre + Schedule FA. Includes fully-exited symbols.
  """
  @spec owned_symbols(String.t()) :: [String.t()]
  def owned_symbols(account_id) do
    Repo.all(
      from o in Origin,
        join: i in Ingestion,
        on: i.ingestion_id == o.ingestion_id,
        where: i.account_id == ^account_id and i.status == "ACTIVE",
        distinct: true,
        select: o.symbol,
        order_by: o.symbol
    )
  end

  @doc """
  One summary tile per held symbol — held qty, cost basis (USD/INR),
  current value (USD/INR), and P&L (USD/INR).

  `current_prices` is `%{symbol => Decimal | binary | nil}`.
  `current_fx` is current USD/INR rate (Decimal | nil).
  """
  @spec symbol_summaries(String.t(), map(), Decimal.t() | nil) :: [map()]
  def symbol_summaries(account_id, current_prices, current_fx \\ nil) do
    rows = account_id |> build() |> flat_holdings()

    rows
    |> Enum.group_by(& &1.symbol)
    |> Enum.map(fn {symbol, rows} ->
      vested = Enum.filter(rows, &(&1.status == "VESTED"))
      unvested = Enum.filter(rows, &(&1.status == "UNVESTED"))
      price = parse_decimal(current_prices[symbol])

      current_value_usd = sum_value(vested, price)
      potential_value_usd = sum_value(unvested, price)

      cost_basis_usd =
        Enum.reduce(vested, Decimal.new(0), fn h, acc ->
          qty = h.quantity || Decimal.new(0)
          cb = h.cost_basis_per_share || Decimal.new(0)
          Decimal.add(acc, Decimal.mult(qty, cb))
        end)

      pnl_usd = Decimal.sub(current_value_usd, cost_basis_usd)

      %{
        symbol: symbol,
        held_qty: sum_qty(vested),
        unvested_qty: sum_qty(unvested),
        cost_basis_usd: cost_basis_usd,
        cost_basis_inr: maybe_to_inr(cost_basis_usd, current_fx),
        current_value_usd: current_value_usd,
        current_value_inr: maybe_to_inr(current_value_usd, current_fx),
        potential_value_usd: potential_value_usd,
        potential_value_inr: maybe_to_inr(potential_value_usd, current_fx),
        pnl_usd: pnl_usd,
        pnl_inr: maybe_to_inr(pnl_usd, current_fx)
      }
    end)
    |> Enum.sort_by(& &1.symbol)
  end

  defp maybe_to_inr(_val, nil), do: nil
  defp maybe_to_inr(nil, _fx), do: nil
  defp maybe_to_inr(%Decimal{} = val, %Decimal{} = fx), do: Decimal.mult(val, fx)

  # ============================================================
  # Build from Holdings Silver (primary source)
  # ============================================================

  defp build_from_holdings(account_id) do
    holdings =
      Repo.all(
        from h in Holding,
          where: h.account_id == ^account_id,
          order_by: [asc: h.vest_date]
      )

    Logger.info(
      "[Portfolio.build] source=holdings, account=#{account_id}, rows=#{length(holdings)}"
    )

    # Filter: sellable_qty > 0 (vested with shares) OR UNVESTED
    visible =
      Enum.filter(holdings, fn h ->
        case h.status do
          "VESTED" ->
            h.sellable_qty != nil and Decimal.gt?(h.sellable_qty, Decimal.new(0))

          "UNVESTED" ->
            true

          _ ->
            false
        end
      end)

    # Convert to holding rows + group
    visible
    |> Enum.map(&holdings_to_row/1)
    |> Enum.group_by(& &1.origin_key)
    |> Enum.map(fn {_key, rows} -> build_origin_group_from_holdings(rows) end)
    |> Enum.group_by(& &1.plan_type)
    |> then(fn grouped ->
      %{
        "ESPP" => grouped |> Map.get("ESPP", []) |> Enum.sort_by(& &1.origin_date, Date),
        "RSU" => grouped |> Map.get("RSU", []) |> Enum.sort_by(& &1.origin_date, Date)
      }
    end)
  end

  defp holdings_to_row(h) do
    quantity =
      case h.status do
        "VESTED" -> h.sellable_qty
        "UNVESTED" -> h.vested_qty
        _ -> nil
      end

    cost_basis_source =
      cond do
        h.cost_basis != nil -> :broker
        true -> :unavailable
      end

    %{
      origin_key: {h.plan_type, h.grant_number || h.grant_date},
      origin_id: h.grant_number || to_string(h.grant_date),
      plan_type: h.plan_type,
      grant_number: h.grant_number,
      symbol: h.symbol,
      origin_date: h.grant_date,
      tranche_id: h.id,
      vest_date: h.vest_date,
      vest_period: h.vest_period,
      status: h.status,
      quantity: quantity,
      sellable_qty: h.sellable_qty,
      cost_basis_per_share: h.cost_basis,
      cost_basis_source: cost_basis_source,
      vest_fx_rate: h.vest_fx_rate,
      origin_fx_rate: nil,
      # Holdings-specific
      granted_qty: h.granted_qty,
      purchase_price: h.purchase_price,
      grant_fmv: h.grant_fmv,
      vested_qty_raw: h.vested_qty,
      released_qty: h.released_qty
    }
  end

  defp build_origin_group_from_holdings(rows) do
    first = hd(rows)
    sorted = Enum.sort_by(rows, & &1.vest_date, Date)
    vested = Enum.filter(sorted, &(&1.status == "VESTED"))
    unvested = Enum.filter(sorted, &(&1.status == "UNVESTED"))

    # Extract origin_fmv: for ESPP, use grant_fmv from first tranche (lock-in price)
    origin_fmv =
      case first.plan_type do
        "ESPP" -> first.grant_fmv
        _ -> nil
      end

    %{
      origin_id: first.origin_id,
      plan_type: first.plan_type,
      grant_number: first.grant_number,
      origin_date: first.origin_date,
      symbol: first.symbol,
      origin_fmv: origin_fmv,
      total_quantity: first.granted_qty,
      origin_fx_rate: first.origin_fx_rate,
      discount_percent: nil,
      total_qty: sum_qty(sorted),
      vested_qty: sum_qty(vested),
      unvested_qty: sum_qty(unvested),
      vested_count: length(vested),
      unvested_count: length(unvested),
      tranches: sorted
    }
  end

  # ============================================================
  # Shared helpers
  # ============================================================

  defp sum_value(holdings, price) do
    if price == nil do
      Decimal.new(0)
    else
      Enum.reduce(holdings, Decimal.new(0), fn h, acc ->
        qty = h.quantity || Decimal.new(0)
        Decimal.add(acc, Decimal.mult(qty, price))
      end)
    end
  end

  defp sum_qty(holdings) do
    Enum.reduce(holdings, Decimal.new(0), fn h, acc ->
      Decimal.add(acc, h.quantity || Decimal.new(0))
    end)
  end

  defp build_plan_type_summary(holdings, price) do
    holdings
    |> Enum.group_by(& &1.plan_type)
    |> Enum.map(fn {plan_type, rows} ->
      vested = Enum.filter(rows, &(&1.status == "VESTED"))
      unvested = Enum.filter(rows, &(&1.status == "UNVESTED"))

      {plan_type,
       %{
         current_value: sum_value(vested, price),
         potential_value: sum_value(unvested, price)
       }}
    end)
    |> Map.new()
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(v) when is_binary(v), do: Decimal.new(v)
  defp parse_decimal(%Decimal{} = d), do: d
end
