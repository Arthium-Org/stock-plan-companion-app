defmodule StockPlan.IngestionsTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Ingestions
  alias StockPlan.Schema.{Ingestion, Origin, Tranche, Sale, SaleAllocation, BronzeRaw}
  alias StockPlan.Repo
  import Ecto.Query

  @bh_file "test/fixtures/sample-data/su1/sample-Etrade-BenefitHistory.xlsx"
  @gl_2025 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2025.xlsx"
  @gl_2024 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2024.xlsx"

  describe "ingest_benefit_history/2" do
    test "ingests valid BH file — full pipeline" do
      {:ok, summary} = Ingestions.ingest_benefit_history("user1", @bh_file)

      assert summary.ingestion_id != nil
      assert summary.bronze.inserted > 0
      assert summary.silver.origins > 0
      assert summary.silver.tranches > 0

      # Verify DB state
      assert Repo.aggregate(Origin, :count) > 0
      assert Repo.aggregate(Tranche, :count) > 0
    end

    test "returns error for non-existent file" do
      assert {:error, :file_not_found} =
               Ingestions.ingest_benefit_history("user1", "/nonexistent.xlsx")
    end

    test "archives previous BH on new upload" do
      {:ok, s1} = Ingestions.ingest_benefit_history("user1", @bh_file)

      # Use SampleUser-2 BH as "different" file (different hash)
      bh2 = "test/fixtures/sample-data/su2/Sample2-BenefitHistory.xlsx"
      {:ok, s2} = Ingestions.ingest_benefit_history("user1", bh2)

      old = Repo.get(Ingestion, s1.ingestion_id)
      new = Repo.get(Ingestion, s2.ingestion_id)
      assert old.status == "ARCHIVED"
      assert new.status == "ACTIVE"
    end

    test "ingestion record has correct fields" do
      {:ok, summary} = Ingestions.ingest_benefit_history("user1", @bh_file)
      ing = Repo.get(Ingestion, summary.ingestion_id)

      assert ing.category == "BENEFIT_HISTORY"
      assert ing.status == "ACTIVE"
      assert ing.account_id == "user1"
      assert ing.file_hash != nil
      assert ing.file_name == "sample-Etrade-BenefitHistory.xlsx"
    end

    test "no ingestion created on parse failure" do
      count_before = Repo.aggregate(Ingestion, :count)
      result = Ingestions.ingest_benefit_history("user1", Path.join(System.tmp_dir!(), "bad.txt"))
      assert {:error, _} = result
      assert Repo.aggregate(Ingestion, :count) == count_before
    end
  end

  describe "ingest_gl/2" do
    test "ingests valid G&L file after BH" do
      {:ok, _} = Ingestions.ingest_benefit_history("user1", @bh_file)
      {:ok, summary} = Ingestions.ingest_gl("user1", @gl_2025)

      assert summary.ingestion_id != nil
      assert summary.bronze.inserted > 0
    end

    test "returns error without prior BH" do
      assert {:error, :no_benefit_history} = Ingestions.ingest_gl("user1", @gl_2025)
    end

    test "multiple G&L files coexist" do
      {:ok, _} = Ingestions.ingest_benefit_history("user1", @bh_file)
      {:ok, s1} = Ingestions.ingest_gl("user1", @gl_2025)
      {:ok, s2} = Ingestions.ingest_gl("user1", @gl_2024)

      ing1 = Repo.get(Ingestion, s1.ingestion_id)
      ing2 = Repo.get(Ingestion, s2.ingestion_id)

      assert ing1.status == "ACTIVE"
      assert ing2.status == "ACTIVE"
      assert ing1.category == "GL_EXPANDED"
      assert ing2.category == "GL_EXPANDED"
    end

    test "G&L enriches Silver data" do
      {:ok, _} = Ingestions.ingest_benefit_history("user1", @bh_file)

      # Before G&L: no RSU vest_fmv
      rsu_fmv_before =
        Repo.aggregate(
          from(t in Tranche,
            join: o in Origin,
            on: t.origin_id == o.id,
            where: o.plan_type == "RSU" and not is_nil(t.vest_fmv)
          ),
          :count
        )

      {:ok, _} = Ingestions.ingest_gl("user1", @gl_2025)

      rsu_fmv_after =
        Repo.aggregate(
          from(t in Tranche,
            join: o in Origin,
            on: t.origin_id == o.id,
            where: o.plan_type == "RSU" and not is_nil(t.vest_fmv)
          ),
          :count
        )

      assert rsu_fmv_after > rsu_fmv_before
    end
  end

  describe "duplicate detection" do
    test "same BH file twice returns duplicate error" do
      {:ok, s1} = Ingestions.ingest_benefit_history("user1", @bh_file)
      result = Ingestions.ingest_benefit_history("user1", @bh_file)

      assert {:error, :duplicate_file, existing_id} = result
      assert existing_id == s1.ingestion_id
    end

    test "same G&L file twice returns duplicate error" do
      {:ok, _} = Ingestions.ingest_benefit_history("user1", @bh_file)
      {:ok, s1} = Ingestions.ingest_gl("user1", @gl_2025)
      result = Ingestions.ingest_gl("user1", @gl_2025)

      assert {:error, :duplicate_file, existing_id} = result
      assert existing_id == s1.ingestion_id
    end
  end

  describe "rebuild/1" do
    test "rebuilds Silver from existing Bronze" do
      {:ok, _} = Ingestions.ingest_benefit_history("user1", @bh_file)

      origin_count = Repo.aggregate(Origin, :count)
      {:ok, summary} = Ingestions.rebuild("user1")

      assert summary.origins == origin_count
    end

    test "returns error with no BH" do
      assert {:error, :no_benefit_history} = Ingestions.rebuild("nonexistent")
    end
  end

  describe "full pipeline integration" do
    test "BH + multiple G&L + rebuild" do
      {:ok, bh} = Ingestions.ingest_benefit_history("user1", @bh_file)
      assert bh.silver.origins > 0

      {:ok, _} = Ingestions.ingest_gl("user1", @gl_2025)
      {:ok, _} = Ingestions.ingest_gl("user1", @gl_2024)

      # Verify enrichment
      rsu_allocs =
        Repo.aggregate(
          from(a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            join: o in Origin,
            on: s.origin_id == o.id,
            where: o.plan_type == "RSU"
          ),
          :count
        )

      assert rsu_allocs > 0

      # Rebuild produces same state
      {:ok, rebuilt} = Ingestions.rebuild("user1")
      assert rebuilt.origins == bh.silver.origins

      # Bronze untouched
      assert Repo.aggregate(BronzeRaw, :count) > 0

      IO.puts(
        "  Pipeline: #{bh.silver.origins} origins, #{rebuilt.tranches} tranches, RSU allocs: #{rsu_allocs}"
      )
    end
  end
end
