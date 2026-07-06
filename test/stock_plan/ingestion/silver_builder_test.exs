defmodule StockPlan.Ingestion.SilverBuilderTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Ingestion.{SilverBuilder, XlsxParser, BronzeWriter}
  alias StockPlan.Schema.{Origin, Tranche, Sale, SaleAllocation, BronzeRaw}
  alias StockPlan.{Repo, TestFixtures}
  import Ecto.Query

  @sample2 "test/fixtures/sample-data/su2/Sample2-BenefitHistory.xlsx"

  defp ingest_sample(file \\ @sample2) do
    ing = TestFixtures.create_ingestion()
    {:ok, rows, _} = XlsxParser.parse(file)
    {:ok, _} = BronzeWriter.write(ing.ingestion_id, rows)
    ing
  end

  describe "build/1 — validation" do
    test "non-existent account returns error" do
      assert {:error, :no_benefit_history} = SilverBuilder.build("nonexistent_0000")
    end

    test "account with no ACTIVE Benefit History returns error" do
      ing = TestFixtures.create_ingestion(%{status: "ARCHIVED"})
      assert {:error, :no_benefit_history} = SilverBuilder.build(ing.account_id)
    end
  end

  describe "build/1 — RSU processing" do
    test "creates RSU origins from Grant rows" do
      ing = ingest_sample()
      {:ok, _summary} = SilverBuilder.build(ing.account_id)

      rsu_origins = Repo.all(from o in Origin, where: o.plan_type == "RSU")
      assert length(rsu_origins) == 13

      for origin <- rsu_origins do
        assert origin.plan_type == "RSU"
        assert origin.symbol == "ADBE"
        assert origin.grant_number != nil
        assert origin.origin_date != nil
        assert origin.ingestion_id == ing.ingestion_id
      end
    end

    test "creates tranches from Vest Schedule rows" do
      ing = ingest_sample()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      tranches = Repo.all(from t in Tranche, where: t.ingestion_id == ^ing.ingestion_id)
      assert length(tranches) > 0

      unvested = Enum.filter(tranches, &(&1.status == "UNVESTED"))
      assert length(unvested) > 0
    end

    test "Shares vested + Shares released pair creates VESTED tranche" do
      ing = ingest_sample()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      vested =
        Repo.all(
          from t in Tranche,
            join: o in Origin,
            on: t.origin_id == o.id,
            where: o.plan_type == "RSU" and t.status == "VESTED"
        )

      assert length(vested) > 0

      for t <- vested do
        assert t.vest_quantity != nil
        assert t.net_quantity != nil
      end
    end

    test "RSU sales created from Shares sold events" do
      ing = ingest_sample()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      rsu_sales =
        Repo.all(
          from s in Sale, join: o in Origin, on: s.origin_id == o.id, where: o.plan_type == "RSU"
        )

      assert length(rsu_sales) > 0

      for sale <- rsu_sales do
        assert sale.sale_price == nil
        assert sale.origin_id != nil
        assert sale.sale_date != nil
      end
    end

    test "RSU sales have NO allocations" do
      ing = ingest_sample()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      rsu_sales =
        Repo.all(
          from s in Sale,
            join: o in Origin,
            on: s.origin_id == o.id,
            where: o.plan_type == "RSU",
            select: s.id
        )

      allocs = Repo.all(from a in SaleAllocation, where: a.sale_id in ^rsu_sales)
      assert length(allocs) == 0
    end
  end

  describe "build/1 — ESPP processing" do
    test "creates ESPP origins grouped by enrollment (Grant Date)" do
      ing = ingest_sample()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      espp_origins = Repo.all(from o in Origin, where: o.plan_type == "ESPP")
      assert length(espp_origins) > 0

      for origin <- espp_origins do
        assert origin.grant_number != nil
        assert origin.origin_fmv != nil
        assert origin.total_quantity == nil
      end
    end

    test "ESPP purchases create VESTED tranches" do
      ing = ingest_sample()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      espp_tranches =
        Repo.all(
          from t in Tranche,
            join: o in Origin,
            on: t.origin_id == o.id,
            where: o.plan_type == "ESPP"
        )

      assert length(espp_tranches) > 0

      for t <- espp_tranches do
        assert t.status == "VESTED"
        assert t.vest_quantity != nil
        assert t.vest_fmv != nil
        assert t.net_quantity != nil
      end
    end

    test "ESPP tranche metadata has buy_price" do
      ing = ingest_sample()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      t =
        Repo.one(
          from t in Tranche,
            join: o in Origin,
            on: t.origin_id == o.id,
            where: o.plan_type == "ESPP",
            limit: 1
        )

      assert t.metadata_json != nil
      meta = Jason.decode!(t.metadata_json)
      assert Map.has_key?(meta, "buy_price")
    end

    test "ESPP sales created by BH have no allocations (G&L provides confirmed lot linkage)" do
      ing = ingest_sample()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      espp_sales =
        Repo.all(
          from s in Sale, join: o in Origin, on: s.origin_id == o.id, where: o.plan_type == "ESPP"
        )

      if length(espp_sales) > 0 do
        allocs =
          Repo.all(
            from a in SaleAllocation,
              where: a.sale_id in ^Enum.map(espp_sales, & &1.id)
          )

        assert allocs == []
      end
    end
  end

  describe "build/1 — orchestration" do
    test "returns summary with counts" do
      ing = ingest_sample()
      {:ok, summary} = SilverBuilder.build(ing.account_id)

      assert summary.origins > 0
      assert summary.tranches > 0
      assert summary.sales >= 0
      assert is_list(summary.warnings)
    end

    test "rebuild is idempotent (same logical state)" do
      ing = ingest_sample()
      {:ok, summary1} = SilverBuilder.build(ing.account_id)
      {:ok, summary2} = SilverBuilder.build(ing.account_id)

      assert summary1.origins == summary2.origins
      assert summary1.tranches == summary2.tranches
      assert summary1.sales == summary2.sales
      assert summary1.allocations == summary2.allocations
    end

    test "rebuild deletes old Silver before recreating" do
      ing = ingest_sample()
      SilverBuilder.build(ing.account_id)

      origin_count_1 = Repo.aggregate(Origin, :count)
      SilverBuilder.build(ing.account_id)
      origin_count_2 = Repo.aggregate(Origin, :count)

      assert origin_count_1 == origin_count_2
    end

    test "Bronze rows survive rebuild" do
      ing = ingest_sample()
      bronze_count = Repo.aggregate(BronzeRaw, :count)

      SilverBuilder.build(ing.account_id)
      assert Repo.aggregate(BronzeRaw, :count) == bronze_count
    end

    test "all origin dates are valid Date structs" do
      ing = ingest_sample()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      origins = Repo.all(Origin)

      for o <- origins do
        assert %Date{} = o.origin_date
      end
    end
  end
end
