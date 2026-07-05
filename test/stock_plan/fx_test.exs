defmodule StockPlan.FXTest do
  use StockPlan.DataCase, async: false

  alias StockPlan.FX
  alias StockPlan.Repo
  alias StockPlan.ID

  setup do
    Repo.delete_all(StockPlan.Schema.FxMonthlyRate)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rates = [
      # Has all three rates
      %{
        id: ID.generate(),
        rate_date: ~D[2024-02-29],
        year_month: "2024-02",
        currency_pair: "USD/INR",
        tt_buying_rate_month_end: "82.49",
        standard_rate_month_end: "82.90",
        standard_rate_month_avg: "82.97",
        source: "TEST",
        inserted_at: now,
        updated_at: now
      },
      # TT nil, has month-end standard
      %{
        id: ID.generate(),
        rate_date: ~D[2024-03-31],
        year_month: "2024-03",
        currency_pair: "USD/INR",
        tt_buying_rate_month_end: nil,
        standard_rate_month_end: "83.04",
        standard_rate_month_avg: "83.10",
        source: "TEST",
        inserted_at: now,
        updated_at: now
      },
      # Only month-avg available
      %{
        id: ID.generate(),
        rate_date: ~D[2019-06-30],
        year_month: "2019-06",
        currency_pair: "USD/INR",
        tt_buying_rate_month_end: nil,
        standard_rate_month_end: nil,
        standard_rate_month_avg: "69.49",
        source: "TEST",
        inserted_at: now,
        updated_at: now
      }
    ]

    Repo.insert_all("stock_plan_fx_monthly_rates", rates)
    :ok
  end

  describe "get_rate/1" do
    test "returns TT buying rate when available (highest priority)" do
      rate = FX.get_rate(~D[2024-03-15])
      assert Decimal.equal?(rate, Decimal.new("82.49"))
    end

    test "falls back to standard month-end when TT nil" do
      rate = FX.get_rate(~D[2024-04-15])
      assert Decimal.equal?(rate, Decimal.new("83.04"))
    end

    test "falls back to standard month-avg when both TT and month-end nil" do
      rate = FX.get_rate(~D[2019-07-15])
      assert Decimal.equal?(rate, Decimal.new("69.49"))
    end

    test "returns nil when no rate exists" do
      assert FX.get_rate(~D[2010-05-15]) == nil
    end

    test "nil date returns nil" do
      assert FX.get_rate(nil) == nil
    end
  end

  describe "previous_month_key/1" do
    test "April 15 → 2024-03" do
      assert FX.previous_month_key(~D[2024-04-15]) == "2024-03"
    end

    test "January 1 → previous year December" do
      assert FX.previous_month_key(~D[2024-01-01]) == "2023-12"
    end

    test "last day of month → previous month" do
      assert FX.previous_month_key(~D[2024-03-31]) == "2024-02"
    end
  end
end
