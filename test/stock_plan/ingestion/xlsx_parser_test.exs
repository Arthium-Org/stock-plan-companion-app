defmodule StockPlan.Ingestion.XlsxParserTest do
  use ExUnit.Case, async: true

  alias StockPlan.Ingestion.XlsxParser
  alias StockPlan.Ingestion.BronzeRow

  # --- TP-1: BronzeRow struct ---

  describe "BronzeRow struct" do
    test "can be created with all fields" do
      row = %BronzeRow{
        sheet_name: "ESPP",
        record_type: "Purchase",
        row_index: 0,
        parent_index: nil,
        raw_row_json: "{}",
        row_hash: "abc"
      }

      assert row.sheet_name == "ESPP"
      assert row.parent_index == nil
    end

    test "default struct has nil fields" do
      row = %BronzeRow{}
      assert row.sheet_name == nil
      assert row.row_index == nil
    end
  end

  # --- TP-2: Row hash ---

  describe "compute_hash/1" do
    test "same input produces same hash" do
      json = ~s({"A":"1","B":"2"})
      assert XlsxParser.compute_hash(json) == XlsxParser.compute_hash(json)
    end

    test "hash is 64-char lowercase hex" do
      hash = XlsxParser.compute_hash(~s({"A":"1"}))
      assert String.length(hash) == 64
      assert hash =~ ~r/^[0-9a-f]{64}$/
    end

    test "different input produces different hash" do
      h1 = XlsxParser.compute_hash(~s({"A":"1"}))
      h2 = XlsxParser.compute_hash(~s({"A":"2"}))
      assert h1 != h2
    end
  end

  # --- TP-3: Row classification ---

  describe "classify_row/1" do
    test "Grant is parent" do
      assert XlsxParser.classify_row("Grant") == {:parent, "Grant"}
    end

    test "Purchase is parent" do
      assert XlsxParser.classify_row("Purchase") == {:parent, "Purchase"}
    end

    test "Event is child" do
      assert XlsxParser.classify_row("Event") == {:child, "Event"}
    end

    test "Vest Schedule is child" do
      assert XlsxParser.classify_row("Vest Schedule") == {:child, "Vest Schedule"}
    end

    test "Totals is skip" do
      assert XlsxParser.classify_row("Totals") == :skip
    end

    test "nil is skip" do
      assert XlsxParser.classify_row(nil) == :skip
    end

    test "empty string is skip" do
      assert XlsxParser.classify_row("") == :skip
    end

    test "unknown value is skip" do
      assert XlsxParser.classify_row("Something Else") == :skip
    end
  end

  # --- TP-4: JSON serialization ---

  describe "row_to_json/2" do
    test "headers + values produce correct JSON" do
      json = XlsxParser.row_to_json(["Symbol", "Date"], ["ADBE", "24-JAN-2025"])
      decoded = Jason.decode!(json)
      assert decoded == %{"Symbol" => "ADBE", "Date" => "24-JAN-2025"}
    end

    test "nil values become null in JSON" do
      json = XlsxParser.row_to_json(["A", "B"], [nil, nil])
      decoded = Jason.decode!(json)
      assert decoded == %{"A" => nil, "B" => nil}
    end

    test "short row padded with nil" do
      json = XlsxParser.row_to_json(["A", "B", "C"], ["x", "y"])
      decoded = Jason.decode!(json)
      assert decoded == %{"A" => "x", "B" => "y", "C" => nil}
    end

    test "extra values ignored" do
      json = XlsxParser.row_to_json(["A", "B"], ["x", "y", "z"])
      decoded = Jason.decode!(json)
      assert decoded == %{"A" => "x", "B" => "y"}
    end

    test "numeric values converted to string" do
      json = XlsxParser.row_to_json(["Price"], [72.36])
      decoded = Jason.decode!(json)
      assert decoded == %{"Price" => "72.36"}
    end

    test "integer values converted to string" do
      json = XlsxParser.row_to_json(["Qty"], [100])
      decoded = Jason.decode!(json)
      assert decoded == %{"Qty" => "100"}
    end

    test "keys are sorted alphabetically for deterministic output" do
      json1 = XlsxParser.row_to_json(["B", "A"], ["2", "1"])
      json2 = XlsxParser.row_to_json(["A", "B"], ["1", "2"])
      assert json1 == json2
    end
  end

  # --- TP-5: Parent-child index tracking ---

  describe "parse_sheet_rows/2" do
    test "parent row gets parent_index nil" do
      rows = [
        ["Grant", "ADBE", "24-JAN-2025"]
      ]

      {bronze_rows, _warnings} =
        XlsxParser.parse_sheet_rows("Restricted Stock", ["Record Type", "Symbol", "Date"], rows)

      assert length(bronze_rows) == 1
      assert hd(bronze_rows).parent_index == nil
      assert hd(bronze_rows).record_type == "Grant"
    end

    test "child rows get parent's row_index" do
      rows = [
        ["Grant", "ADBE", "24-JAN-2025"],
        ["Event", nil, "01/27/2025"],
        ["Event", nil, "01/27/2025"]
      ]

      {bronze_rows, _warnings} =
        XlsxParser.parse_sheet_rows("Restricted Stock", ["Record Type", "Symbol", "Date"], rows)

      assert Enum.at(bronze_rows, 0).parent_index == nil
      assert Enum.at(bronze_rows, 1).parent_index == 0
      assert Enum.at(bronze_rows, 2).parent_index == 0
    end

    test "new parent resets parent_index" do
      rows = [
        ["Grant", "ADBE", "24-JAN-2025"],
        ["Event", nil, "01/27/2025"],
        ["Grant", "ADBE", "15-MAR-2024"],
        ["Event", nil, "03/15/2024"]
      ]

      {bronze_rows, _warnings} =
        XlsxParser.parse_sheet_rows("Restricted Stock", ["Record Type", "Symbol", "Date"], rows)

      assert Enum.at(bronze_rows, 0).parent_index == nil
      assert Enum.at(bronze_rows, 1).parent_index == 0
      assert Enum.at(bronze_rows, 2).parent_index == nil
      assert Enum.at(bronze_rows, 3).parent_index == 2
    end

    test "orphan child before any parent is skipped with warning" do
      rows = [
        ["Event", nil, "01/27/2025"],
        ["Grant", "ADBE", "24-JAN-2025"]
      ]

      {bronze_rows, warnings} =
        XlsxParser.parse_sheet_rows("Restricted Stock", ["Record Type", "Symbol", "Date"], rows)

      assert length(bronze_rows) == 1
      assert hd(bronze_rows).record_type == "Grant"
      assert length(warnings) == 1
      assert hd(warnings).reason == :orphan_child
    end

    test "Totals rows are skipped" do
      rows = [
        ["Grant", "ADBE", "24-JAN-2025"],
        ["Totals", nil, nil]
      ]

      {bronze_rows, _warnings} =
        XlsxParser.parse_sheet_rows("Restricted Stock", ["Record Type", "Symbol", "Date"], rows)

      assert length(bronze_rows) == 1
    end

    test "all rows have correct sheet_name" do
      rows = [["Purchase", "ADBE", "30-JUN-2024"]]

      {bronze_rows, _warnings} =
        XlsxParser.parse_sheet_rows("ESPP", ["Record Type", "Symbol", "Date"], rows)

      assert hd(bronze_rows).sheet_name == "ESPP"
    end

    test "row_hash is 64-char hex" do
      rows = [["Grant", "ADBE", "24-JAN-2025"]]

      {bronze_rows, _warnings} =
        XlsxParser.parse_sheet_rows("Restricted Stock", ["Record Type", "Symbol", "Date"], rows)

      assert hd(bronze_rows).row_hash =~ ~r/^[0-9a-f]{64}$/
    end

    test "raw_row_json is valid JSON" do
      rows = [["Grant", "ADBE", "24-JAN-2025"]]

      {bronze_rows, _warnings} =
        XlsxParser.parse_sheet_rows("Restricted Stock", ["Record Type", "Symbol", "Date"], rows)

      assert {:ok, _} = Jason.decode(hd(bronze_rows).raw_row_json)
    end
  end

  # --- TP-7: Full parser error cases ---

  describe "parse/1 error cases" do
    test "non-existent file returns error" do
      assert {:error, :file_not_found} = XlsxParser.parse("/tmp/nonexistent_file.xlsx")
    end

    test "non-xlsx file returns error" do
      path = Path.join(System.tmp_dir!(), "test_not_xlsx.txt")
      File.write!(path, "this is not an xlsx file")

      assert {:error, :invalid_format} = XlsxParser.parse(path)
    after
      File.rm(Path.join(System.tmp_dir!(), "test_not_xlsx.txt"))
    end
  end
end
