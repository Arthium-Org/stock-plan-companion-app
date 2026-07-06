defmodule StockPlan.Tax.CapitalGainsTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Tax.CapitalGains
  alias StockPlan.Ingestions

  @bh_file "test/fixtures/sample-data/su1/sample-Etrade-BenefitHistory.xlsx"
  @gl_2025 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2025.xlsx"
  @gl_2024 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2024.xlsx"
  @gl_2023 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2023.xlsx"

  @account_id "cg_test_user"

  setup do
    {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_file)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2025)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2024)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2023)
    :ok
  end

  describe "build/2" do
    test "returns {rows, summary} for FY with sales" do
      # FY 2024-25 (Apr 2024 - Mar 2025)
      {rows, summary} = CapitalGains.build(@account_id, 2024)

      assert is_list(rows)
      assert is_map(summary)
      assert Map.has_key?(summary, :stcg_usd)
      assert Map.has_key?(summary, :stcg_inr)
      assert Map.has_key?(summary, :ltcg_usd)
      assert Map.has_key?(summary, :ltcg_inr)
      assert Map.has_key?(summary, :net_gain_usd)
      assert Map.has_key?(summary, :net_gain_inr)
      assert Map.has_key?(summary, :unknown_count)
    end

    test "each allocated row has required fields" do
      {rows, _} = CapitalGains.build(@account_id, 2024)

      allocated = Enum.filter(rows, &(&1.gain_type != :unknown))

      for row <- allocated do
        assert row.sale_date != nil
        assert row.vest_date != nil
        assert row.quantity != nil
        assert row.holding_days != nil
        assert row.gain_type in [:STCG, :STCL, :LTCG, :LTCL]
        assert row.cost_basis_per_share != nil
        assert row.proceeds_usd != nil
        assert row.cost_basis_usd != nil
        assert row.gain_loss_usd != nil
      end
    end

    test "gain_loss_usd = proceeds - cost_basis" do
      {rows, _} = CapitalGains.build(@account_id, 2024)

      allocated = Enum.filter(rows, &(&1.gain_type != :unknown))

      for row <- allocated, row.gain_loss_usd != nil do
        expected = Decimal.sub(row.proceeds_usd, row.cost_basis_usd)

        assert Decimal.compare(row.gain_loss_usd, expected) == :eq,
               "Gain mismatch: #{row.gain_loss_usd} != #{expected}"
      end
    end

    test "STCG classification for holding <= 24 months" do
      {rows, _} = CapitalGains.build(@account_id, 2024)

      stcg_rows = Enum.filter(rows, &(&1.gain_type == :STCG))

      for row <- stcg_rows do
        threshold = Date.shift(row.vest_date, year: 2)

        assert Date.compare(row.sale_date, threshold) != :gt,
               "STCG row should have sale_date <= threshold"
      end
    end

    test "LTCG classification for holding > 24 months" do
      {rows, _} = CapitalGains.build(@account_id, 2024)

      ltcg_rows = Enum.filter(rows, &(&1.gain_type == :LTCG))

      for row <- ltcg_rows do
        threshold = Date.shift(row.vest_date, year: 2)

        assert Date.compare(row.sale_date, threshold) == :gt,
               "LTCG row should have sale_date > threshold"
      end
    end

    test "summary net = stcg + ltcg" do
      {_rows, summary} = CapitalGains.build(@account_id, 2024)

      expected_usd = Decimal.add(summary.stcg_usd, summary.ltcg_usd)
      expected_inr = Decimal.add(summary.stcg_inr, summary.ltcg_inr)

      assert Decimal.compare(summary.net_gain_usd, expected_usd) == :eq
      assert Decimal.compare(summary.net_gain_inr, expected_inr) == :eq
    end

    test "no sales in FY returns empty rows and zero summary" do
      # Pick a year far in the future with no sales
      {rows, summary} = CapitalGains.build(@account_id, 2030)

      assert rows == []
      assert Decimal.compare(summary.stcg_usd, Decimal.new(0)) == :eq
      assert Decimal.compare(summary.ltcg_usd, Decimal.new(0)) == :eq
      assert summary.unknown_count == 0
    end

    test "nonexistent account returns empty" do
      {rows, summary} = CapitalGains.build("nonexistent_account", 2024)

      assert rows == []
      assert Decimal.compare(summary.net_gain_usd, Decimal.new(0)) == :eq
    end

    test "holding_days is positive for allocated rows" do
      {rows, _} = CapitalGains.build(@account_id, 2024)

      allocated = Enum.filter(rows, &(&1.gain_type != :unknown))

      for row <- allocated do
        assert row.holding_days > 0
      end
    end

    test "plan_type is present on each row" do
      {rows, _} = CapitalGains.build(@account_id, 2024)

      for row <- rows do
        assert row.plan_type in ["RSU", "ESPP"]
      end
    end
  end

  describe "build/2 with multiple FYs" do
    test "FY 2023-24 also works" do
      {rows, summary} = CapitalGains.build(@account_id, 2023)

      assert is_list(rows)
      assert is_map(summary)
    end
  end
end
