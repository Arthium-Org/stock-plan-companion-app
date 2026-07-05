defmodule StockPlan.Ingestion.XlsxParserIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Ingestion.XlsxParser
  alias StockPlan.Ingestion.BronzeRow

  @sample1 "docs/Sample-Data/SampleUser - 1/sample-Etrade-BenefitHistory.xlsx"
  @sample2 "docs/Sample-Data/SampleUser - 2/Sample2-BenefitHistory.xlsx"

  @expected_sheets ["ESPP", "Restricted Stock", "Options"]
  @expected_record_types ["Grant", "Purchase", "Event", "Vest Schedule"]

  describe "SampleUser-1 BenefitHistory" do
    @tag :integration
    test "parses successfully" do
      assert {:ok, rows, warnings} = XlsxParser.parse(@sample1)
      assert is_list(rows)
      assert length(rows) > 0
      assert is_list(warnings)

      IO.puts("  SampleUser-1: #{length(rows)} rows, #{length(warnings)} warnings")
    end

    @tag :integration
    test "all rows have valid sheet_name" do
      {:ok, rows, _} = XlsxParser.parse(@sample1)

      for row <- rows do
        assert row.sheet_name in @expected_sheets,
               "unexpected sheet: #{row.sheet_name}"
      end
    end

    @tag :integration
    test "all rows have valid record_type" do
      {:ok, rows, _} = XlsxParser.parse(@sample1)

      for row <- rows do
        assert row.record_type in @expected_record_types,
               "unexpected record_type: #{row.record_type}"
      end
    end

    @tag :integration
    test "parent rows have nil parent_index" do
      {:ok, rows, _} = XlsxParser.parse(@sample1)
      parents = Enum.filter(rows, &(&1.record_type in ["Grant", "Purchase"]))

      for row <- parents do
        assert row.parent_index == nil,
               "parent row #{row.row_index} in #{row.sheet_name} has parent_index #{row.parent_index}"
      end
    end

    @tag :integration
    test "child rows have non-nil parent_index" do
      {:ok, rows, _} = XlsxParser.parse(@sample1)
      children = Enum.filter(rows, &(&1.record_type in ["Event", "Vest Schedule"]))

      for row <- children do
        assert row.parent_index != nil,
               "child row #{row.row_index} in #{row.sheet_name} has nil parent_index"
      end
    end

    @tag :integration
    test "row_hash format is correct" do
      {:ok, rows, _} = XlsxParser.parse(@sample1)

      for row <- rows do
        assert row.row_hash =~ ~r/^[0-9a-f]{64}$/,
               "bad hash: #{row.row_hash}"
      end
    end

    @tag :integration
    test "no duplicate row_hash within same sheet" do
      {:ok, rows, _} = XlsxParser.parse(@sample1)

      rows
      |> Enum.group_by(& &1.sheet_name)
      |> Enum.each(fn {sheet, sheet_rows} ->
        hashes = Enum.map(sheet_rows, & &1.row_hash)

        assert length(hashes) == length(Enum.uniq(hashes)),
               "duplicate hashes in #{sheet}"
      end)
    end

    @tag :integration
    test "all rows are BronzeRow structs" do
      {:ok, rows, _} = XlsxParser.parse(@sample1)

      for row <- rows do
        assert %BronzeRow{} = row
      end
    end
  end

  describe "SampleUser-2 BenefitHistory" do
    @tag :integration
    test "parses successfully with valid structure" do
      assert {:ok, rows, warnings} = XlsxParser.parse(@sample2)
      assert length(rows) > 0

      for row <- rows do
        assert row.sheet_name in @expected_sheets
        assert row.record_type in @expected_record_types
        assert row.row_hash =~ ~r/^[0-9a-f]{64}$/
      end

      IO.puts("  SampleUser-2: #{length(rows)} rows, #{length(warnings)} warnings")
    end
  end
end
