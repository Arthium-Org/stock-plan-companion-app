defmodule StockPlan.Ingestion.ValueNormalizerTest do
  use ExUnit.Case, async: true

  alias StockPlan.Ingestion.ValueNormalizer

  describe "clean_number/1" do
    test "strips $ prefix" do
      assert ValueNormalizer.clean_number("$386.88") == "386.88"
    end

    test "strips % suffix" do
      assert ValueNormalizer.clean_number("15%") == "15"
    end

    test "strips commas" do
      assert ValueNormalizer.clean_number("1,234.56") == "1234.56"
    end

    test "strips $ and commas together" do
      assert ValueNormalizer.clean_number("$1,234.56") == "1234.56"
    end

    test "passes through clean number" do
      assert ValueNormalizer.clean_number("117.6485") == "117.6485"
    end

    test "empty string returns nil" do
      assert ValueNormalizer.clean_number("") == nil
    end

    test "nil returns nil" do
      assert ValueNormalizer.clean_number(nil) == nil
    end

    test "zero returns nil" do
      assert ValueNormalizer.clean_number("0") == nil
    end

    test "integer string passes through" do
      assert ValueNormalizer.clean_number("441") == "441"
    end

    test "fractional passes through" do
      assert ValueNormalizer.clean_number("35.782") == "35.782"
    end

    test "already-numeric non-string value converted" do
      assert ValueNormalizer.clean_number(72.36) == "72.36"
    end

    test "integer non-string value converted" do
      assert ValueNormalizer.clean_number(100) == "100"
    end
  end

  describe "clean_number_keep_zero/1" do
    test "zero returns 0 string (for quantities where 0 is meaningful)" do
      assert ValueNormalizer.clean_number_keep_zero("0") == "0"
    end

    test "still strips symbols" do
      assert ValueNormalizer.clean_number_keep_zero("$0.00") == "0.00"
    end

    test "nil returns nil" do
      assert ValueNormalizer.clean_number_keep_zero(nil) == nil
    end

    test "empty returns nil" do
      assert ValueNormalizer.clean_number_keep_zero("") == nil
    end
  end

  describe "parse_date/1" do
    test "parses DD-MMM-YYYY format" do
      assert ValueNormalizer.parse_date("24-JAN-2024") == ~D[2024-01-24]
    end

    test "parses JUL" do
      assert ValueNormalizer.parse_date("03-JUL-2017") == ~D[2017-07-03]
    end

    test "parses JUN" do
      assert ValueNormalizer.parse_date("30-JUN-2025") == ~D[2025-06-30]
    end

    test "parses MM/DD/YYYY format" do
      assert ValueNormalizer.parse_date("01/15/2025") == ~D[2025-01-15]
    end

    test "parses 12/24/2019" do
      assert ValueNormalizer.parse_date("12/24/2019") == ~D[2019-12-24]
    end

    test "empty string returns nil" do
      assert ValueNormalizer.parse_date("") == nil
    end

    test "nil returns nil" do
      assert ValueNormalizer.parse_date(nil) == nil
    end

    test "NA returns nil" do
      assert ValueNormalizer.parse_date("NA") == nil
    end

    test "invalid string returns nil" do
      assert ValueNormalizer.parse_date("invalid") == nil
    end

    test "-- returns nil" do
      assert ValueNormalizer.parse_date("--") == nil
    end
  end
end
