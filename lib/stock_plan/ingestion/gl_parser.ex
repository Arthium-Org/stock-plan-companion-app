defmodule StockPlan.Ingestion.GlParser do
  @moduledoc false

  alias StockPlan.Ingestion.{BronzeRow, XlsxParser}

  @fmv_columns ["Vest Date FMV", "Exercise Date FMV"]

  @spec parse(String.t()) :: {:ok, [BronzeRow.t()], [map()]} | {:error, atom()}
  def parse(file_path) do
    if not File.exists?(file_path) do
      {:error, :file_not_found}
    else
      try do
        {:ok, tid} = Xlsxir.multi_extract(file_path, 0)
        rows = Xlsxir.get_list(tid)
        Xlsxir.close(tid)

        case rows do
          [] ->
            {:ok, [], []}

          [headers | data] ->
            clean_headers = Enum.map(headers, &clean_header/1)
            {bronze_rows, warnings} = parse_sell_rows(clean_headers, data)
            {:ok, bronze_rows, warnings}
        end
      rescue
        _ -> {:error, :invalid_format}
      catch
        _, _ -> {:error, :invalid_format}
      end
    end
  end

  defp parse_sell_rows(headers, data) do
    data
    |> Enum.with_index()
    |> Enum.filter(fn {row, _idx} -> List.first(row) == "Sell" end)
    |> Enum.reduce({[], []}, fn {row_values, idx}, {rows_acc, warns_acc} ->
      # Convert FMV columns from NaiveDateTime to decimal before JSON
      converted = convert_fmv_columns(headers, row_values)
      json = XlsxParser.row_to_json(headers, converted)
      hash_input = "G&L_Expanded:#{idx}:#{json}"

      bronze_row = %BronzeRow{
        sheet_name: "G&L_Expanded",
        record_type: "Sell",
        row_index: idx,
        parent_index: nil,
        raw_row_json: json,
        row_hash: XlsxParser.compute_hash(hash_input)
      }

      {[bronze_row | rows_acc], warns_acc}
    end)
    |> then(fn {rows, warns} -> {Enum.reverse(rows), Enum.reverse(warns)} end)
  end

  defp convert_fmv_columns(headers, values) do
    Enum.zip(headers, pad_values(values, length(headers)))
    |> Enum.map(fn {header, value} ->
      if header in @fmv_columns do
        decode_fmv(value)
      else
        value
      end
    end)
  end

  defp decode_fmv(%NaiveDateTime{} = ndt) do
    epoch = ~D[1899-12-30]
    days = Date.diff(NaiveDateTime.to_date(ndt), epoch)
    seconds = NaiveDateTime.to_time(ndt) |> Time.diff(~T[00:00:00])
    Float.round(days + seconds / 86400.0, 6)
  end

  defp decode_fmv({0, 0, 0}), do: nil
  defp decode_fmv(nil), do: nil
  defp decode_fmv(0), do: nil
  defp decode_fmv(v), do: v

  defp pad_values(values, target) when length(values) >= target, do: values
  defp pad_values(values, target), do: values ++ List.duplicate(nil, target - length(values))

  defp clean_header(nil), do: ""
  defp clean_header(h) when is_binary(h), do: String.trim(h)
  defp clean_header(h), do: to_string(h) |> String.trim()
end
