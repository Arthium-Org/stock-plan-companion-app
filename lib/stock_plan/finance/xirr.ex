defmodule StockPlan.Finance.XIRR do
  @moduledoc """
  XIRR — internal rate of return for irregular cashflows.

  Cashflows: [{Date.t(), float()}] where negative = outflow, positive = inflow.
  Uses Newton-Raphson with bounds guard.
  """

  @max_iterations 100
  @tolerance 1.0e-7

  @spec xirr([{Date.t(), float()}], float()) :: {:ok, float()} | {:error, :no_convergence}
  def xirr(cashflows, guess \\ 0.1)
  def xirr([], _guess), do: {:error, :no_convergence}

  def xirr(cashflows, guess) do
    has_positive = Enum.any?(cashflows, fn {_, a} -> a > 0 end)
    has_negative = Enum.any?(cashflows, fn {_, a} -> a < 0 end)

    if not has_positive or not has_negative do
      {:error, :no_convergence}
    else
      first_date = cashflows |> Enum.map(&elem(&1, 0)) |> Enum.min(Date)

      flows =
        Enum.map(cashflows, fn {date, amount} ->
          {Date.diff(date, first_date) / 365.0, amount}
        end)

      do_newton(flows, guess, 0)
    end
  end

  @doc "Net present value at given rate for a cashflow list. Public for testing."
  @spec npv([{Date.t(), float()}], float()) :: float()
  def npv(cashflows, rate) do
    first_date = cashflows |> Enum.map(&elem(&1, 0)) |> Enum.min(Date)

    Enum.reduce(cashflows, 0.0, fn {date, amount}, acc ->
      t = Date.diff(date, first_date) / 365.0
      acc + amount / :math.pow(1.0 + rate, t)
    end)
  end

  # ============================================================
  # Private
  # ============================================================

  defp do_newton(_flows, _rate, iter) when iter >= @max_iterations, do: {:error, :no_convergence}

  defp do_newton(flows, rate, iter) do
    f = npv_flows(flows, rate)
    df = dnpv(flows, rate)

    cond do
      abs(df) < 1.0e-10 ->
        {:error, :no_convergence}

      abs(f) < @tolerance ->
        {:ok, Float.round(rate, 6)}

      true ->
        new_rate = rate - f / df

        if new_rate < -0.9999 or new_rate > 1_000.0 do
          {:error, :no_convergence}
        else
          do_newton(flows, new_rate, iter + 1)
        end
    end
  end

  defp npv_flows(flows, rate) do
    Enum.reduce(flows, 0.0, fn {t, amount}, acc ->
      acc + amount / :math.pow(1.0 + rate, t)
    end)
  end

  defp dnpv(flows, rate) do
    Enum.reduce(flows, 0.0, fn {t, amount}, acc ->
      acc - t * amount / :math.pow(1.0 + rate, t + 1.0)
    end)
  end
end
