defmodule StockPlan.StockPrice do
  @moduledoc """
  Stock Price Service — fetches historical and current prices from Yahoo Finance.

  - get_close(symbol, date) → adjusted close on that date (or nearest trading day)
  - get_close_range(symbol, from, to) → map of {date => price} for all trading days
  - current_price(symbol) → latest price (cached 15 min)
  """

  alias StockPlan.StockPrice.Yahoo

  # 15 minutes
  @cache_ttl_ms 15 * 60 * 1000

  @doc "Get adjusted close price for a symbol on a date (or next trading day if weekend/holiday)."
  @spec get_close(String.t(), Date.t()) :: String.t() | nil
  def get_close(symbol, date) do
    # Fetch a range around the date to handle weekends/holidays
    prices = Yahoo.fetch_historical(symbol, date, Date.add(date, 5))

    case prices do
      %{} = map when map_size(map) > 0 ->
        # Find the closest trading day >= date (next business day)
        map
        |> Enum.filter(fn {d, _} -> Date.compare(d, date) != :lt end)
        |> Enum.sort_by(fn {d, _} -> Date.to_iso8601(d) end, :asc)
        |> case do
          [{_d, price} | _] -> price
          [] -> nil
        end

      _ ->
        nil
    end
  end

  @doc "Get adjusted close prices for all trading days in a date range."
  @spec get_close_range(String.t(), Date.t(), Date.t()) :: %{Date.t() => String.t()}
  def get_close_range(symbol, from_date, to_date) do
    Yahoo.fetch_historical(symbol, from_date, to_date)
  end

  @doc "Get current/latest price (cached for 15 minutes)."
  @spec current_price(String.t()) :: String.t() | nil
  def current_price(symbol) do
    ensure_cache_started()
    cache_key = {:current_price, symbol}

    case :ets.lookup(:stock_price_cache, cache_key) do
      [{_, price, cached_at}] ->
        if System.monotonic_time(:millisecond) - cached_at < @cache_ttl_ms do
          price
        else
          fetch_and_cache_current(symbol, cache_key)
        end

      [] ->
        fetch_and_cache_current(symbol, cache_key)
    end
  end

  defp fetch_and_cache_current(symbol, cache_key) do
    case Yahoo.fetch_current(symbol) do
      nil ->
        nil

      price ->
        :ets.insert(:stock_price_cache, {cache_key, price, System.monotonic_time(:millisecond)})
        price
    end
  end

  defp ensure_cache_started do
    if :ets.whereis(:stock_price_cache) == :undefined do
      :ets.new(:stock_price_cache, [:named_table, :public, :set])
    end
  end
end
