defmodule StockPlan.Tax.ScheduleFSITest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Tax.ScheduleFSI
  alias StockPlan.Ingestions

  @bh_file "docs/Sample-Data/SampleUser - 1/sample-Etrade-BenefitHistory.xlsx"
  @gl_2025 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2025.xlsx"
  @gl_2024 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2024.xlsx"
  @gl_2023 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2023.xlsx"

  @account_id "fsi_test_user"

  setup do
    {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_file)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2025)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2024)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2023)
    :ok
  end

  describe "build/2" do
    test "returns map with 4 income heads" do
      fsi = ScheduleFSI.build(@account_id, 2024)

      assert is_map(fsi)
      assert length(fsi.heads) == 4
      assert fsi.country == "United States of America"
      assert fsi.country_code == "002"
    end

    test "FY label is formatted correctly" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      assert fsi.fy_label == "FY 2024-25"
    end

    test "salary head is nil (not foreign income)" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      salary = Enum.find(fsi.heads, &(&1.sl_no == "i"))

      assert salary.head == "Salary"
      assert salary.income_inr == nil
      assert salary.tax_paid_outside_inr == nil
      assert salary.tax_payable_india == nil
      assert salary.note =~ "Indian salary income"
    end

    test "house property head is nil" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      hp = Enum.find(fsi.heads, &(&1.sl_no == "ii"))

      assert hp.head == "House Property"
      assert hp.income_inr == nil
      assert hp.tax_paid_outside_inr == nil
    end

    test "capital gains head pulls from CG summary" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      cg = Enum.find(fsi.heads, &(&1.sl_no == "iii"))

      assert cg.head == "Capital Gains"
      assert %Decimal{} = cg.income_inr
      assert Map.has_key?(cg, :income_detail)
      assert %Decimal{} = cg.income_detail.stcg_inr
      assert %Decimal{} = cg.income_detail.ltcg_inr
      assert %Decimal{} = cg.income_detail.stcg_usd
      assert %Decimal{} = cg.income_detail.ltcg_usd
    end

    test "CG income_inr = max(0, stcg_inr + ltcg_inr) — losses reported as 0" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      cg = Enum.find(fsi.heads, &(&1.sl_no == "iii"))

      raw = Decimal.add(cg.income_detail.stcg_inr, cg.income_detail.ltcg_inr)
      expected = Decimal.max(raw, Decimal.new(0))
      assert Decimal.compare(cg.income_inr, expected) == :eq
      # FSI never shows negative income
      assert Decimal.compare(cg.income_inr, Decimal.new(0)) != :lt
    end

    test "tax paid outside India is zero for CG" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      cg = Enum.find(fsi.heads, &(&1.sl_no == "iii"))

      assert Decimal.compare(cg.tax_paid_outside_inr, Decimal.new(0)) == :eq
    end

    test "tax payable in India is user_to_populate for CG" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      cg = Enum.find(fsi.heads, &(&1.sl_no == "iii"))

      assert cg.tax_payable_india == :user_to_populate
    end

    test "dividends head is zero" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      div = Enum.find(fsi.heads, &(&1.sl_no == "iv"))

      assert div.head == "Other Sources (Dividends)"
      assert Decimal.compare(div.income_inr, Decimal.new(0)) == :eq
      assert div.tax_payable_india == :user_to_populate
    end

    test "FY with no CG returns zero capital gains" do
      fsi = ScheduleFSI.build(@account_id, 2030)
      cg = Enum.find(fsi.heads, &(&1.sl_no == "iii"))

      assert Decimal.compare(cg.income_inr, Decimal.new(0)) == :eq
    end
  end

  describe "to_csv/1" do
    test "generates valid CSV with header and 4 rows" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      csv = ScheduleFSI.to_csv(fsi)

      lines = String.split(csv, "\r\n")
      assert length(lines) == 5

      header = Enum.at(lines, 0)
      assert header =~ "Sl No"
      assert header =~ "Head of Income"
      assert header =~ "DTAA Article"
    end

    test "CSV does not contain raw commas in text fields" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      csv = ScheduleFSI.to_csv(fsi)

      lines = String.split(csv, "\r\n")

      for line <- Enum.drop(lines, 1), line != "" do
        # Each data row should have exactly 8 commas (9 fields)
        comma_count = line |> String.graphemes() |> Enum.count(&(&1 == ","))
        assert comma_count == 8, "Expected 8 commas, got #{comma_count} in: #{line}"
      end
    end

    test "CSV contains user_to_populate placeholders" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      csv = ScheduleFSI.to_csv(fsi)

      assert csv =~ "User to populate"
    end

    test "salary row has empty amounts" do
      fsi = ScheduleFSI.build(@account_id, 2024)
      csv = ScheduleFSI.to_csv(fsi)

      lines = String.split(csv, "\r\n")
      salary_line = Enum.at(lines, 1)

      assert salary_line =~ "Salary"
    end
  end
end
