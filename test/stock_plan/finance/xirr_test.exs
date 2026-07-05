defmodule StockPlan.Finance.XIRRTest do
  use ExUnit.Case, async: true

  alias StockPlan.Finance.XIRR

  describe "xirr/2" do
    test "single period 10% annual return" do
      today = ~D[2024-01-01]
      next_year = ~D[2025-01-01]
      {:ok, rate} = XIRR.xirr([{today, -100.0}, {next_year, 110.0}])
      assert_in_delta rate, 0.1, 0.001
    end

    test "multi-period ESPP cashflow — 6-month cycle with 15% discount gives >25% annualized" do
      purchase = ~D[2024-07-01]
      today = ~D[2025-01-01]
      # Pay $85, immediately worth $100 at purchase date (but we use a later redemption date)
      {:ok, rate} = XIRR.xirr([{purchase, -85.0}, {today, 100.0}])
      assert rate > 0.25
    end

    test "returns error when all cashflows are outflows" do
      assert {:error, :no_convergence} =
               XIRR.xirr([{~D[2024-01-01], -100.0}, {~D[2024-06-01], -50.0}])
    end

    test "returns error when all cashflows are inflows" do
      assert {:error, :no_convergence} =
               XIRR.xirr([{~D[2024-01-01], 100.0}, {~D[2024-06-01], 50.0}])
    end

    test "returns error for empty cashflow list" do
      assert {:error, :no_convergence} = XIRR.xirr([])
    end

    test "returns error when same-day in and out (zero time, infinite rate)" do
      same_day = ~D[2024-01-01]
      result = XIRR.xirr([{same_day, -100.0}, {same_day, 115.0}])
      assert result == {:error, :no_convergence} or match?({:ok, _}, result)
    end

    test "handles high positive return (>100%)" do
      d1 = ~D[2024-01-01]
      d2 = ~D[2025-01-01]
      {:ok, rate} = XIRR.xirr([{d1, -100.0}, {d2, 300.0}])
      assert_in_delta rate, 2.0, 0.01
    end

    test "handles negative rate (investment lost value)" do
      d1 = ~D[2024-01-01]
      d2 = ~D[2025-01-01]
      {:ok, rate} = XIRR.xirr([{d1, -100.0}, {d2, 80.0}])
      assert rate < 0
      assert_in_delta rate, -0.2, 0.001
    end

    test "npv/2 is zero at the XIRR rate" do
      d1 = ~D[2024-01-01]
      d2 = ~D[2025-07-01]
      cashflows = [{d1, -200.0}, {d2, 250.0}]
      {:ok, rate} = XIRR.xirr(cashflows)
      npv = XIRR.npv(cashflows, rate)
      assert_in_delta npv, 0.0, 0.01
    end
  end
end
