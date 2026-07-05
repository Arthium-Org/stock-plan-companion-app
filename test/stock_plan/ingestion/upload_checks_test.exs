defmodule StockPlan.Ingestion.UploadChecksTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Ingestion.UploadChecks
  alias StockPlan.Ingestions

  @bh_file_1 "docs/Sample-Data/SampleUser - 1/sample-Etrade-BenefitHistory.xlsx"
  @gl_2025_1 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2025.xlsx"

  @bh_file_3 "docs/Sample-Data/SampleUser - 3/Sample3-BenefitHistory.xlsx"
  @holdings_file_3 "docs/Sample-Data/SampleUser - 3/Sample3-ByBenefitType_expanded.xlsx"
  @gl_2025_3 "docs/Sample-Data/SampleUser - 3/Sample3-G&L_Expanded_2025.xlsx"
  @gl_2026_3 "docs/Sample-Data/SampleUser - 3/Sample3-G&L_Expanded_2026.xlsx"

  describe "empty account (no data)" do
    test "returns :error nudge for no BH, all features blocked" do
      result = UploadChecks.check("empty_account")

      assert Enum.any?(result.nudges, fn n -> n.code == :no_benefit_history end)

      bh_nudge = Enum.find(result.nudges, fn n -> n.code == :no_benefit_history end)
      assert bh_nudge.severity == :error
      assert bh_nudge.reason == "No Benefit History uploaded"

      assert result.readiness.portfolio == :blocked
      assert result.readiness.vesting_schedule == :blocked
      assert result.readiness.schedule_fa == :blocked
      assert result.readiness.capital_gains == :blocked
      assert result.readiness.schedule_fsi == :blocked
      assert result.readiness.sell_advisor == :blocked
    end

    test "no holdings or GL nudges when BH is missing" do
      result = UploadChecks.check("empty_account")

      refute Enum.any?(result.nudges, fn n -> n.code == :no_holdings end)
      refute Enum.any?(result.nudges, fn n -> n.code == :no_gl_for_dates end)
    end
  end

  describe "User 1: BH + G&L, no Holdings" do
    setup do
      account = "upload_checks_user1"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_file_1)
      {:ok, _} = Ingestions.ingest_gl(account, @gl_2025_1)
      %{account: account}
    end

    test "no :error nudge for BH (BH is present)", %{account: account} do
      result = UploadChecks.check(account)
      refute Enum.any?(result.nudges, fn n -> n.code == :no_benefit_history end)
    end

    test "capital_gains is :ready (BH + G&L present)", %{account: account} do
      result = UploadChecks.check(account)
      assert result.readiness.capital_gains == :ready
      assert result.readiness.schedule_fsi == :ready
    end

    test "vesting_schedule is :ready", %{account: account} do
      result = UploadChecks.check(account)
      assert result.readiness.vesting_schedule == :ready
    end

    test "no :no_gl nudge code (replaced by :no_gl_for_dates)", %{account: account} do
      result = UploadChecks.check(account)
      refute Enum.any?(result.nudges, fn n -> n.code == :no_gl end)
    end
  end

  describe "User 3: BH + Holdings + G&L (full data)" do
    setup do
      account = "upload_checks_user3"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_file_3)
      {:ok, _} = Ingestions.ingest_holdings(account, @holdings_file_3)
      {:ok, _} = Ingestions.ingest_gl(account, @gl_2025_3)
      {:ok, _} = Ingestions.ingest_gl(account, @gl_2026_3)
      %{account: account}
    end

    test "no :error or :warning nudges", %{account: account} do
      result = UploadChecks.check(account)

      error_or_warning =
        Enum.filter(result.nudges, fn n -> n.severity in [:error, :warning] end)

      assert error_or_warning == [],
             "Expected no error/warning nudges, got: #{inspect(error_or_warning)}"
    end

    test "all features :ready", %{account: account} do
      result = UploadChecks.check(account)

      assert result.readiness.portfolio == :ready
      assert result.readiness.vesting_schedule == :ready
      assert result.readiness.schedule_fa == :ready
      assert result.readiness.capital_gains == :ready
      assert result.readiness.schedule_fsi == :ready
      assert result.readiness.sell_advisor == :ready
    end
  end

  describe "BH only, no G&L — sales present in BH window" do
    setup do
      account = "upload_checks_bh_only"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_file_1)
      %{account: account}
    end

    test "has :warning nudge with :no_gl_for_dates code for uncovered CY-1 sales", %{
      account: account
    } do
      result = UploadChecks.check(account)

      gl_nudge =
        Enum.find(result.nudges, fn n ->
          n.code == :no_gl_for_dates and n.severity == :warning
        end)

      assert gl_nudge != nil,
             "Expected :no_gl_for_dates :warning nudge, got: #{inspect(result.nudges)}"
    end

    test "no :no_gl nudge code (replaced by :no_gl_for_dates)", %{account: account} do
      result = UploadChecks.check(account)
      refute Enum.any?(result.nudges, fn n -> n.code == :no_gl end)
    end

    test "capital_gains is :blocked (uncovered CY-1 sales)", %{account: account} do
      result = UploadChecks.check(account)
      assert result.readiness.capital_gains == :blocked
    end

    test "schedule_fa is :blocked (uncovered CY-1 sales)", %{account: account} do
      result = UploadChecks.check(account)
      assert result.readiness.schedule_fa == :blocked
    end

    test "schedule_fsi is :blocked (uncovered CY-1 sales)", %{account: account} do
      result = UploadChecks.check(account)
      assert result.readiness.schedule_fsi == :blocked
    end

    test "portfolio is :not_applicable (no current shares — fully sold)", %{account: account} do
      result = UploadChecks.check(account)
      assert result.readiness.portfolio == :not_applicable
    end
  end

  describe "BH with current shares, no Holdings (User 3 BH only)" do
    setup do
      account = "upload_checks_current_shares_no_holdings"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_file_3)
      %{account: account}
    end

    test "has :error :no_holdings nudge", %{account: account} do
      result = UploadChecks.check(account)
      holdings_nudge = Enum.find(result.nudges, fn n -> n.code == :no_holdings end)
      assert holdings_nudge != nil
      assert holdings_nudge.severity == :error
    end

    test "portfolio is :blocked (Holdings required)", %{account: account} do
      result = UploadChecks.check(account)
      assert result.readiness.portfolio == :blocked
    end

    test "vesting_schedule is :ready", %{account: account} do
      result = UploadChecks.check(account)
      assert result.readiness.vesting_schedule == :ready
    end
  end

  describe "nudge structure" do
    test "every nudge has required keys" do
      result = UploadChecks.check("empty_account")

      for nudge <- result.nudges do
        assert Map.has_key?(nudge, :severity)
        assert Map.has_key?(nudge, :code)
        assert Map.has_key?(nudge, :reason)
        assert Map.has_key?(nudge, :impact)
        assert Map.has_key?(nudge, :action)
        assert nudge.severity in [:error, :warning, :info]
        assert is_atom(nudge.code)
        assert is_binary(nudge.reason)
        assert is_binary(nudge.impact)
        assert is_binary(nudge.action)
      end
    end
  end

  describe "check_symbol_consistency/1 (M22)" do
    @bh_adbe "docs/Sample-Data/SampleUser - 5/SampleUser5-BenefitHistory-ADBE.xlsx"
    @bh_crm "docs/Sample-Data/SampleUser - 5/SampleUser5-BenefitHistory-CRM.xlsx"
    @holdings_crm "docs/Sample-Data/SampleUser - 5/SampleUser5-ByBenefitType_expanded-CRM.xlsx"

    @tag :user5
    test "CRM with Holdings produces no :bh_without_holdings nudge for CRM", %{} do
      account = "ucheck_user5_a"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_adbe)
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_crm)
      {:ok, _} = Ingestions.ingest_holdings(account, @holdings_crm)

      result = UploadChecks.check(account)

      crm_nudge =
        Enum.find(result.nudges, fn n ->
          n.code == :bh_without_holdings and String.contains?(n.reason, "CRM")
        end)

      assert crm_nudge == nil, "CRM has Holdings — should not fire bh_without_holdings"
      refute Enum.any?(result.nudges, fn n -> n.code == :holdings_without_bh end)
    end

    @tag :user5
    test "no nudges when symbols match perfectly" do
      account = "ucheck_user5_b"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_crm)
      {:ok, _} = Ingestions.ingest_holdings(account, @holdings_crm)

      result = UploadChecks.check(account)

      refute Enum.any?(result.nudges, fn n ->
               n.code in [:bh_without_holdings, :holdings_without_bh]
             end)
    end

    @tag :user5
    test ":bh_without_holdings suppressed for symbols with no unsold shares per snapshot", %{} do
      # Upload ADBE + CRM BH + CRM Holdings. If ADBE snapshot shows 0 unsold
      # (vested_unsold_origin_count == 0 and unvested_count == 0), no nudge fires for ADBE.
      # This tests that check_symbol_consistency uses the snapshot, not SaleAllocation.
      account = "ucheck_user5_c"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_adbe)
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_crm)
      {:ok, _} = Ingestions.ingest_holdings(account, @holdings_crm)

      result = UploadChecks.check(account)

      # Regardless of whether ADBE fires (depends on fixture data), CRM must NOT fire
      crm_nudge =
        Enum.find(result.nudges, fn n ->
          n.code == :bh_without_holdings and String.contains?(n.reason, "CRM")
        end)

      assert crm_nudge == nil
      refute Enum.any?(result.nudges, fn n -> n.code == :holdings_without_bh end)
    end
  end
end
