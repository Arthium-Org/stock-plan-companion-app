defmodule StockPlan.Ingestion.FileDetectorTest do
  use ExUnit.Case, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Ingestion.FileDetector

  @sample1_dir "test/fixtures/sample-data/su1"
  @sample3_dir "test/fixtures/sample-data/su3"

  describe "detect/1 — Benefit History" do
    test "SampleUser-1 BenefitHistory" do
      path = Path.join(@sample1_dir, "sample-Etrade-BenefitHistory.xlsx")
      assert {:ok, :benefit_history} = FileDetector.detect(path)
    end
  end

  describe "detect/1 — Holdings" do
    test "SampleUser-3 ByBenefitType_expanded" do
      path = Path.join(@sample3_dir, "Sample3-ByBenefitType_expanded.xlsx")
      assert {:ok, :holdings} = FileDetector.detect(path)
    end
  end

  describe "detect/1 — G&L Expanded" do
    test "SampleUser-1 G&L_Expanded_2025" do
      path = Path.join(@sample1_dir, "Sample-G&L_Expanded_2025.xlsx")
      assert {:ok, :gl_expanded} = FileDetector.detect(path)
    end
  end

  describe "detect/1 — unknown / error" do
    test "non-existent file returns :unknown" do
      assert {:error, :unknown} = FileDetector.detect("nonexistent.xlsx")
    end

    test "non-xlsx file returns :unknown" do
      # Use mix.exs as a non-xlsx file
      assert {:error, :unknown} = FileDetector.detect("mix.exs")
    end
  end
end
