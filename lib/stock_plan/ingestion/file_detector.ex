defmodule StockPlan.Ingestion.FileDetector do
  @moduledoc """
  Detects E*Trade XLSX file types from content by inspecting sheet names and headers.

  Supported file types:
  - :benefit_history — BenefitHistory.xlsx (sheets: ESPP, Restricted Stock, Options)
  - :holdings — ByBenefitType_expanded.xlsx (sheets: ESPP, Restricted Stock — more columns, no Options)
  - :gl_expanded — G&L_Expanded.xlsx (single sheet: G&L_Expanded)
  """

  @type file_type :: :benefit_history | :holdings | :gl_expanded

  @spec detect(String.t()) :: {:ok, file_type()} | {:error, :unknown}
  def detect(xlsx_path) do
    with true <- File.exists?(xlsx_path),
         {:ok, sheets} <- extract_sheet_info(xlsx_path) do
      classify(sheets)
    else
      false -> {:error, :unknown}
      {:error, _} -> {:error, :unknown}
    end
  end

  # Returns a list of {sheet_name, headers} tuples
  defp extract_sheet_info(path) do
    try do
      results = Xlsxir.multi_extract(path)

      tids =
        results
        |> Enum.filter(fn
          {:ok, _tid} -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, tid} -> tid end)

      sheets =
        Enum.map(tids, fn tid ->
          name = Xlsxir.get_info(tid, :name)

          headers =
            case Xlsxir.get_list(tid) do
              [first_row | _] -> Enum.map(first_row, &to_string_safe/1)
              _ -> []
            end

          Xlsxir.close(tid)
          {name, headers}
        end)

      {:ok, sheets}
    rescue
      _ -> {:error, :invalid_format}
    catch
      _, _ -> {:error, :invalid_format}
    end
  end

  defp classify(sheets) do
    sheet_names = Enum.map(sheets, fn {name, _} -> name end)
    sheet_map = Map.new(sheets)

    cond do
      "G&L_Expanded" in sheet_names ->
        {:ok, :gl_expanded}

      "Options" in sheet_names ->
        {:ok, :benefit_history}

      "Restricted Stock" in sheet_names ->
        rs_headers = Map.get(sheet_map, "Restricted Stock", [])

        cond do
          length(rs_headers) >= 55 and "Est. Cost Basis (per share):" in rs_headers ->
            {:ok, :holdings}

          "Event Type" in rs_headers ->
            {:ok, :benefit_history}

          true ->
            {:error, :unknown}
        end

      true ->
        {:error, :unknown}
    end
  end

  defp to_string_safe(nil), do: ""
  defp to_string_safe(val) when is_binary(val), do: val
  defp to_string_safe(val), do: to_string(val)
end
