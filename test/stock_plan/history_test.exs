defmodule StockPlan.HistoryTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.History
  alias StockPlan.Ingestions

  @bh_user1 "test/fixtures/sample-data/su1/sample-Etrade-BenefitHistory.xlsx"
  @gl_user1 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2025.xlsx"

  @bh_adbe "test/fixtures/sample-data/su5/SampleUser5-BenefitHistory-ADBE.xlsx"
  @bh_crm "test/fixtures/sample-data/su5/SampleUser5-BenefitHistory-CRM.xlsx"
  @gl_su5 "test/fixtures/sample-data/su5/SampleUser5-G&L_Expanded.xlsx"

  describe "build/1 — empty account" do
    test "returns empty maps when no data uploaded" do
      result = History.build("hist_empty_#{System.unique_integer()}")
      assert result.symbols == []
      assert result.rsu == %{}
      assert result.espp == %{}
    end
  end

  describe "build/1 — single symbol (SU1 BH)" do
    setup do
      account = "hist_su1_#{System.unique_integer()}"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_user1)
      {:ok, _} = Ingestions.ingest_gl(account, @gl_user1)
      {:ok, account: account}
    end

    test "returns the single symbol", %{account: account} do
      result = History.build(account)
      assert length(result.symbols) == 1
      [sym] = result.symbols
      assert is_binary(sym)
    end

    test "no _combined key when single symbol", %{account: account} do
      result = History.build(account)
      refute Map.has_key?(result.rsu, "_combined")
      refute Map.has_key?(result.espp, "_combined")
    end

    test "rsu summary has required §G.1 keys", %{account: account} do
      result = History.build(account)
      [sym] = result.symbols
      rsu = result.rsu[sym]

      if rsu do
        s = rsu.summary
        assert is_integer(s.grant_count)
        assert %Decimal{} = s.grant_promise_usd
        assert %Decimal{} = s.income_recognized_usd
        assert %Decimal{} = s.vested_net_shares
        assert %Decimal{} = s.unvested_gross_shares
        # still_to_vest may be nil when no current price
        assert is_nil(s.still_to_vest_usd) or match?(%Decimal{}, s.still_to_vest_usd)
        assert is_nil(s.vest_vs_grant_drift_pct) or match?(%Decimal{}, s.vest_vs_grant_drift_pct)
      end
    end

    test "rsu section has income_by_year and grants_by_year", %{account: account} do
      result = History.build(account)
      [sym] = result.symbols
      rsu = result.rsu[sym]

      if rsu do
        assert is_list(rsu.income_by_year)
        assert is_list(rsu.grants_by_year)
        assert is_list(rsu.grants)
      end
    end

    test "income_by_year rows are sorted ascending", %{account: account} do
      result = History.build(account)
      [sym] = result.symbols
      rsu = result.rsu[sym]

      if rsu && rsu.income_by_year != [] do
        years = Enum.map(rsu.income_by_year, & &1.year)
        assert years == Enum.sort(years)
      end
    end

    test "grant rows have §G.4 columns only — no sold/proceeds/return_pct", %{account: account} do
      result = History.build(account)
      [sym] = result.symbols
      rsu = result.rsu[sym]

      if rsu && rsu.grants != [] do
        for g <- rsu.grants do
          assert is_binary(g.grant_number) or is_nil(g.grant_number)
          assert %Date{} = g.grant_date
          assert %Decimal{} = g.granted_qty
          assert %Decimal{} = g.grant_promise_usd
          assert %Decimal{} = g.recognized_usd
          # still_to_vest and vs_promise may be nil
          assert is_nil(g.still_to_vest_usd) or match?(%Decimal{}, g.still_to_vest_usd)
          assert is_nil(g.vested_pct) or match?(%Decimal{}, g.vested_pct)
          # Removed fields must not be present
          refute Map.has_key?(g, :sold_qty)
          refute Map.has_key?(g, :realized_proceeds_usd)
          refute Map.has_key?(g, :unrealized_value_usd)
          refute Map.has_key?(g, :return_pct)
        end
      end
    end

    test "rsu build output has no tax_paid_by_year/counterfactual/velocity/yoy", %{
      account: account
    } do
      result = History.build(account)
      [sym] = result.symbols
      rsu = result.rsu[sym]

      if rsu do
        refute Map.has_key?(rsu, :tax_paid_by_year)
        refute Map.has_key?(rsu, :counterfactual)
        refute Map.has_key?(rsu, :velocity)
        refute Map.has_key?(rsu, :yoy)
        refute Map.has_key?(rsu, :cumulative_income_by_year)
      end
    end

    test "espp summary has net_discount_usd (not total_discount)", %{account: account} do
      result = History.build(account)
      [sym] = result.symbols
      espp = result.espp[sym]

      if espp do
        s = espp.summary
        assert Map.has_key?(s, :net_discount_usd)
        refute Map.has_key?(s, :total_discount_usd)
        # New summary fields present
        assert Map.has_key?(s, :realized_proceeds_usd)
        assert Map.has_key?(s, :total_pnl_usd)
        assert Map.has_key?(s, :total_return_pct)
      end
    end

    test "espp lots have net_buy_price field", %{account: account} do
      result = History.build(account)
      [sym] = result.symbols
      espp = result.espp[sym]

      if espp && espp.lots != [] do
        for lot <- espp.lots do
          assert Map.has_key?(lot, :net_buy_price)
          assert Map.has_key?(lot, :realized_proceeds)
        end
      end
    end
  end

  describe "build/1 — multi-symbol (SU5 ADBE + CRM)" do
    setup do
      account = "hist_su5_#{System.unique_integer()}"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_adbe)
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_crm)
      {:ok, _} = Ingestions.ingest_gl(account, @gl_su5)
      {:ok, account: account}
    end

    test "returns both symbols", %{account: account} do
      result = History.build(account)
      assert length(result.symbols) == 2
      assert "ADBE" in result.symbols or "CRM" in result.symbols
    end

    test "no _combined key for multi-symbol", %{account: account} do
      result = History.build(account)
      refute Map.has_key?(result.rsu, "_combined")
      refute Map.has_key?(result.espp, "_combined")
    end

    test "each symbol has its own rsu entry", %{account: account} do
      result = History.build(account)

      for sym <- result.symbols do
        assert Map.has_key?(result.rsu, sym)
        rsu = result.rsu[sym]
        if rsu, do: assert(is_list(rsu.grants))
      end
    end

    test "rsu summary vested_net_shares is non-negative per symbol", %{account: account} do
      result = History.build(account)

      for sym <- result.symbols do
        rsu = result.rsu[sym]

        if rsu do
          assert Decimal.compare(rsu.summary.vested_net_shares, Decimal.new(0)) in [:eq, :gt]
        end
      end
    end
  end
end
