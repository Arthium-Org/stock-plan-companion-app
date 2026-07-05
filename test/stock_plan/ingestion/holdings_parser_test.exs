defmodule StockPlan.Ingestion.HoldingsParserTest do
  use ExUnit.Case, async: true

  @moduletag :requires_fixtures

  alias StockPlan.Ingestion.{HoldingsParser, BronzeRow}

  @sample3 "docs/Sample-Data/SampleUser - 3/Sample3-ByBenefitType_expanded.xlsx"
  @sample2 "docs/Sample-Data/SampleUser - 2/Sample2-ByBenefitType_expanded.xlsx"

  describe "parse/1 — file validation" do
    test "returns error for missing file" do
      assert {:error, :file_not_found} = HoldingsParser.parse("nonexistent.xlsx")
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = HoldingsParser.parse("mix.exs")
    end
  end

  describe "parse/1 — SampleUser-3 (ESPP + RSU)" do
    setup do
      {:ok, rows, warnings} = HoldingsParser.parse(@sample3)
      %{rows: rows, warnings: warnings}
    end

    test "parses successfully with no warnings", %{rows: rows, warnings: warnings} do
      assert length(rows) > 0
      assert warnings == []
    end

    test "ESPP rows have correct sheet_name", %{rows: rows} do
      espp = Enum.filter(rows, &(&1.sheet_name == "Holdings_ESPP"))
      assert length(espp) == 4
      assert Enum.all?(espp, &(&1.record_type == "Purchase"))
    end

    test "ESPP rows are all parents (no parent_index)", %{rows: rows} do
      espp = Enum.filter(rows, &(&1.sheet_name == "Holdings_ESPP"))
      assert Enum.all?(espp, &(&1.parent_index == nil))
    end

    test "ESPP Purchase row contains expected fields", %{rows: rows} do
      purchase = Enum.find(rows, &(&1.sheet_name == "Holdings_ESPP"))
      data = Jason.decode!(purchase.raw_row_json)
      assert data["Symbol"] == "ADBE"
      assert data["Purchase Date"] != nil
      assert data["Sellable Qty."] != nil
      assert data["Est. Cost Basis (per share):"] != nil
      assert data["Purchase Price"] != nil
    end

    test "RSU rows have correct sheet_name", %{rows: rows} do
      rsu = Enum.filter(rows, &(&1.sheet_name == "Holdings_RSU"))
      assert length(rsu) == 145
    end

    test "RSU record types match expected counts", %{rows: rows} do
      rsu = Enum.filter(rows, &(&1.sheet_name == "Holdings_RSU"))
      types = Enum.map(rsu, & &1.record_type) |> Enum.frequencies()
      assert types["Grant"] == 5
      assert types["Vest Schedule"] == 77
      assert types["Tax Withholding"] == 41
      assert types["Sellable Shares"] == 22
    end

    test "RSU Grant rows are parents", %{rows: rows} do
      grants = Enum.filter(rows, &(&1.record_type == "Grant"))
      assert Enum.all?(grants, &(&1.parent_index == nil))
    end

    test "RSU child rows have valid parent_index", %{rows: rows} do
      rsu = Enum.filter(rows, &(&1.sheet_name == "Holdings_RSU"))
      children = Enum.filter(rsu, &(&1.parent_index != nil))
      grant_indices = rsu |> Enum.filter(&(&1.record_type == "Grant")) |> Enum.map(& &1.row_index)

      for child <- children do
        assert child.parent_index in grant_indices
      end
    end

    test "Totals row is skipped", %{rows: rows} do
      refute Enum.any?(rows, &(&1.record_type == "Totals"))
    end

    test "all rows have unique row_hash", %{rows: rows} do
      hashes = Enum.map(rows, & &1.row_hash)
      assert length(hashes) == length(Enum.uniq(hashes))
    end

    test "total row count matches expected", %{rows: rows} do
      # 4 ESPP + 145 RSU = 149
      assert length(rows) == 149
    end
  end

  describe "parse/1 — SampleUser-2 (RSU only)" do
    setup do
      {:ok, rows, warnings} = HoldingsParser.parse(@sample2)
      %{rows: rows, warnings: warnings}
    end

    test "parses successfully", %{rows: rows, warnings: warnings} do
      assert length(rows) > 0
      assert warnings == []
    end

    test "no ESPP rows (RSU only user)", %{rows: rows} do
      espp = Enum.filter(rows, &(&1.sheet_name == "Holdings_ESPP"))
      assert espp == []
    end

    test "RSU rows have expected record types", %{rows: rows} do
      types = Enum.map(rows, & &1.record_type) |> Enum.frequencies()
      assert types["Grant"] == 4
      assert types["Vest Schedule"] == 64
      assert types["Tax Withholding"] == 28
      # SampleUser-2 has no Sellable Shares
      assert types["Sellable Shares"] == nil
    end

    test "total 96 rows", %{rows: rows} do
      assert length(rows) == 96
    end
  end

  describe "Sellable Shares row data" do
    test "contains Grant Number and Vest Period for matching" do
      {:ok, rows, _} = HoldingsParser.parse(@sample3)
      ss = Enum.find(rows, &(&1.record_type == "Sellable Shares"))
      data = Jason.decode!(ss.raw_row_json)
      assert data["Grant Number"] != nil
      assert data["Vest Period"] != nil
    end

    test "contains cost basis and tax status" do
      {:ok, rows, _} = HoldingsParser.parse(@sample3)
      ss = Enum.find(rows, &(&1.record_type == "Sellable Shares"))
      data = Jason.decode!(ss.raw_row_json)
      assert data["Est. Cost Basis (per share):"] != nil
      assert data["Tax Status"] in ["Long Term", "Short Term"]
    end
  end
end
