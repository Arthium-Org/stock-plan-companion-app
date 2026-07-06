defmodule StockPlan.MultiSymbolTest do
  @moduledoc """
  Integration tests for M22 — Multi-Symbol Support.
  Uses SampleUser-5: ADBE BH + CRM BH + CRM Holdings + shared G&L.
  """
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.{Ingestions, Portfolio, Repo}
  alias StockPlan.Schema.{Ingestion, Origin}
  import Ecto.Query

  @bh_adbe "test/fixtures/sample-data/su5/SampleUser5-BenefitHistory-ADBE.xlsx"
  @bh_crm "test/fixtures/sample-data/su5/SampleUser5-BenefitHistory-CRM.xlsx"
  @holdings_crm "test/fixtures/sample-data/su5/SampleUser5-ByBenefitType_expanded-CRM.xlsx"

  @account_id "user5"

  describe "per-symbol BH ingestion" do
    @tag :user5
    test "two BH files for different symbols both stay ACTIVE" do
      {:ok, adbe} = Ingestions.ingest_benefit_history(@account_id, @bh_adbe)
      {:ok, crm} = Ingestions.ingest_benefit_history(@account_id, @bh_crm)

      assert adbe.dominant_symbol == "ADBE"
      assert crm.dominant_symbol == "CRM"

      adbe_row = Repo.get(Ingestion, adbe.ingestion_id)
      crm_row = Repo.get(Ingestion, crm.ingestion_id)

      assert adbe_row.status == "ACTIVE"
      assert crm_row.status == "ACTIVE"
      assert adbe_row.dominant_symbol == "ADBE"
      assert crm_row.dominant_symbol == "CRM"

      # Silver has origins for both symbols
      symbols =
        Repo.all(
          from o in Origin,
            where: o.account_id == ^@account_id,
            distinct: true,
            select: o.symbol,
            order_by: o.symbol
        )

      assert "ADBE" in symbols
      assert "CRM" in symbols
    end

    @tag :user5
    test "active_bh_symbols/1 lists both" do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_adbe)
      {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_crm)

      assert ["ADBE", "CRM"] = Ingestions.active_bh_symbols(@account_id)
    end
  end

  describe "asymmetric coverage: ADBE BH only, CRM BH + Holdings" do
    @tag :user5
    test "held_symbols == [CRM]; owned_symbols == [ADBE, CRM]" do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_adbe)
      {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_crm)
      {:ok, _} = Ingestions.ingest_holdings(@account_id, @holdings_crm)

      assert Portfolio.owned_symbols(@account_id) == ["ADBE", "CRM"]
      # Portfolio is driven by Holdings when present; only CRM holdings exist
      held = Portfolio.held_symbols(@account_id)
      assert "CRM" in held
      refute "ADBE" in held
    end

    @tag :user5
    test "active_holdings_symbols/1 only returns CRM (no ADBE holdings)" do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_adbe)
      {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_crm)
      {:ok, _} = Ingestions.ingest_holdings(@account_id, @holdings_crm)

      assert Ingestions.active_holdings_symbols(@account_id) == ["CRM"]
    end
  end

  describe "extract_file_symbol/1" do
    @tag :user5
    test "extracts ADBE from a BH file's rows" do
      {:ok, rows, _} = StockPlan.Ingestion.XlsxParser.parse(@bh_adbe)
      assert {:ok, "ADBE"} = Ingestions.extract_file_symbol(rows)
    end

    @tag :user5
    test "extracts CRM from a BH file's rows" do
      {:ok, rows, _} = StockPlan.Ingestion.XlsxParser.parse(@bh_crm)
      assert {:ok, "CRM"} = Ingestions.extract_file_symbol(rows)
    end

    test "returns :no_symbol for empty input" do
      assert {:error, :no_symbol} = Ingestions.extract_file_symbol([])
    end
  end
end
