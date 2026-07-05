defmodule StockPlan.Ingestion.GlParserTest do
  use ExUnit.Case, async: true

  @moduletag :requires_fixtures

  alias StockPlan.Ingestion.{GlParser, BronzeRow}

  @gl_2025 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2025.xlsx"
  @gl_2024 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2024.xlsx"

  describe "parse/1" do
    test "parses G&L file successfully" do
      assert {:ok, rows, warnings} = GlParser.parse(@gl_2025)
      assert length(rows) > 0
      assert is_list(warnings)
    end

    test "all rows have sheet_name G&L_Expanded" do
      {:ok, rows, _} = GlParser.parse(@gl_2025)
      assert Enum.all?(rows, &(&1.sheet_name == "G&L_Expanded"))
    end

    test "all rows have record_type Sell" do
      {:ok, rows, _} = GlParser.parse(@gl_2025)
      assert Enum.all?(rows, &(&1.record_type == "Sell"))
    end

    test "Summary rows skipped" do
      {:ok, rows, _} = GlParser.parse(@gl_2025)

      for row <- rows do
        decoded = Jason.decode!(row.raw_row_json)
        refute decoded["Record Type"] == "Summary"
      end
    end

    test "2025 file has 83 Sell rows" do
      {:ok, rows, _} = GlParser.parse(@gl_2025)
      assert length(rows) == 83
    end

    test "parent_index nil for all rows" do
      {:ok, rows, _} = GlParser.parse(@gl_2025)
      assert Enum.all?(rows, &(&1.parent_index == nil))
    end

    test "row_hash is 64-char hex, no duplicates" do
      {:ok, rows, _} = GlParser.parse(@gl_2025)
      hashes = Enum.map(rows, & &1.row_hash)
      assert Enum.all?(hashes, &(&1 =~ ~r/^[0-9a-f]{64}$/))
      assert length(hashes) == length(Enum.uniq(hashes))
    end

    test "raw_row_json is valid JSON with expected fields" do
      {:ok, rows, _} = GlParser.parse(@gl_2025)
      row = hd(rows)
      decoded = Jason.decode!(row.raw_row_json)
      assert Map.has_key?(decoded, "Grant Number")
      assert Map.has_key?(decoded, "Vest Date")
      assert Map.has_key?(decoded, "Date Sold")
      assert Map.has_key?(decoded, "Proceeds Per Share")
      assert Map.has_key?(decoded, "Order Number")
    end

    test "Vest Date FMV converted from NaiveDateTime to decimal string" do
      {:ok, rows, _} = GlParser.parse(@gl_2025)

      rs_row =
        Enum.find(rows, fn r ->
          d = Jason.decode!(r.raw_row_json)
          d["Plan Type"] == "RS" && d["Vest Date FMV"] != nil
        end)

      assert rs_row != nil
      decoded = Jason.decode!(rs_row.raw_row_json)
      fmv = decoded["Vest Date FMV"]

      assert is_binary(fmv)
      {num, _} = Float.parse(fmv)
      # FMV should be a stock price, not an Excel serial
      assert num > 100
    end

    test "parses 2024 file" do
      {:ok, rows, _} = GlParser.parse(@gl_2024)
      assert length(rows) == 11
    end

    test "non-existent file returns error" do
      assert {:error, :file_not_found} = GlParser.parse("/tmp/nonexistent.xlsx")
    end

    test "all rows are BronzeRow structs" do
      {:ok, rows, _} = GlParser.parse(@gl_2025)
      assert Enum.all?(rows, &match?(%BronzeRow{}, &1))
    end
  end
end
