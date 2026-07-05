defmodule StockPlan.Ingestion.HoldingsParser do
  @moduledoc false

  alias StockPlan.Ingestion.{BronzeRow, XlsxParser}

  @sheets ["ESPP", "Restricted Stock"]
  @sheet_mapping %{"ESPP" => "Holdings_ESPP", "Restricted Stock" => "Holdings_RSU"}

  @type warning :: %{sheet_name: String.t(), row_index: non_neg_integer(), reason: atom()}

  @spec parse(String.t()) :: {:ok, [BronzeRow.t()], [warning()]} | {:error, atom()}
  def parse(file_path) do
    if not File.exists?(file_path) do
      {:error, :file_not_found}
    else
      try do
        results = Xlsxir.multi_extract(file_path)
        {rows, warnings} = process_all_sheets(results)
        {:ok, rows, warnings}
      rescue
        _ -> {:error, :invalid_format}
      catch
        _, _ -> {:error, :invalid_format}
      end
    end
  end

  defp process_all_sheets(results) when is_list(results) do
    tids =
      results
      |> Enum.filter(fn
        {:ok, _tid} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, tid} -> tid end)

    sheet_map =
      tids
      |> Enum.map(fn tid ->
        name = Xlsxir.get_info(tid, :name)
        data = Xlsxir.get_list(tid)
        Xlsxir.close(tid)
        {name, data}
      end)
      |> Map.new()

    @sheets
    |> Enum.reduce({[], []}, fn sheet_name, {all_rows, all_warnings} ->
      case Map.get(sheet_map, sheet_name) do
        nil ->
          {all_rows, all_warnings}

        [] ->
          {all_rows, all_warnings}

        [_headers_only] ->
          {all_rows, all_warnings}

        [headers | data_rows] ->
          clean_headers = headers |> Enum.map(&clean_header/1) |> deduplicate_headers()
          bronze_sheet_name = Map.fetch!(@sheet_mapping, sheet_name)
          {rows, warnings} = parse_sheet_rows(bronze_sheet_name, clean_headers, data_rows)
          {all_rows ++ rows, all_warnings ++ warnings}
      end
    end)
  end

  @doc "Parse rows from a single sheet. Public for testing."
  @spec parse_sheet_rows(String.t(), [String.t()], [[any()]]) :: {[BronzeRow.t()], [warning()]}
  def parse_sheet_rows(sheet_name, headers, data_rows) do
    {rows, warnings, _parent_idx} =
      data_rows
      |> Enum.with_index()
      |> Enum.reduce({[], [], nil}, fn {row_values, idx}, {rows_acc, warns_acc, current_parent} ->
        record_type_value = List.first(row_values)

        case classify_row(record_type_value) do
          {:parent, record_type} ->
            row = build_row(sheet_name, record_type, idx, nil, headers, row_values)
            {[row | rows_acc], warns_acc, idx}

          {:child, record_type} ->
            if current_parent == nil do
              warning = %{sheet_name: sheet_name, row_index: idx, reason: :orphan_child}
              {rows_acc, [warning | warns_acc], current_parent}
            else
              row = build_row(sheet_name, record_type, idx, current_parent, headers, row_values)
              {[row | rows_acc], warns_acc, current_parent}
            end

          :skip ->
            {rows_acc, warns_acc, current_parent}
        end
      end)

    {Enum.reverse(rows), Enum.reverse(warnings)}
  end

  defp build_row(sheet_name, record_type, row_index, parent_index, headers, row_values) do
    json = XlsxParser.row_to_json(headers, row_values)
    hash_input = "#{sheet_name}:#{row_index}:#{json}"

    %BronzeRow{
      sheet_name: sheet_name,
      record_type: record_type,
      row_index: row_index,
      parent_index: parent_index,
      raw_row_json: json,
      row_hash: XlsxParser.compute_hash(hash_input)
    }
  end

  @spec classify_row(any()) :: {:parent, String.t()} | {:child, String.t()} | :skip
  def classify_row("Grant"), do: {:parent, "Grant"}
  def classify_row("Purchase"), do: {:parent, "Purchase"}
  def classify_row("Vest Schedule"), do: {:child, "Vest Schedule"}
  def classify_row("Sellable Shares"), do: {:child, "Sellable Shares"}
  def classify_row("Tax Withholding"), do: {:child, "Tax Withholding"}
  def classify_row("Totals"), do: :skip
  def classify_row(nil), do: :skip
  def classify_row(""), do: :skip
  def classify_row(_), do: :skip

  # RS sheet has 63 columns with duplicate names (e.g., "Granted Qty." at col 4 and 21).
  # Append _2, _3 etc. to duplicates so JSON keys are unique.
  defp deduplicate_headers(headers) do
    {deduped, _counts} =
      Enum.map_reduce(headers, %{}, fn header, counts ->
        count = Map.get(counts, header, 0) + 1

        new_header = if count > 1, do: "#{header}_#{count}", else: header
        {new_header, Map.put(counts, header, count)}
      end)

    deduped
  end

  defp clean_header(nil), do: ""
  defp clean_header(h) when is_binary(h), do: String.trim(h)
  defp clean_header(h), do: to_string(h) |> String.trim()
end
