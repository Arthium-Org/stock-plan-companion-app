defmodule StockPlan.Ingestion.XlsxParser do
  @moduledoc false

  alias StockPlan.Ingestion.BronzeRow

  @sheets ["ESPP", "Restricted Stock", "Options"]

  @type warning :: %{sheet_name: String.t(), row_index: non_neg_integer(), reason: atom()}

  @spec parse(String.t()) :: {:ok, [BronzeRow.t()], [warning()]} | {:error, atom()}
  def parse(file_path) do
    cond do
      not File.exists?(file_path) ->
        {:error, :file_not_found}

      true ->
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
          clean_headers = Enum.map(headers, &clean_header/1)
          {rows, warnings} = parse_sheet_rows(sheet_name, clean_headers, data_rows)
          {all_rows ++ rows, all_warnings ++ warnings}
      end
    end)
  end

  defp clean_header(nil), do: ""
  defp clean_header(h) when is_binary(h), do: String.trim(h)
  defp clean_header(h), do: to_string(h) |> String.trim()

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
    json = row_to_json(headers, row_values)
    # Hash includes sheet_name + row_index to disambiguate identical rows
    hash_input = "#{sheet_name}:#{row_index}:#{json}"

    %BronzeRow{
      sheet_name: sheet_name,
      record_type: record_type,
      row_index: row_index,
      parent_index: parent_index,
      raw_row_json: json,
      row_hash: compute_hash(hash_input)
    }
  end

  @doc "Classify a Record Type value. Public for testing."
  @spec classify_row(any()) :: {:parent, String.t()} | {:child, String.t()} | :skip
  def classify_row("Grant"), do: {:parent, "Grant"}
  def classify_row("Purchase"), do: {:parent, "Purchase"}
  def classify_row("Event"), do: {:child, "Event"}
  def classify_row("Vest Schedule"), do: {:child, "Vest Schedule"}
  def classify_row("Totals"), do: :skip
  def classify_row(nil), do: :skip
  def classify_row(""), do: :skip
  def classify_row(_), do: :skip

  @doc "Serialize headers + values to deterministic JSON. Public for testing."
  @spec row_to_json([String.t()], [any()]) :: String.t()
  def row_to_json(headers, values) do
    padded = pad_or_trim(values, length(headers))

    pairs =
      headers
      |> Enum.zip(padded)
      |> Enum.map(fn {k, v} -> {k, stringify_value(v)} end)
      |> Enum.sort_by(fn {k, _} -> k end)

    Jason.encode_to_iodata!(%Jason.OrderedObject{values: pairs})
    |> IO.iodata_to_binary()
  end

  defp stringify_value(nil), do: nil
  defp stringify_value(v) when is_binary(v), do: v
  defp stringify_value(v) when is_integer(v), do: Integer.to_string(v)
  defp stringify_value(v) when is_float(v), do: Float.to_string(v)
  defp stringify_value(v) when is_boolean(v), do: Atom.to_string(v)

  defp stringify_value({y, m, d}) when is_integer(y) and is_integer(m) and is_integer(d) do
    Date.new!(y, m, d) |> Date.to_iso8601()
  end

  defp stringify_value(v), do: inspect(v)

  defp pad_or_trim(values, target_len) when length(values) >= target_len do
    Enum.take(values, target_len)
  end

  defp pad_or_trim(values, target_len) do
    values ++ List.duplicate(nil, target_len - length(values))
  end

  @doc "Compute SHA256 hash of a string. Public for testing."
  @spec compute_hash(String.t()) :: String.t()
  def compute_hash(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end
end
