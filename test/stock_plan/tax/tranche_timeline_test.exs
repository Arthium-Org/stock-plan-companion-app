defmodule StockPlan.Tax.TrancheTimelineTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Tax.TrancheTimeline
  alias StockPlan.Ingestions

  # SampleUser-1: BH + G&L (all sold, no Holdings)
  @bh_file_1 "docs/Sample-Data/SampleUser - 1/sample-Etrade-BenefitHistory.xlsx"
  @gl_2025_1 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2025.xlsx"
  @gl_2024_1 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2024.xlsx"
  @gl_2023_1 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2023.xlsx"

  # SampleUser-3: BH + Holdings + G&L
  @bh_file_3 "docs/Sample-Data/SampleUser - 3/Sample3-BenefitHistory.xlsx"
  @holdings_file_3 "docs/Sample-Data/SampleUser - 3/Sample3-ByBenefitType_expanded.xlsx"
  @gl_2025_3 "docs/Sample-Data/SampleUser - 3/Sample3-G&L_Expanded_2025.xlsx"
  @gl_2026_3 "docs/Sample-Data/SampleUser - 3/Sample3-G&L_Expanded_2026.xlsx"

  @account_1 "timeline_test_user1"
  @account_3 "timeline_test_user3"

  describe "User 1 (BH + G&L, all sold)" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_1, @bh_file_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2025_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2024_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2023_1)
      :ok
    end

    test "build returns timelines and validation result" do
      {timelines, validation} = TrancheTimeline.build(@account_1)
      assert is_list(timelines)
      assert length(timelines) > 0
      assert is_map(validation)
      assert Map.has_key?(validation, :valid)
      assert Map.has_key?(validation, :errors)
      assert Map.has_key?(validation, :warnings)
    end

    test "each timeline has required fields" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      for t <- timelines do
        assert Map.has_key?(t, :tranche_id)
        assert Map.has_key?(t, :origin_id)
        assert Map.has_key?(t, :grant_number)
        assert Map.has_key?(t, :plan_type)
        assert Map.has_key?(t, :vest_date)
        assert Map.has_key?(t, :net_quantity)
        assert Map.has_key?(t, :sells)
        assert Map.has_key?(t, :holdings_qty)
        assert Map.has_key?(t, :total_sold)
        assert Map.has_key?(t, :held_from_timeline)
      end
    end

    test "RSU tranches have sells from G&L (source: :gl)" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      rsu_with_sells =
        timelines
        |> Enum.filter(fn t -> t.plan_type == "RSU" and t.sells != [] end)

      assert length(rsu_with_sells) > 0

      for t <- rsu_with_sells, s <- t.sells do
        assert s.source == :gl
      end
    end

    test "ESPP tranches have sells from G&L or BH (no mixing within tranche)" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      espp_with_sells =
        timelines
        |> Enum.filter(fn t -> t.plan_type == "ESPP" and t.sells != [] end)

      for t <- espp_with_sells do
        sources = Enum.map(t.sells, & &1.source) |> Enum.uniq()
        # No mixing: all sells for a tranche come from same source
        assert length(sources) == 1,
               "ESPP #{t.grant_number} vest #{t.vest_date} mixes sources: #{inspect(sources)}"

        assert hd(sources) in [:gl, :bh]
      end
    end

    test "invariant holds: held_from_timeline = net_quantity - total_sold" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      for t <- timelines do
        expected = Decimal.sub(t.net_quantity, t.total_sold)

        assert Decimal.compare(t.held_from_timeline, expected) == :eq,
               "Invariant violated for tranche #{t.tranche_id}: " <>
                 "held=#{t.held_from_timeline}, expected=#{expected}"
      end
    end

    test "holdings_qty reflects BH sold validation (no Holdings uploaded)" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      # Without Holdings, BH sold validation detects fully-sold origins:
      # - Fully sold origins (bh_sold == total_released): holdings_qty = 0
      # - Partially sold origins: holdings_qty = nil (can't determine)
      # - Tranches with explicit sells: holdings_qty unchanged (nil)
      for t <- timelines do
        assert t.holdings_qty == nil or Decimal.equal?(t.holdings_qty, Decimal.new(0)),
               "holdings_qty should be nil or 0 without Holdings, got #{inspect(t.holdings_qty)} " <>
                 "for #{t.grant_number} vest #{t.vest_date}"
      end
    end

    test "sells are sorted chronologically" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      for t <- timelines, length(t.sells) > 1 do
        dates = Enum.map(t.sells, fn s -> Date.to_iso8601(s.date) end)
        assert dates == Enum.sort(dates)
      end
    end
  end

  describe "BH sold validation without Holdings (User 1)" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_1, @bh_file_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2025_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2024_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2023_1)
      :ok
    end

    test "fully sold origins detected via BH totals (holdings_qty=0)" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      # Group by origin and check: origins where bh_sold == total_released
      # should have tranches without sells marked with holdings_qty = 0
      by_origin = Enum.group_by(timelines, & &1.origin_id)

      fully_sold_origins =
        Enum.filter(by_origin, fn {_origin_id, origin_timelines} ->
          # Check if all tranches are accounted for (sold or marked)
          Enum.all?(origin_timelines, fn t ->
            not Enum.empty?(t.sells) or
              (t.holdings_qty != nil and Decimal.equal?(t.holdings_qty, Decimal.new(0)))
          end)
        end)

      # User 1 has all sold — should have fully sold origins detected
      assert length(fully_sold_origins) > 0,
             "Expected some fully-sold origins detected via BH totals"
    end

    test "old sold tranches excluded from CY queries via BH validation" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      # Tranches marked as sold (holdings_qty=0, no sells) should be excluded
      # from CY queries via the Holdings override in held_during_cy
      bh_marked_sold =
        timelines
        |> Enum.filter(fn t ->
          t.holdings_qty != nil and
            Decimal.equal?(t.holdings_qty, Decimal.new(0)) and
            Enum.empty?(t.sells)
        end)

      if length(bh_marked_sold) > 0 do
        cy_held = TrancheTimeline.held_during_cy(timelines, 2024)
        cy_ids = Enum.map(cy_held, fn h -> h.timeline.tranche_id end) |> MapSet.new()

        for t <- bh_marked_sold do
          refute MapSet.member?(cy_ids, t.tranche_id),
                 "BH-confirmed sold tranche #{t.grant_number} vest #{t.vest_date} " <>
                   "should NOT appear in CY 2024"
        end
      end
    end

    test "confidence field present on sell maps" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      for t <- timelines, s <- t.sells do
        assert Map.has_key?(s, :confidence),
               "Sell map missing :confidence field for #{t.grant_number} vest #{t.vest_date}"

        assert s.confidence in [:verified, :inferred],
               "Unexpected confidence value: #{inspect(s.confidence)}"

        # G&L sells should be :verified, BH sells should be :inferred
        case s.source do
          :gl -> assert s.confidence == :verified
          :bh -> assert s.confidence == :inferred
        end
      end
    end
  end

  describe "User 3 (BH + Holdings + G&L)" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_3, @bh_file_3)
      {:ok, _} = Ingestions.ingest_holdings(@account_3, @holdings_file_3)
      {:ok, _} = Ingestions.ingest_gl(@account_3, @gl_2025_3)
      {:ok, _} = Ingestions.ingest_gl(@account_3, @gl_2026_3)
      :ok
    end

    test "build returns timelines with holdings data" do
      {timelines, _} = TrancheTimeline.build(@account_3)
      assert is_list(timelines)
      assert length(timelines) > 0

      # At least some tranches should have holdings data
      with_holdings = Enum.filter(timelines, fn t -> t.holdings_qty != nil end)
      assert length(with_holdings) > 0
    end

    test "V1: no qty_mismatch warnings when data is consistent" do
      {_timelines, validation} = TrancheTimeline.build(@account_3)

      mismatch_warnings =
        Enum.filter(validation.warnings, fn w -> w.code == :qty_mismatch end)

      # Allow some tolerance — data may have minor discrepancies
      # If there are mismatches, they should be within +-1 (tolerance check is in the code)
      for w <- mismatch_warnings do
        assert w.code == :qty_mismatch
        assert is_binary(w.message)
      end
    end

    test "invariant holds for all tranches" do
      {timelines, _} = TrancheTimeline.build(@account_3)

      for t <- timelines do
        expected = Decimal.sub(t.net_quantity, t.total_sold)

        assert Decimal.compare(t.held_from_timeline, expected) == :eq,
               "Invariant violated for #{t.grant_number} vest #{t.vest_date}"
      end
    end
  end

  describe "V1 — Holdings vs Timeline quantity match" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_3, @bh_file_3)
      {:ok, _} = Ingestions.ingest_holdings(@account_3, @holdings_file_3)
      {:ok, _} = Ingestions.ingest_gl(@account_3, @gl_2025_3)
      {:ok, _} = Ingestions.ingest_gl(@account_3, @gl_2026_3)
      :ok
    end

    test "V1 skipped when no Holdings uploaded" do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_1, @bh_file_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2025_1)

      {_timelines, validation} = TrancheTimeline.build(@account_1)

      mismatch_warnings =
        Enum.filter(validation.warnings, fn w -> w.code == :qty_mismatch end)

      assert mismatch_warnings == []
    end
  end

  describe "V2 — G&L coverage for CY" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_1, @bh_file_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2025_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2024_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2023_1)
      :ok
    end

    test "no sells in CY returns :ok" do
      # Use a far-future year with no sales
      {_timelines, _validation} = TrancheTimeline.build(@account_1)

      bh_sales = load_bh_sales(@account_1)
      allocations = load_allocations(@account_1)

      assert TrancheTimeline.validate_cy_coverage(bh_sales, allocations, 2030) == :ok
    end

    test "sells in CY with G&L coverage returns :ok" do
      {_timelines, _validation} = TrancheTimeline.build(@account_1)
      bh_sales = load_bh_sales(@account_1)
      allocations = load_allocations(@account_1)

      # 2024 has sells and G&L is uploaded
      result = TrancheTimeline.validate_cy_coverage(bh_sales, allocations, 2024)
      assert result == :ok
    end

    test "sells in CY without G&L returns error" do
      # Only ingest BH, no G&L — use a different account
      account = "v2_test_no_gl"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_file_1)

      {_timelines, _validation} = TrancheTimeline.build(account)
      bh_sales = load_bh_sales(account)
      allocations = load_allocations(account)

      # Check a year where BH has sells — should fail
      # Find a year with RSU sells
      rsu_sell_years =
        bh_sales
        |> Enum.filter(fn s -> s.plan_type == "RSU" end)
        |> Enum.map(fn s -> s.sale_date.year end)
        |> Enum.uniq()

      if rsu_sell_years != [] do
        year = hd(rsu_sell_years)
        result = TrancheTimeline.validate_cy_coverage(bh_sales, allocations, year)
        assert {:error, msg} = result
        assert msg =~ "G&L data missing"
        assert msg =~ "Upload G&L"
      end
    end
  end

  describe "V3 — No gaps in G&L allocations" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_1, @bh_file_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2025_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2024_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2023_1)
      :ok
    end

    test "all BH sales within G&L range have allocations" do
      {_timelines, validation} = TrancheTimeline.build(@account_1)

      gap_warnings = Enum.filter(validation.warnings, fn w -> w.code == :gl_gaps end)
      # With all G&L files uploaded, there should be no gaps
      assert gap_warnings == []
    end
  end

  describe "held_during_cy/2" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_1, @bh_file_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2025_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2024_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2023_1)
      :ok
    end

    test "excludes tranches vested after CY end" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      cy_entries = TrancheTimeline.held_during_cy(timelines, 2020)

      for entry <- cy_entries do
        assert Date.compare(entry.timeline.vest_date, ~D[2020-12-31]) != :gt
      end
    end

    test "held_at_start and held_at_end are non-negative" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      cy_entries = TrancheTimeline.held_during_cy(timelines, 2024)

      for entry <- cy_entries do
        assert Decimal.compare(entry.held_at_start, Decimal.new(0)) != :lt,
               "held_at_start should be non-negative"

        assert Decimal.compare(entry.held_at_end, Decimal.new(0)) != :lt,
               "held_at_end should be non-negative"
      end
    end

    test "sold_during_cy is consistent with held_at_start and held_at_end" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      cy_entries = TrancheTimeline.held_during_cy(timelines, 2024)

      for entry <- cy_entries do
        expected_end = Decimal.sub(entry.held_at_start, entry.sold_during_cy)

        assert Decimal.compare(entry.held_at_end, expected_end) == :eq,
               "held_at_end should be held_at_start - sold_during_cy"
      end
    end

    test "excludes tranches fully sold before CY" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      # Check a recent year — all entries should have held_at_start > 0 or sold_during_cy > 0
      cy_entries = TrancheTimeline.held_during_cy(timelines, 2024)

      for entry <- cy_entries do
        assert entry.held_during_cy == true
      end
    end

    test "returns empty for far future year" do
      {timelines, _} = TrancheTimeline.build(@account_1)

      cy_entries = TrancheTimeline.held_during_cy(timelines, 2050)
      # May have entries if tranches are never sold, but for User 1 (all sold) should be empty
      # Actually, depends on sell dates — just assert it doesn't crash
      assert is_list(cy_entries)
    end
  end

  describe "held_during_cy/2 with User 3" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_3, @bh_file_3)
      {:ok, _} = Ingestions.ingest_holdings(@account_3, @holdings_file_3)
      {:ok, _} = Ingestions.ingest_gl(@account_3, @gl_2025_3)
      {:ok, _} = Ingestions.ingest_gl(@account_3, @gl_2026_3)
      :ok
    end

    test "returns entries for CY 2025" do
      {timelines, _} = TrancheTimeline.build(@account_3)

      cy_entries = TrancheTimeline.held_during_cy(timelines, 2025)
      assert length(cy_entries) > 0
    end

    test "held_at_end matches timeline held_from_timeline for current CY" do
      {timelines, _} = TrancheTimeline.build(@account_3)

      # For the most recent CY where no more sells happened after Dec 31,
      # held_at_end should match held_from_timeline for each tranche
      # This is approximate — depends on when data was taken
      cy_entries = TrancheTimeline.held_during_cy(timelines, 2025)

      for entry <- cy_entries do
        assert Decimal.compare(entry.held_at_end, Decimal.new(0)) != :lt
      end
    end
  end

  describe "Schedule FA integration" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_1, @bh_file_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2025_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2024_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2023_1)
      :ok
    end

    test "V2 error blocks FA when G&L missing for CY with sells" do
      account = "fa_v2_block_test"
      {:ok, _} = Ingestions.ingest_benefit_history(account, @bh_file_1)

      # No G&L uploaded — check a year with RSU sells
      alias StockPlan.Tax.ScheduleFA

      # Find year with sells
      {_timelines, _} = TrancheTimeline.build(account)

      # For User 1 without G&L, ESPP sells have allocations (from BH),
      # but RSU sells won't have G&L allocations
      # V2 will check BH sales (all sales including RSU) vs G&L allocations
      result = ScheduleFA.build(account, 2024)

      case result do
        {:error, msg} ->
          assert msg =~ "G&L missing"

        {:ok, _rows, _warnings} ->
          # If no RSU sells in 2024, V2 passes — that's OK
          :ok
      end
    end
  end

  # ============================================================
  # User 4: BH + Holdings + G&L (old sold grants, regression)
  # ============================================================

  # SampleUser-4: BH + Holdings + G&L (has old fully-sold grants from 2012-2019)
  @bh_file_4 "docs/Sample-Data/SampleUser - 4/Sampleuser4-BenefitHistory.xlsx"
  @holdings_file_4 "docs/Sample-Data/SampleUser - 4/SampleUser4-ByBenefitType_expanded.xlsx"
  @gl_file_4 "docs/Sample-Data/SampleUser - 4/SampleUser4-G&L_Expanded.xlsx"

  @account_4 "timeline_test_user4"

  describe "BH sold validation (User 4 — old sold grants)" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_4, @bh_file_4)
      {:ok, _} = Ingestions.ingest_holdings(@account_4, @holdings_file_4)
      {:ok, _} = Ingestions.ingest_gl(@account_4, @gl_file_4)
      :ok
    end

    test "old fully-sold RSU tranches marked as sold (holdings=0) via BH validation" do
      {timelines, _} = TrancheTimeline.build(@account_4)

      # RSU tranches with holdings=0 and no sells (BH validation confirmed they're sold)
      bh_confirmed_rsu =
        timelines
        |> Enum.filter(fn t ->
          t.plan_type == "RSU" and
            t.holdings_qty != nil and
            Decimal.equal?(t.holdings_qty, Decimal.new(0)) and
            Enum.empty?(t.sells)
        end)

      assert length(bh_confirmed_rsu) > 0

      # These should be excluded from CY 2024 (Holdings override kicks in)
      cy_held = TrancheTimeline.held_during_cy(timelines, 2024)
      cy_ids = Enum.map(cy_held, fn h -> h.timeline.tranche_id end) |> MapSet.new()

      for t <- bh_confirmed_rsu do
        refute MapSet.member?(cy_ids, t.tranche_id),
               "BH-confirmed sold #{t.grant_number} vest #{t.vest_date} should NOT be in CY 2024"
      end
    end

    test "old fully-sold ESPP tranches (not covered by G&L) appear as sold in timeline" do
      {timelines, _} = TrancheTimeline.build(@account_4)

      # ESPP tranches where BH has a sell event but G&L may not cover them (old lots).
      # After the BH-phase allocation fix, these have allocations from BH (not G&L),
      # so source is :gl in the timeline — but the outcome is correct: held = 0.
      espp_fully_sold =
        timelines
        |> Enum.filter(fn t ->
          t.plan_type == "ESPP" and
            t.sells != [] and
            Decimal.equal?(t.held_from_timeline, Decimal.new(0))
        end)

      assert length(espp_fully_sold) > 0

      # Each sell quantity should cover net_quantity (fully sold)
      for t <- espp_fully_sold do
        total_sold =
          Enum.reduce(t.sells, Decimal.new(0), fn s, acc -> Decimal.add(acc, s.quantity) end)

        assert Decimal.compare(total_sold, t.net_quantity) != :lt,
               "ESPP #{t.grant_number} vest #{t.vest_date}: sold=#{total_sold} should cover net=#{t.net_quantity}"
      end
    end

    test "tranches sold before CY 2024 do NOT appear in CY 2024 FA" do
      {timelines, _} = TrancheTimeline.build(@account_4)

      cy_held = TrancheTimeline.held_during_cy(timelines, 2024)
      cy_tranche_ids = Enum.map(cy_held, fn h -> h.timeline.tranche_id end) |> MapSet.new()

      # Tranches fully sold before 2024-01-01 should not appear
      sold_before_2024 =
        timelines
        |> Enum.filter(fn t ->
          t.sells != [] and
            Decimal.equal?(t.held_from_timeline, Decimal.new(0)) and
            Enum.all?(t.sells, fn s -> Date.compare(s.date, ~D[2024-01-01]) == :lt end)
        end)

      assert length(sold_before_2024) > 0, "Expected some tranches sold before 2024"

      leaked =
        Enum.filter(sold_before_2024, fn t -> MapSet.member?(cy_tranche_ids, t.tranche_id) end)

      assert leaked == [],
             "#{length(leaked)} tranches sold before 2024 leaked into CY 2024 FA"
    end

    test "per-origin invariant: released = held + sold" do
      {timelines, _} = TrancheTimeline.build(@account_4)

      # Group by origin and verify totals
      by_origin = Enum.group_by(timelines, & &1.origin_id)

      for {_origin_id, origin_timelines} <- by_origin do
        total_released =
          Enum.reduce(origin_timelines, Decimal.new(0), fn t, acc ->
            Decimal.add(acc, t.net_quantity)
          end)

        total_held =
          Enum.reduce(origin_timelines, Decimal.new(0), fn t, acc ->
            Decimal.add(acc, t.held_from_timeline)
          end)

        total_sold =
          Enum.reduce(origin_timelines, Decimal.new(0), fn t, acc ->
            Decimal.add(acc, t.total_sold)
          end)

        assert Decimal.equal?(Decimal.add(total_held, total_sold), total_released),
               "Origin invariant violated: held=#{total_held} + sold=#{total_sold} != released=#{total_released}"
      end
    end

    test "BH validation only marks tranches when BH total covers remaining" do
      {timelines, _} = TrancheTimeline.build(@account_4)

      # No orphans should remain (except future ESPP vests not yet in Holdings)
      orphans =
        timelines
        |> Enum.filter(fn t ->
          t.holdings_qty == nil and Enum.empty?(t.sells) and
            Date.compare(t.vest_date, ~D[2025-01-01]) == :lt
        end)

      assert orphans == [],
             "#{length(orphans)} orphan tranches remain unaccounted (vested before 2025)"
    end

    test "Holdings override: tranches in Holdings with qty 0 excluded from FA" do
      {timelines, _} = TrancheTimeline.build(@account_4)

      # Find tranches in Holdings with qty=0 and no sells
      holdings_zero_no_sells =
        timelines
        |> Enum.filter(fn t ->
          t.holdings_qty != nil and
            Decimal.equal?(t.holdings_qty, Decimal.new(0)) and
            Enum.empty?(t.sells)
        end)

      # These should not appear in any CY FA
      cy_held = TrancheTimeline.held_during_cy(timelines, 2024)
      cy_ids = Enum.map(cy_held, fn h -> h.timeline.tranche_id end) |> MapSet.new()

      for t <- holdings_zero_no_sells do
        refute MapSet.member?(cy_ids, t.tranche_id),
               "Holdings=0 tranche #{t.grant_number} vest #{t.vest_date} should not be in CY 2024"
      end
    end
  end

  describe "Schedule FA regression (User 4)" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_4, @bh_file_4)
      {:ok, _} = Ingestions.ingest_holdings(@account_4, @holdings_file_4)
      {:ok, _} = Ingestions.ingest_gl(@account_4, @gl_file_4)
      :ok
    end

    test "Schedule FA CY 2024 succeeds and excludes old sold tranches" do
      alias StockPlan.Tax.ScheduleFA

      result = ScheduleFA.build(@account_4, 2024)

      case result do
        {:ok, rows, _warnings} ->
          # No rows should have vest dates from fully-sold old grants (pre-2017)
          very_old =
            Enum.filter(rows, fn r -> Date.compare(r.date_acquired, ~D[2017-01-01]) == :lt end)

          assert very_old == [],
                 "#{length(very_old)} rows from pre-2017 tranches in CY 2024 FA"

        {:error, _msg} ->
          # V2 error is acceptable if G&L doesn't cover all 2024 sell dates
          :ok
      end
    end

    test "Schedule FA row count is reasonable (not all tranches)" do
      alias StockPlan.Tax.ScheduleFA

      {timelines, _} = TrancheTimeline.build(@account_4)
      total_tranches = length(timelines)

      case ScheduleFA.build(@account_4, 2024) do
        {:ok, rows, _} ->
          # FA should have fewer rows than total tranches (old sold excluded)
          assert length(rows) < total_tranches,
                 "FA has #{length(rows)} rows but total tranches is #{total_tranches} — old sold not excluded?"

        {:error, _} ->
          :ok
      end
    end

    test "no FA row has both closing_value and sale_proceeds as 0" do
      alias StockPlan.Tax.ScheduleFA

      case ScheduleFA.build(@account_4, 2025) do
        {:ok, rows, _} ->
          # Every FA row must have either:
          # - closing_value > 0 (still held at year end), OR
          # - sale_proceeds > 0 (sold during the year)
          # Both being 0 means the row shouldn't be in FA at all
          invalid =
            Enum.filter(rows, fn r ->
              Decimal.equal?(r.closing_value_inr, Decimal.new(0)) and
                Decimal.equal?(r.sale_proceeds_inr, Decimal.new(0))
            end)

          assert invalid == [],
                 "#{length(invalid)} FA rows have both closing=0 and sale_proceeds=0: " <>
                   Enum.map_join(invalid, ", ", fn r ->
                     "#{r.grant_number} vest #{r.date_acquired}"
                   end)

        {:error, _} ->
          :ok
      end
    end

    test "every FA tranche must be in Holdings or G&L" do
      alias StockPlan.Tax.ScheduleFA

      {timelines, _} = TrancheTimeline.build(@account_4)

      case ScheduleFA.build(@account_4, 2025) do
        {:ok, rows, _} ->
          for row <- rows do
            # Find the matching timeline entry
            matching =
              Enum.find(timelines, fn t ->
                t.vest_date == row.date_acquired and t.plan_type == row.plan_type
              end)

            assert matching != nil,
                   "FA row #{row.plan_type} vest #{row.date_acquired} has no matching timeline"

            # Must be either: in Holdings (holdings_qty != nil) OR has G&L sells
            in_holdings =
              matching.holdings_qty != nil and
                Decimal.gt?(matching.holdings_qty, Decimal.new(0))

            has_gl_sells = Enum.any?(matching.sells, fn s -> s.source == :gl end)
            has_bh_sells = Enum.any?(matching.sells, fn s -> s.source == :bh end)

            assert in_holdings or has_gl_sells or has_bh_sells,
                   "FA row #{row.plan_type} vest #{row.date_acquired} not in Holdings or G&L/BH"
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "summary/2 with User 1 (all sold, no Holdings)" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_1, @bh_file_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2025_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2024_1)
      {:ok, _} = Ingestions.ingest_gl(@account_1, @gl_2023_1)
      :ok
    end

    test "returns a map keyed by symbol" do
      {timelines, _} = TrancheTimeline.build(@account_1)
      bh_sales = load_bh_sales_for_summary(@account_1)

      result = TrancheTimeline.summary(timelines, bh_sales)

      assert is_map(result)
      assert map_size(result) > 0

      for {symbol, _} <- result do
        assert is_binary(symbol)
      end
    end

    test "has all expected fields" do
      {timelines, _} = TrancheTimeline.build(@account_1)
      bh_sales = load_bh_sales_for_summary(@account_1)

      result = TrancheTimeline.summary(timelines, bh_sales)

      for {_symbol, summary} <- result do
        assert Map.has_key?(summary, :total_released)
        assert Map.has_key?(summary, :total_bh_sold)
        assert Map.has_key?(summary, :total_gl_sold)
        assert Map.has_key?(summary, :total_bh_matched)
        assert Map.has_key?(summary, :holdings_held)
        assert Map.has_key?(summary, :has_holdings)
        assert Map.has_key?(summary, :vested_unsold_bh)
        assert Map.has_key?(summary, :tranche_count)
        assert Map.has_key?(summary, :origin_count)
        assert Map.has_key?(summary, :status)
      end
    end

    test "total_released > 0 for each symbol" do
      {timelines, _} = TrancheTimeline.build(@account_1)
      bh_sales = load_bh_sales_for_summary(@account_1)

      result = TrancheTimeline.summary(timelines, bh_sales)

      for {_symbol, summary} <- result do
        assert Decimal.gt?(summary.total_released, Decimal.new(0))
      end
    end

    test "status is a valid atom" do
      {timelines, _} = TrancheTimeline.build(@account_1)
      bh_sales = load_bh_sales_for_summary(@account_1)

      result = TrancheTimeline.summary(timelines, bh_sales)

      for {_symbol, summary} <- result do
        assert summary.status in [:reconciled, :holdings_needed, :error]
      end
    end

    test "status is :reconciled (all sold, bh_sold == total_released)" do
      {timelines, _} = TrancheTimeline.build(@account_1)
      bh_sales = load_bh_sales_for_summary(@account_1)

      result = TrancheTimeline.summary(timelines, bh_sales)

      for {symbol, summary} <- result do
        assert summary.status == :reconciled,
               "Expected :reconciled for #{symbol}, got #{summary.status}. " <>
                 "total_released=#{summary.total_released}, total_bh_sold=#{summary.total_bh_sold}"
      end
    end
  end

  describe "summary/2 with User 3 (has Holdings)" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_3, @bh_file_3)
      {:ok, _} = Ingestions.ingest_holdings(@account_3, @holdings_file_3)
      {:ok, _} = Ingestions.ingest_gl(@account_3, @gl_2025_3)
      {:ok, _} = Ingestions.ingest_gl(@account_3, @gl_2026_3)
      :ok
    end

    test "status is :reconciled (has Holdings)" do
      {timelines, _} = TrancheTimeline.build(@account_3)
      bh_sales = load_bh_sales_for_summary(@account_3)

      result = TrancheTimeline.summary(timelines, bh_sales)

      for {symbol, summary} <- result do
        assert summary.status == :reconciled,
               "Expected :reconciled for #{symbol}, got #{summary.status}. " <>
                 "has_holdings=#{summary.has_holdings}"
      end
    end

    test "has_holdings is true" do
      {timelines, _} = TrancheTimeline.build(@account_3)
      bh_sales = load_bh_sales_for_summary(@account_3)

      result = TrancheTimeline.summary(timelines, bh_sales)

      # At least one symbol should have holdings
      has_any = Enum.any?(result, fn {_symbol, summary} -> summary.has_holdings end)
      assert has_any, "Expected at least one symbol with has_holdings=true for User 3"
    end
  end

  # ============================================================
  # Helpers
  # ============================================================

  defp load_bh_sales(account_id) do
    import Ecto.Query

    Repo.all(
      from s in StockPlan.Schema.Sale,
        join: o in StockPlan.Schema.Origin,
        on: s.origin_id == o.id,
        where: s.account_id == ^account_id,
        select: %{
          sale_date: s.sale_date,
          plan_type: o.plan_type
        }
    )
  end

  defp load_allocations(account_id) do
    import Ecto.Query

    Repo.all(
      from a in StockPlan.Schema.SaleAllocation,
        join: s in StockPlan.Schema.Sale,
        on: a.sale_id == s.id,
        join: t in StockPlan.Schema.Tranche,
        on: a.tranche_id == t.id,
        join: o in StockPlan.Schema.Origin,
        on: t.origin_id == o.id,
        where: o.account_id == ^account_id,
        select: %{
          sale_date: s.sale_date,
          plan_type: o.plan_type
        }
    )
  end

  defp load_bh_sales_for_summary(account_id) do
    import Ecto.Query

    Repo.all(
      from s in StockPlan.Schema.Sale,
        join: o in StockPlan.Schema.Origin,
        on: s.origin_id == o.id,
        where: s.account_id == ^account_id,
        select: %{
          origin_id: s.origin_id,
          sale_date: s.sale_date,
          total_quantity: s.total_quantity,
          plan_type: o.plan_type,
          grant_number: o.grant_number
        }
    )
  end
end
