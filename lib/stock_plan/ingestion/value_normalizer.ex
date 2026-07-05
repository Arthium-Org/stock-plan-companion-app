defmodule StockPlan.Ingestion.ValueNormalizer do
  @moduledoc false

  @months %{
    "JAN" => 1,
    "FEB" => 2,
    "MAR" => 3,
    "APR" => 4,
    "MAY" => 5,
    "JUN" => 6,
    "JUL" => 7,
    "AUG" => 8,
    "SEP" => 9,
    "OCT" => 10,
    "NOV" => 11,
    "DEC" => 12
  }

  @doc "Strip $, %, commas. Returns nil for empty/zero."
  @spec clean_number(any()) :: String.t() | nil
  def clean_number(nil), do: nil
  def clean_number(""), do: nil

  def clean_number(v) when is_binary(v) do
    cleaned = v |> String.replace(~r/[$%,]/, "") |> String.trim()

    case cleaned do
      "" -> nil
      "0" -> nil
      _ -> cleaned
    end
  end

  def clean_number(v) when is_float(v), do: Float.to_string(v)
  def clean_number(v) when is_integer(v), do: Integer.to_string(v)
  def clean_number(v), do: to_string(v)

  @doc "Strip $, %, commas. Keeps zero (for tax quantities where 0 is valid)."
  @spec clean_number_keep_zero(any()) :: String.t() | nil
  def clean_number_keep_zero(nil), do: nil
  def clean_number_keep_zero(""), do: nil

  def clean_number_keep_zero(v) when is_binary(v) do
    cleaned = v |> String.replace(~r/[$%,]/, "") |> String.trim()
    if cleaned == "", do: nil, else: cleaned
  end

  def clean_number_keep_zero(v) when is_float(v), do: Float.to_string(v)
  def clean_number_keep_zero(v) when is_integer(v), do: Integer.to_string(v)
  def clean_number_keep_zero(v), do: to_string(v)

  @doc "Parse DD-MMM-YYYY or MM/DD/YYYY to Date. Returns nil on failure."
  @spec parse_date(any()) :: Date.t() | nil
  def parse_date(nil), do: nil
  def parse_date(""), do: nil

  def parse_date(v) when is_binary(v) do
    cond do
      v =~ ~r/^\d{2}-[A-Z]{3}-\d{4}$/ -> parse_dmy(v)
      v =~ ~r/^\d{2}\/\d{2}\/\d{4}$/ -> parse_mdy(v)
      true -> nil
    end
  end

  def parse_date(_), do: nil

  defp parse_dmy(v) do
    [day, month, year] = String.split(v, "-")

    case Map.get(@months, month) do
      nil -> nil
      m -> Date.new!(String.to_integer(year), m, String.to_integer(day))
    end
  rescue
    _ -> nil
  end

  defp parse_mdy(v) do
    [month, day, year] = String.split(v, "/")
    Date.new!(String.to_integer(year), String.to_integer(month), String.to_integer(day))
  rescue
    _ -> nil
  end
end
