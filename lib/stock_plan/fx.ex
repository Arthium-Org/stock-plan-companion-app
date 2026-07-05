defmodule StockPlan.FX do
  @moduledoc """
  FX Rate Service — SBI TT Buying Rate lookup per Indian tax law.

  Rule: For any transaction date, use the TT buying rate from the
  last day of the PREVIOUS month. Falls back to standard_rate_month_end,
  then standard_rate_month_avg.
  """

  alias StockPlan.Repo
  alias StockPlan.Schema.FxMonthlyRate
  import Ecto.Query

  @doc """
  Get USD/INR rate for a transaction date.
  Priority: tt_buying_rate_month_end → standard_rate_month_end → standard_rate_month_avg.
  Uses the rate from the PREVIOUS month.
  """
  @spec get_rate(Date.t()) :: Decimal.t() | nil
  def get_rate(nil), do: nil

  def get_rate(date) do
    ym = previous_month_key(date)

    case Repo.one(
           from r in FxMonthlyRate, where: r.year_month == ^ym and r.currency_pair == "USD/INR"
         ) do
      nil -> nil
      rate -> pick_best_rate(rate)
    end
  end

  @doc "Get rate as string (for storing in SafeDecimal fields)."
  @spec get_rate_string(Date.t()) :: String.t() | nil
  def get_rate_string(date) do
    case get_rate(date) do
      nil -> nil
      %Decimal{} = d -> Decimal.to_string(d)
    end
  end

  @doc "Get the most recent available rate."
  @spec current_rate() :: Decimal.t() | nil
  def current_rate do
    case Repo.one(
           from r in FxMonthlyRate,
             where: r.currency_pair == "USD/INR",
             order_by: [desc: r.year_month],
             limit: 1
         ) do
      nil -> nil
      rate -> pick_best_rate(rate)
    end
  end

  @type rate_source :: :tt_buying | :standard_month_end | :standard_month_avg

  @doc """
  Get the most recent rate plus the metadata needed to label it in the UI:
  which month's row it came from and which of the three fields was picked.
  """
  @spec current_rate_info() ::
          %{rate: Decimal.t(), year_month: String.t(), source: rate_source()} | nil
  def current_rate_info do
    case Repo.one(
           from r in FxMonthlyRate,
             where: r.currency_pair == "USD/INR",
             order_by: [desc: r.year_month],
             limit: 1
         ) do
      nil ->
        nil

      rate ->
        {value, source} = pick_best_with_source(rate)

        if value do
          %{rate: value, year_month: rate.year_month, source: source}
        else
          nil
        end
    end
  end

  defp pick_best_with_source(%{tt_buying_rate_month_end: tt}) when not is_nil(tt),
    do: {tt, :tt_buying}

  defp pick_best_with_source(%{standard_rate_month_end: me}) when not is_nil(me),
    do: {me, :standard_month_end}

  defp pick_best_with_source(%{standard_rate_month_avg: avg}) when not is_nil(avg),
    do: {avg, :standard_month_avg}

  defp pick_best_with_source(_), do: {nil, nil}

  @doc """
  Compute the year_month key for the previous month.
  Transaction on April 15 → "2024-03" (March).
  Transaction on Jan 1 → previous year December.
  """
  @spec previous_month_key(Date.t()) :: String.t()
  def previous_month_key(date) do
    date
    |> Date.beginning_of_month()
    |> Date.add(-1)
    |> Calendar.strftime("%Y-%m")
  end

  # Priority: TT buying (tax-compliant) → month-end standard → monthly average
  defp pick_best_rate(%{tt_buying_rate_month_end: tt}) when not is_nil(tt), do: tt
  defp pick_best_rate(%{standard_rate_month_end: me}) when not is_nil(me), do: me
  defp pick_best_rate(%{standard_rate_month_avg: avg}) when not is_nil(avg), do: avg
  defp pick_best_rate(_), do: nil
end
