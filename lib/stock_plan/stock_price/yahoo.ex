defmodule StockPlan.StockPrice.Yahoo do
  @moduledoc false

  @base_url "https://query1.finance.yahoo.com/v8/finance/chart"

  @doc "Fetch historical adjusted close prices for a date range."
  @spec fetch_historical(String.t(), Date.t(), Date.t()) :: %{Date.t() => String.t()}
  def fetch_historical(symbol, from_date, to_date) do
    period1 = date_to_unix(from_date)
    # inclusive end
    period2 = date_to_unix(Date.add(to_date, 1))

    url = "#{@base_url}/#{symbol}?period1=#{period1}&period2=#{period2}&interval=1d"

    case Req.get(url, headers: [{"user-agent", "StockPlanManager/1.0"}]) do
      {:ok, %{status: 200, body: body}} ->
        parse_historical(body)

      _ ->
        %{}
    end
  end

  @doc "Fetch current/latest price."
  @spec fetch_current(String.t()) :: String.t() | nil
  def fetch_current(symbol) do
    url = "#{@base_url}/#{symbol}?range=1d&interval=1d"

    case Req.get(url, headers: [{"user-agent", "StockPlanManager/1.0"}]) do
      {:ok, %{status: 200, body: body}} ->
        parse_current(body)

      _ ->
        nil
    end
  end

  defp parse_historical(body) do
    with %{"chart" => %{"result" => [result | _]}} <- body,
         %{"timestamp" => timestamps} <- result,
         %{"indicators" => %{"adjclose" => [%{"adjclose" => closes} | _]}} <- result do
      Enum.zip(timestamps, closes)
      |> Enum.reject(fn {_, close} -> is_nil(close) end)
      |> Enum.map(fn {ts, close} ->
        date = DateTime.from_unix!(ts) |> DateTime.to_date()
        price = Float.round(close / 1.0, 6) |> Float.to_string()
        {date, price}
      end)
      |> Map.new()
    else
      _ -> %{}
    end
  end

  defp parse_current(body) do
    with %{"chart" => %{"result" => [result | _]}} <- body,
         %{"meta" => %{"regularMarketPrice" => price}} <- result do
      Float.round(price / 1.0, 2) |> Float.to_string()
    else
      _ -> nil
    end
  end

  defp date_to_unix(date) do
    date
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.to_unix()
  end
end
