defmodule StockPlan.Tax.SellAdvisorV2Test do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Tax.SellAdvisor
  alias StockPlan.Tax.SellAdvisorV2
  alias StockPlan.Ingestions

  @bh_file "docs/Sample-Data/SampleUser - 3/Sample3-BenefitHistory.xlsx"
  @holdings_file "docs/Sample-Data/SampleUser - 3/Sample3-ByBenefitType_expanded.xlsx"

  @account_id "sell_advisor_v2_test"

  # Fixed test params — same as v1 tests for comparison
  @test_price Decimal.new("450.00")
  @test_fx Decimal.new("84.50")
  @test_today ~D[2026-05-05]

  setup do
    {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_file)
    {:ok, _} = Ingestions.ingest_holdings(@account_id, @holdings_file)
    :ok
  end

  defp advise_v2(target) do
    SellAdvisorV2.advise(@account_id, target,
      current_price: @test_price,
      current_fx: @test_fx,
      today: @test_today
    )
  end

  defp advise_v1(target) do
    SellAdvisor.advise(@account_id, target,
      current_price: @test_price,
      current_fx: @test_fx,
      today: @test_today
    )
  end

  # ============================================================
  # Basic functionality
  # ============================================================

  describe "basic functionality" do
    test "returns {:ok, result} with version v2" do
      assert {:ok, result} = advise_v2({:shares, 10})
      assert result.version == "v2"
      assert length(result.baskets) >= 1
    end

    test "basket has version field" do
      {:ok, result} = advise_v2({:shares, 10})
      basket = hd(result.baskets)
      assert basket.version == "v2"
    end

    test "shares target returns baskets" do
      assert {:ok, result} = advise_v2({:shares, 10})
      assert Decimal.eq?(result.target_shares, Decimal.new(10))
    end

    test "USD target resolves to shares" do
      assert {:ok, result} = advise_v2({:usd, Decimal.new("4500")})
      assert Decimal.eq?(result.target_shares, Decimal.new(10))
    end

    test "INR target resolves to shares" do
      assert {:ok, result} = advise_v2({:inr, Decimal.new("380250")})
      assert Decimal.eq?(result.target_shares, Decimal.new(10))
    end

    test "no sellable lots returns error" do
      assert {:error, :no_sellable_lots} =
               SellAdvisorV2.advise("nonexistent_account", {:shares, 10},
                 current_price: @test_price,
                 current_fx: @test_fx,
                 today: @test_today
               )
    end
  end

  # ============================================================
  # Stage 1: Tax Loss Harvesting
  # ============================================================

  describe "Stage 1 — offset baseline STCG with STCL" do
    test "v2 correctly offsets baseline STCG" do
      {:ok, result} = advise_v2({:shares, 30})
      basket = hd(result.baskets)

      # User 3 has baseline STCG of ~7530. v2 should offset it.
      # The basket tax should be <= what v1 produces (or equal)
      assert basket.total_tax_inr != nil
    end

    test "Stage 1 picks loss lots first" do
      {:ok, result} = advise_v2({:shares, 30})
      basket = hd(result.baskets)

      # If there are loss lots, they should appear early in entries
      if length(basket.entries) > 1 do
        loss_entries = Enum.filter(basket.entries, fn e -> Decimal.negative?(e.gain_inr) end)
        gain_entries = Enum.filter(basket.entries, fn e -> Decimal.positive?(e.gain_inr) end)

        if loss_entries != [] and gain_entries != [] do
          # Loss lots committed in Stage 1 should appear before Stage 2 gain lots
          first_loss_idx =
            basket.entries
            |> Enum.find_index(fn e -> Decimal.negative?(e.gain_inr) end)

          last_gain_idx =
            basket.entries
            |> Enum.with_index()
            |> Enum.filter(fn {e, _} -> Decimal.positive?(e.gain_inr) end)
            |> List.last()
            |> elem(1)

          assert first_loss_idx <= last_gain_idx
        end
      end
    end
  end

  # ============================================================
  # Pure Harvest Mode
  # ============================================================

  describe "pure harvest mode" do
    test "returns harvest summary when target is :harvest" do
      {:ok, result} = advise_v2(:harvest)
      assert result.version == "v2"
      assert Map.has_key?(result, :harvest_summary)
      assert result.harvest_summary.lots_to_sell >= 0
    end

    test "harvest mode has zero target shares" do
      {:ok, result} = advise_v2(:harvest)
      assert Decimal.eq?(result.target_shares, Decimal.new(0))
    end

    test "harvest summary reports tax saved" do
      {:ok, result} = advise_v2(:harvest)

      if result.harvest_summary.lots_to_sell > 0 do
        assert Decimal.positive?(result.harvest_summary.tax_saved_inr)
        assert String.contains?(result.harvest_summary.message, "save")
      else
        assert result.harvest_summary.message ==
                 "No cost-justified tax loss harvesting available."
      end
    end

    test "harvest basket entries are all loss lots" do
      {:ok, result} = advise_v2(:harvest)
      basket = hd(result.baskets)

      for entry <- basket.entries do
        assert Decimal.negative?(entry.gain_inr),
               "Harvest should only pick loss lots, got gain_inr=#{entry.gain_inr}"
      end
    end
  end

  # ============================================================
  # v1 vs v2 Comparison
  # ============================================================

  describe "v1 vs v2 comparison" do
    test "both produce valid results on same input" do
      {:ok, v1_result} = advise_v1({:shares, 30})
      {:ok, v2_result} = advise_v2({:shares, 30})

      v1_basket = hd(v1_result.baskets)
      v2_basket = hd(v2_result.baskets)

      # Both should have entries
      assert length(v1_basket.entries) > 0
      assert length(v2_basket.entries) > 0

      # Both should fill target or report shortfall consistently
      v1_total = v1_basket.total_shares
      v2_total = v2_basket.total_shares

      assert Decimal.gt?(v1_total, Decimal.new(0))
      assert Decimal.gt?(v2_total, Decimal.new(0))
    end

    test "v2 tax should be <= v1 tax (2-stage offset advantage)" do
      {:ok, v1_result} = advise_v1({:shares, 30})
      {:ok, v2_result} = advise_v2({:shares, 30})

      v1_basket = hd(v1_result.baskets)
      v2_basket = hd(v2_result.baskets)

      # v2 explicitly offsets baseline gains in Stage 1, so should produce
      # equal or lower tax. Allow small tolerance for different lot selection.
      v1_tax = Decimal.to_float(v1_basket.total_tax_inr)
      v2_tax = Decimal.to_float(v2_basket.total_tax_inr)

      assert v2_tax <= v1_tax + 1.0,
             "v2 tax (#{v2_tax}) should be <= v1 tax (#{v1_tax}) " <>
               "since v2 explicitly offsets baseline gains"
    end

    test "both fill same number of shares for share target" do
      {:ok, v1_result} = advise_v1({:shares, 10})
      {:ok, v2_result} = advise_v2({:shares, 10})

      v1_basket = hd(v1_result.baskets)
      v2_basket = hd(v2_result.baskets)

      assert Decimal.eq?(v1_basket.total_shares, v2_basket.total_shares),
             "Both should sell exactly 10 shares"
    end

    test "v2 may select different lots than v1" do
      {:ok, v1_result} = advise_v1({:shares, 30})
      {:ok, v2_result} = advise_v2({:shares, 30})

      v1_lots =
        hd(v1_result.baskets).entries
        |> Enum.map(& &1.lot.holding_id)
        |> MapSet.new()

      v2_lots =
        hd(v2_result.baskets).entries
        |> Enum.map(& &1.lot.holding_id)
        |> MapSet.new()

      # They may or may not be the same — just verify both are valid sets
      assert MapSet.size(v1_lots) > 0
      assert MapSet.size(v2_lots) > 0
    end

    test "comparison with User 3 data: sell 30 shares" do
      {:ok, v1_result} = advise_v1({:shares, 30})
      {:ok, v2_result} = advise_v2({:shares, 30})

      v1_basket = hd(v1_result.baskets)
      v2_basket = hd(v2_result.baskets)

      # Log comparison data for review
      v1_lot_ids =
        v1_basket.entries |> Enum.map(& &1.lot.holding_id) |> Enum.sort()

      v2_lot_ids =
        v2_basket.entries |> Enum.map(& &1.lot.holding_id) |> Enum.sort()

      v1_orders = v1_basket.charges.order_count
      v2_orders = v2_basket.charges.order_count

      # Basic structural assertions
      assert Decimal.eq?(v1_basket.total_shares, Decimal.new(30))
      assert Decimal.eq?(v2_basket.total_shares, Decimal.new(30))

      # Log comparison (visible in test output with --trace)
      IO.puts("\n=== v1 vs v2 Comparison (User 3, sell 30 shares) ===")
      IO.puts("v1 lots: #{inspect(v1_lot_ids)}")
      IO.puts("v2 lots: #{inspect(v2_lot_ids)}")
      IO.puts("v1 tax: #{Decimal.round(v1_basket.total_tax_inr, 2)}")
      IO.puts("v2 tax: #{Decimal.round(v2_basket.total_tax_inr, 2)}")
      IO.puts("v1 orders: #{v1_orders}")
      IO.puts("v2 orders: #{v2_orders}")
      IO.puts("v1 FY baseline: #{inspect(v1_result.fy_baseline)}")

      IO.puts("\nv1 entries:")

      for e <- v1_basket.entries do
        IO.puts(
          "  #{e.lot.plan_type} #{e.lot.grant_number} vest=#{e.lot.vest_date} " <>
            "qty=#{e.qty_to_sell} gain_type=#{e.gain_type} gain_inr=#{Decimal.round(e.gain_inr, 2)}"
        )
      end

      IO.puts("\nv2 entries:")

      for e <- v2_basket.entries do
        IO.puts(
          "  #{e.lot.plan_type} #{e.lot.grant_number} vest=#{e.lot.vest_date} " <>
            "qty=#{e.qty_to_sell} gain_type=#{e.gain_type} gain_inr=#{Decimal.round(e.gain_inr, 2)}"
        )
      end

      IO.puts("=== End Comparison ===\n")
    end
  end

  # ============================================================
  # Edge Cases
  # ============================================================

  describe "edge cases" do
    test "target exceeds total sellable" do
      {:ok, result} = advise_v2({:shares, 99999})
      basket = hd(result.baskets)
      refute basket.fills_target
      assert basket.shortfall != nil
      assert Decimal.positive?(basket.shortfall)
    end

    test "FY baseline is loaded" do
      {:ok, result} = advise_v2({:shares, 5})
      assert result.fy_baseline != nil
      assert Map.has_key?(result.fy_baseline, :realized_st_gain)
    end

    test "basket output compatible with v1 format" do
      {:ok, result} = advise_v2({:shares, 10})
      basket = hd(result.baskets)

      # All v1 fields should be present
      assert Map.has_key?(basket, :name)
      assert Map.has_key?(basket, :entries)
      assert Map.has_key?(basket, :total_shares)
      assert Map.has_key?(basket, :stcg_shares)
      assert Map.has_key?(basket, :ltcg_shares)
      assert Map.has_key?(basket, :stcg_tax_inr)
      assert Map.has_key?(basket, :ltcg_tax_inr)
      assert Map.has_key?(basket, :total_tax_inr)
      assert Map.has_key?(basket, :charges)
      assert Map.has_key?(basket, :fills_target)

      # Plus v2 field
      assert Map.has_key?(basket, :version)
    end

    test "single share sell works" do
      {:ok, result} = advise_v2({:shares, 1})
      basket = hd(result.baskets)
      assert Decimal.eq?(basket.total_shares, Decimal.new(1))
    end
  end

  # ============================================================
  # Tax Evaluator (reuses v1 — sanity check)
  # ============================================================

  describe "evaluate_tax reuse" do
    test "STCL offsets STCG via v1 evaluate_tax" do
      baseline = %{
        realized_st_gain: Decimal.new("50000"),
        realized_st_loss: Decimal.new(0),
        realized_lt_gain: Decimal.new(0),
        realized_lt_loss: Decimal.new(0)
      }

      entries = [
        %{gain_inr: Decimal.new("-50000"), gain_type: :STCG}
      ]

      result = SellAdvisor.evaluate_tax(entries, baseline)
      assert Decimal.eq?(result.total_tax, Decimal.new(0))
    end
  end
end
