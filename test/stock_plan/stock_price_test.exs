defmodule StockPlan.StockPriceTest do
  use ExUnit.Case, async: false

  alias StockPlan.StockPrice

  describe "get_close/2" do
    @tag :external
    test "fetches historical close price for ADBE" do
      price = StockPrice.get_close("ADBE", ~D[2024-04-15])
      assert price != nil
      assert is_binary(price)
      {num, _} = Float.parse(price)
      assert num > 100 and num < 1000
    end

    @tag :external
    test "weekend date returns nearest trading day" do
      # 2024-04-13 is Saturday
      price = StockPrice.get_close("ADBE", ~D[2024-04-13])
      assert price != nil
      {num, _} = Float.parse(price)
      assert num > 100
    end

    @tag :external
    test "returns nil for invalid symbol" do
      price = StockPrice.get_close("ZZZZZZINVALID", ~D[2024-04-15])
      assert price == nil
    end
  end

  describe "get_close_range/3" do
    @tag :external
    test "fetches range of close prices" do
      prices = StockPrice.get_close_range("ADBE", ~D[2024-01-01], ~D[2024-03-31])
      assert is_map(prices)
      # ~60 trading days in Q1
      assert map_size(prices) > 50
      assert map_size(prices) < 70

      # All values are numeric strings
      for {date, price} <- prices do
        assert %Date{} = date
        assert is_binary(price)
        {num, _} = Float.parse(price)
        assert num > 100
      end
    end
  end

  describe "current_price/1" do
    @tag :external
    test "fetches current ADBE price" do
      price = StockPrice.current_price("ADBE")
      assert price != nil
      assert is_binary(price)
      {num, _} = Float.parse(price)
      assert num > 100
    end

    @tag :external
    test "second call uses cache" do
      _p1 = StockPrice.current_price("ADBE")
      # Should be instant from cache
      {time, p2} = :timer.tc(fn -> StockPrice.current_price("ADBE") end)
      assert p2 != nil
      # < 100ms (cache hit)
      assert time < 100_000
    end
  end
end
