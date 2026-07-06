defmodule StockPlan.PortfolioTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Portfolio
  alias StockPlan.Ingestions
  alias StockPlan.Ingestion.{HoldingsParser, BronzeWriter, HoldingsSilverBuilder}
  alias StockPlan.TestFixtures

  @bh_user1 "test/fixtures/sample-data/su1/sample-Etrade-BenefitHistory.xlsx"
  @gl_user1 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2025.xlsx"
  @holdings_user3 "test/fixtures/sample-data/su3/Sample3-ByBenefitType_expanded.xlsx"

  defp setup_bh_user1 do
    {:ok, _} = Ingestions.ingest_benefit_history("user1_port", @bh_user1)
    {:ok, _} = Ingestions.ingest_gl("user1_port", @gl_user1)
  end

  defp setup_holdings_user3 do
    ing =
      TestFixtures.create_holdings_ingestion(%{
        account_id: "user3_port",
        file_name: "Sample3-ByBenefitType.xlsx",
        file_hash: "sha_" <> StockPlan.ID.generate()
      })

    {:ok, rows, _} = HoldingsParser.parse(@holdings_user3)
    {:ok, _} = BronzeWriter.write(ing.ingestion_id, rows)
    {:ok, _} = HoldingsSilverBuilder.build("user3_port")
  end

  describe "build/1 — Holdings Silver source" do
    setup do
      setup_holdings_user3()
      :ok
    end

    test "returns map with ESPP and RSU keys" do
      result = Portfolio.build("user3_port")
      assert is_map(result)
      assert Map.has_key?(result, "ESPP")
      assert Map.has_key?(result, "RSU")
    end

    test "RSU origin groups have required fields" do
      result = Portfolio.build("user3_port")
      rsu_origins = result["RSU"]
      assert length(rsu_origins) > 0

      for origin <- rsu_origins do
        assert origin.plan_type == "RSU"
        assert origin.grant_number != nil
        assert origin.origin_date != nil
        assert is_list(origin.tranches)
        assert is_integer(origin.vested_count)
        assert is_integer(origin.unvested_count)
      end
    end

    test "ESPP origins present" do
      result = Portfolio.build("user3_port")
      espp = result["ESPP"]
      assert length(espp) > 0
    end

    test "ESPP cost_basis is FMV (not discounted price)" do
      result = Portfolio.build("user3_port")
      espp = result["ESPP"]

      for origin <- espp, t <- origin.tranches do
        if t.cost_basis_per_share do
          # FMV should be > $300 (discounted price is ~$286)
          assert Decimal.gt?(t.cost_basis_per_share, Decimal.new(300))
        end
      end
    end

    test "tranches sorted ascending by vest_date" do
      result = Portfolio.build("user3_port")

      for {_type, origins} <- result, origin <- origins, length(origin.tranches) > 1 do
        dates = Enum.map(origin.tranches, & &1.vest_date) |> Enum.reject(&is_nil/1)

        for [a, b] <- Enum.chunk_every(dates, 2, 1, :discard) do
          assert Date.compare(a, b) != :gt
        end
      end
    end

    test "vested rows excluded when sellable_qty = 0" do
      result = Portfolio.build("user3_port")
      flat = Portfolio.flat_holdings(result)

      for h <- flat, h.status == "VESTED" do
        assert h.quantity != nil
        assert Decimal.gt?(h.quantity, Decimal.new(0))
      end
    end

    test "unvested rows have no cost_basis" do
      result = Portfolio.build("user3_port")
      flat = Portfolio.flat_holdings(result)
      unvested = Enum.filter(flat, &(&1.status == "UNVESTED"))

      if length(unvested) > 0 do
        for h <- unvested do
          assert h.cost_basis_per_share == nil
        end
      end
    end
  end

  describe "build/1 — BH fallback (no Holdings)" do
    test "User 1 all sold = empty portfolio" do
      setup_bh_user1()
      result = Portfolio.build("user1_port")
      flat = Portfolio.flat_holdings(result)

      # User 1 has sold everything — portfolio should be empty
      assert flat == []
    end

    test "empty account returns empty map" do
      result = Portfolio.build("nonexistent_account")
      assert result == %{"ESPP" => [], "RSU" => []}
    end
  end

  describe "flat_holdings/1" do
    test "flattens hierarchical data" do
      setup_holdings_user3()
      hierarchical = Portfolio.build("user3_port")
      flat = Portfolio.flat_holdings(hierarchical)

      assert is_list(flat)
      assert length(flat) > 0
      assert Enum.all?(flat, &Map.has_key?(&1, :plan_type))
    end
  end

  describe "compute_summary/2" do
    test "computes correct totals" do
      setup_holdings_user3()
      flat = Portfolio.build("user3_port") |> Portfolio.flat_holdings()
      summary = Portfolio.compute_summary(flat, "250.00")

      assert Decimal.equal?(
               summary.total_value,
               Decimal.add(summary.current_value, summary.potential_value)
             )
    end

    test "breakdown by plan_type" do
      setup_holdings_user3()
      flat = Portfolio.build("user3_port") |> Portfolio.flat_holdings()
      summary = Portfolio.compute_summary(flat, "250.00")

      assert Map.has_key?(summary.by_plan_type, "RSU")
      assert Map.has_key?(summary.by_plan_type, "ESPP")
    end

    test "no holdings returns zero summary" do
      summary = Portfolio.compute_summary([], "250.00")
      assert Decimal.equal?(summary.total_value, Decimal.new(0))
    end
  end

  describe "held_symbols/1" do
    test "empty account returns []" do
      assert Portfolio.held_symbols("nonexistent_account") == []
    end

    test "single-symbol holdings returns [symbol]" do
      setup_holdings_user3()
      symbols = Portfolio.held_symbols("user3_port")
      assert symbols == ["ADBE"]
    end
  end

  describe "owned_symbols/1" do
    test "empty account returns []" do
      assert Portfolio.owned_symbols("nonexistent_account") == []
    end

    test "single-symbol returns [symbol] sorted" do
      setup_bh_user1()
      symbols = Portfolio.owned_symbols("user1_port")
      assert symbols == ["ADBE"]
    end
  end

  describe "symbol_summaries/3" do
    test "returns empty list for empty account" do
      assert Portfolio.symbol_summaries("nonexistent_account", %{}) == []
    end

    test "one entry per symbol with correct totals" do
      setup_holdings_user3()
      prices = %{"ADBE" => Decimal.new("400.00")}
      [summary] = Portfolio.symbol_summaries("user3_port", prices)

      assert summary.symbol == "ADBE"
      assert Decimal.gt?(summary.held_qty, Decimal.new(0))
      # current_value = held_qty * 400
      expected = Decimal.mult(summary.held_qty, Decimal.new("400.00"))
      assert Decimal.equal?(summary.current_value_usd, expected)
    end

    test "INR fields populated when fx supplied" do
      setup_holdings_user3()
      prices = %{"ADBE" => Decimal.new("400.00")}
      fx = Decimal.new("83")
      [summary] = Portfolio.symbol_summaries("user3_port", prices, fx)

      assert summary.current_value_inr != nil
      expected_inr = Decimal.mult(summary.current_value_usd, fx)
      assert Decimal.equal?(summary.current_value_inr, expected_inr)
    end

    test "INR fields nil when fx is nil" do
      setup_holdings_user3()
      prices = %{"ADBE" => Decimal.new("400.00")}
      [summary] = Portfolio.symbol_summaries("user3_port", prices, nil)
      assert summary.current_value_inr == nil
    end
  end
end
