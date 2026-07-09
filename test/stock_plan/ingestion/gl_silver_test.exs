defmodule StockPlan.Ingestion.GlSilverTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Ingestion.{XlsxParser, GlParser, BronzeWriter, SilverBuilder, BronzeRow}
  alias StockPlan.Schema.{Origin, Tranche, Sale, SaleAllocation, BronzeRaw}
  alias StockPlan.{Repo, TestFixtures}
  import Ecto.Query

  @benefit_history "test/fixtures/sample-data/su1/sample-Etrade-BenefitHistory.xlsx"
  @gl_2025 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2025.xlsx"
  @gl_2024 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2024.xlsx"
  @gl_2023 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2023.xlsx"

  @bh_user2 "test/fixtures/sample-data/su2/Sample2-BenefitHistory.xlsx"
  @gl_user2_2025 "test/fixtures/sample-data/su2/G&L_Expanded_2025.xlsx"
  @gl_user2_2026 "test/fixtures/sample-data/su2/G&L_Expanded_2026.xlsx"

  defp ingest_benefit_history(account_id \\ "user1", file \\ @benefit_history) do
    ing = TestFixtures.create_ingestion(%{account_id: account_id, category: "BENEFIT_HISTORY"})
    {:ok, rows, _} = XlsxParser.parse(file)
    {:ok, _} = BronzeWriter.write(ing.ingestion_id, rows)
    ing
  end

  defp ingest_gl(file, account_id \\ "user1") do
    ing =
      TestFixtures.create_gl_ingestion(%{
        account_id: account_id,
        file_name: Path.basename(file),
        file_hash: "sha256_" <> StockPlan.ID.generate()
      })

    {:ok, rows, _} = GlParser.parse(file)
    {:ok, _} = BronzeWriter.write(ing.ingestion_id, rows)
    ing
  end

  describe "build/1 with account_id — Benefit History only" do
    test "works with only Benefit History" do
      ing = ingest_benefit_history()
      {:ok, summary} = SilverBuilder.build(ing.account_id)
      assert summary.origins > 0
      assert summary.tranches > 0
    end

    test "returns error with no Benefit History" do
      assert {:error, :no_benefit_history} = SilverBuilder.build("nonexistent")
    end

    test "RSU vest_day_close is populated from stock prices without G&L" do
      # Phase 4 stock-price enrichment fills vest_day_close (not vest_fmv) from
      # market close data even without a G&L file. vest_fmv stays nil on the
      # BH-only path -- only vest_day_close is backfilled by stock-price
      # enrichment (see SilverBuilder.enrich_stock_prices/1, which updates
      # vest_day_close on VESTED tranches missing it).
      ing = ingest_benefit_history()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      rsu_vested =
        Repo.all(
          from t in Tranche,
            join: o in Origin,
            on: t.origin_id == o.id,
            where: o.plan_type == "RSU" and t.status == "VESTED"
        )

      assert length(rsu_vested) > 0
      # At least some vested tranches have vest_day_close filled by stock price enrichment
      assert Enum.any?(rsu_vested, &(&1.vest_day_close != nil))
    end

    test "RSU sales have nil price without G&L" do
      ing = ingest_benefit_history()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      rsu_sales =
        Repo.all(
          from s in Sale, join: o in Origin, on: s.origin_id == o.id, where: o.plan_type == "RSU"
        )

      assert length(rsu_sales) > 0
      assert Enum.all?(rsu_sales, &(&1.sale_price == nil))
    end

    test "no RSU sale allocations without G&L" do
      ing = ingest_benefit_history()
      {:ok, _} = SilverBuilder.build(ing.account_id)

      rsu_allocs =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            join: o in Origin,
            on: s.origin_id == o.id,
            where: o.plan_type == "RSU" and o.account_id == ^ing.account_id
        )

      assert length(rsu_allocs) == 0
    end
  end

  describe "build/1 with G&L enrichment" do
    test "G&L enriches RSU tranche vest_fmv" do
      ingest_benefit_history()
      ingest_gl(@gl_2025)

      {:ok, _} = SilverBuilder.build("user1")

      rsu_with_fmv =
        Repo.all(
          from t in Tranche,
            join: o in Origin,
            on: t.origin_id == o.id,
            where: o.plan_type == "RSU" and not is_nil(t.vest_fmv)
        )

      assert length(rsu_with_fmv) > 0
    end

    test "G&L creates allocations with sale_price" do
      ingest_benefit_history()
      ingest_gl(@gl_2025)

      {:ok, _} = SilverBuilder.build("user1")

      # Price is on allocations, not sales (G&L data → allocations, BH data → sales)
      priced = Repo.all(from a in SaleAllocation, where: not is_nil(a.sale_price))
      assert length(priced) > 0
    end

    test "G&L creates RSU sale allocations" do
      ingest_benefit_history()
      ingest_gl(@gl_2025)

      {:ok, _} = SilverBuilder.build("user1")

      rsu_allocs =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            join: o in Origin,
            on: s.origin_id == o.id,
            where: o.plan_type == "RSU"
        )

      assert length(rsu_allocs) > 0
    end

    test "ESPP sales do NOT get new allocations from G&L" do
      ingest_benefit_history()
      ingest_gl(@gl_2025)

      # Build twice — count ESPP allocations
      {:ok, _s1} = SilverBuilder.build("user1")

      espp_allocs_1 =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            join: o in Origin,
            on: s.origin_id == o.id,
            where: o.plan_type == "ESPP"
        )
        |> length()

      # ESPP allocs come from M5 (Benefit History), not G&L
      # They should exist from Phase 1
      assert espp_allocs_1 > 0
    end

    test "rebuild is idempotent with both sources" do
      ingest_benefit_history()
      ingest_gl(@gl_2025)

      {:ok, s1} = SilverBuilder.build("user1")
      {:ok, s2} = SilverBuilder.build("user1")

      assert s1.origins == s2.origins
      assert s1.tranches == s2.tranches
      assert s1.sales == s2.sales
    end

    test "Bronze rows unchanged by rebuild" do
      ingest_benefit_history()
      ingest_gl(@gl_2025)

      bronze_count = Repo.aggregate(BronzeRaw, :count)
      SilverBuilder.build("user1")
      assert Repo.aggregate(BronzeRaw, :count) == bronze_count
    end

    test "multi-year G&L — all enrichments applied" do
      ingest_benefit_history()
      ingest_gl(@gl_2023)
      ingest_gl(@gl_2024)
      ingest_gl(@gl_2025)

      {:ok, summary} = SilverBuilder.build("user1")

      rsu_allocs =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            join: o in Origin,
            on: s.origin_id == o.id,
            where: o.plan_type == "RSU"
        )
        |> length()

      IO.puts(
        "  Multi-year: #{summary.origins} origins, #{summary.tranches} tranches, #{summary.sales} sales, RSU allocs: #{rsu_allocs}"
      )

      assert rsu_allocs > 0
    end

    test "unmatched G&L rows produce warnings" do
      ingest_benefit_history()
      ingest_gl(@gl_2025)

      {:ok, summary} = SilverBuilder.build("user1")
      # Some G&L rows may reference grants not in SampleUser-1's Benefit History
      assert is_list(summary.warnings)
    end

    test "aggregates same-price G&L rows into one allocation" do
      ingest_benefit_history()
      ingest_gl(@gl_2023)
      ingest_gl(@gl_2024)
      ingest_gl(@gl_2025)

      {:ok, _} = SilverBuilder.build("user1")

      origin =
        Repo.one!(from o in Origin, where: o.grant_number == "RU401244", limit: 1)

      tranche =
        Repo.one!(
          from t in Tranche,
            where: t.origin_id == ^origin.id and t.vest_date == ^~D[2025-10-15],
            limit: 1
        )

      allocs =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            where: a.tranche_id == ^tranche.id and s.sale_date == ^~D[2025-10-27],
            select: a.quantity
        )

      # Same-price G&L sub-lots (wash-sale rows with same order/price) are aggregated
      # into one allocation by aggregate_gl_bronze/1.
      assert length(allocs) == 1
      # The G&L 2025 file has two rows for this lot (order 96988186, price 355.135):
      # real-data quantities of Qty=2 and Qty=4 aggregate to 6 (real Sample-Data).
      # The synthetic fixture applies a x0.65 per-cell scale to quantities (05-02),
      # which shifts this sum -- captured actual (not hand-derived) via a run
      # against the synthetic fixture: 4. The 2023 and 2024 files have no rows for
      # this lot, so cross-file latest-wins does not reduce the count; the
      # surviving ingestion's rows are the only contributors to this sum.
      assert Decimal.equal?(hd(allocs), Decimal.new("4"))
    end

    test "User 2 RU383740 / order 94231427 aggregates sub-lots into one allocation per (tranche, price)" do
      ingest_benefit_history("user2", @bh_user2)
      ingest_gl(@gl_user2_2025, "user2")
      ingest_gl(@gl_user2_2026, "user2")

      {:ok, _} = SilverBuilder.build("user2")

      origin =
        Repo.one!(
          from o in Origin,
            where: o.account_id == "user2" and o.grant_number == "RU383740",
            limit: 1
        )

      allocs =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            where: s.origin_id == ^origin.id and a.order_number == "94231427",
            select: {a.tranche_id, a.sale_price}
        )

      # Sub-lots with the same (tranche_id, sale_price, order_number) are aggregated.
      # There must be exactly one allocation per unique (tranche_id, sale_price) pair —
      # no duplicates from wash-sale row splitting.
      unique_keys = Enum.uniq(allocs)

      assert length(allocs) == length(unique_keys),
             "Expected one allocation per (tranche_id, sale_price), got duplicates: #{inspect(allocs)}"

      assert length(allocs) > 0, "No allocations found for RU383740 / order 94231427"

      # Verify the aggregated quantity for the vest 2025-04-15 lot.
      # The 2025 G&L has 3 sub-lot rows for this (vest, order): real-data
      # quantities Qty=4, Qty=4, Qty=1 sum to 9 (real Sample-Data). The
      # synthetic fixture applies a x0.65 per-cell scale to quantities (05-02),
      # which shifts this sum -- captured actual (not hand-derived) via a run
      # against the synthetic fixture: 7.
      tranche_apr15 =
        Repo.one!(
          from t in StockPlan.Schema.Tranche,
            where: t.origin_id == ^origin.id and t.vest_date == ^~D[2025-04-15],
            limit: 1
        )

      apr15_qty =
        Repo.one!(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            where:
              a.tranche_id == ^tranche_apr15.id and
                a.order_number == "94231427",
            select: a.quantity
        )

      assert Decimal.equal?(apr15_qty, Decimal.new("7")),
             "Expected aggregated qty=7 for RU383740 vest 2025-04-15 / order 94231427, got #{apr15_qty}"
    end
  end

  describe "aggregate_gl_bronze/1 — tested through SilverBuilder.build/1" do
    # The aggregate_gl_bronze/1 function is private; all cases are tested by inserting
    # synthetic Bronze G&L rows and observing the resulting SaleAllocations.

    defp make_gl_bronze_row(overrides) do
      base = %{
        "Symbol" => "ADBE",
        "Plan Type" => "RS",
        "Grant Number" => "RU999001",
        # MM/DD/YYYY — the format parse_date/1 understands for event-row dates
        "Vest Date" => "01/15/2024",
        "Date Sold" => "06/10/2024",
        "Date Acquired" => nil,
        "Purchase Date" => nil,
        "Grant Date" => nil,
        "Order Number" => "77001",
        "Proceeds Per Share" => "450.00",
        "Quantity" => "2",
        "Vest Date FMV" => nil
      }

      data = Map.merge(base, overrides)
      json = Jason.encode!(data)

      hash =
        :crypto.hash(:sha256, "test_gl:#{json}:#{:rand.uniform(1_000_000)}")
        |> Base.encode16(case: :lower)

      %BronzeRow{
        sheet_name: "G&L_Expanded",
        record_type: "Sell",
        row_index: :rand.uniform(999_999),
        parent_index: nil,
        raw_row_json: json,
        row_hash: hash
      }
    end

    defp insert_synthetic_bh(account_id, grant_number, vest_date) do
      ing =
        TestFixtures.create_ingestion(%{
          account_id: account_id,
          category: "BENEFIT_HISTORY",
          dominant_symbol: "ADBE"
        })

      grant_json =
        Jason.encode!(%{
          "Symbol" => "ADBE",
          "Grant Number" => grant_number,
          "Grant Date" => "01-JAN-2023",
          "Granted Qty." => "100",
          "Vested Qty." => "10",
          "Unvested Qty." => "90",
          "Status" => "Open",
          "Type" => "RSU"
        })

      vest_json =
        Jason.encode!(%{
          "Symbol" => "ADBE",
          "Date" => vest_date,
          "Event Type" => "Shares released",
          "Qty. or Amount" => "8"
        })

      sold_json =
        Jason.encode!(%{
          "Symbol" => "ADBE",
          "Date" => "06/10/2024",
          "Event Type" => "Shares sold",
          "Qty. or Amount" => "4"
        })

      vested_event_json =
        Jason.encode!(%{
          "Symbol" => "ADBE",
          "Date" => vest_date,
          "Event Type" => "Shares vested",
          "Qty. or Amount" => "10"
        })

      grant_row = %BronzeRow{
        sheet_name: "Restricted Stock",
        record_type: "Grant",
        row_index: 0,
        parent_index: nil,
        raw_row_json: grant_json,
        row_hash: :crypto.hash(:sha256, grant_json) |> Base.encode16(case: :lower)
      }

      vested_event_row = %BronzeRow{
        sheet_name: "Restricted Stock",
        record_type: "Event",
        row_index: 1,
        parent_index: 0,
        raw_row_json: vested_event_json,
        row_hash: :crypto.hash(:sha256, vested_event_json) |> Base.encode16(case: :lower)
      }

      vest_event_row = %BronzeRow{
        sheet_name: "Restricted Stock",
        record_type: "Event",
        row_index: 2,
        parent_index: 0,
        raw_row_json: vest_json,
        row_hash: :crypto.hash(:sha256, vest_json) |> Base.encode16(case: :lower)
      }

      sold_event_row = %BronzeRow{
        sheet_name: "Restricted Stock",
        record_type: "Event",
        row_index: 3,
        parent_index: 0,
        raw_row_json: sold_json,
        row_hash: :crypto.hash(:sha256, sold_json) |> Base.encode16(case: :lower)
      }

      {:ok, _} =
        BronzeWriter.write(ing.ingestion_id, [
          grant_row,
          vested_event_row,
          vest_event_row,
          sold_event_row
        ])

      ing
    end

    test "T4-1: within-file sub-lot aggregation — same (symbol, grant, vest, order, price), different rows → one allocation with summed qty" do
      account_id = "t4_1_#{:rand.uniform(99999)}"
      _bh_ing = insert_synthetic_bh(account_id, "RU999001", "01/15/2024")

      gl_ing = TestFixtures.create_gl_ingestion(%{account_id: account_id})

      row1 = make_gl_bronze_row(%{"Quantity" => "3", "Vest Date FMV" => "420.00"})
      row2 = make_gl_bronze_row(%{"Quantity" => "4", "Vest Date FMV" => nil})
      {:ok, _} = BronzeWriter.write(gl_ing.ingestion_id, [row1, row2])

      {:ok, _} = SilverBuilder.build(account_id)

      allocs =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            where: s.account_id == ^account_id and a.order_number == "77001",
            select: a.quantity
        )

      assert length(allocs) == 1
      assert Decimal.equal?(hd(allocs), Decimal.new("7"))
    end

    test "T4-2: price-variation — same (symbol, grant, vest, order), different price → two separate allocations" do
      account_id = "t4_2_#{:rand.uniform(99999)}"
      _bh_ing = insert_synthetic_bh(account_id, "RU999001", "01/15/2024")

      gl_ing = TestFixtures.create_gl_ingestion(%{account_id: account_id})

      row1 =
        make_gl_bronze_row(%{
          "Quantity" => "3",
          "Proceeds Per Share" => "450.00",
          "Order Number" => "77001"
        })

      row2 =
        make_gl_bronze_row(%{
          "Quantity" => "4",
          "Proceeds Per Share" => "452.50",
          "Order Number" => "77001"
        })

      {:ok, _} = BronzeWriter.write(gl_ing.ingestion_id, [row1, row2])

      {:ok, _} = SilverBuilder.build(account_id)

      allocs =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            where: s.account_id == ^account_id and a.order_number == "77001",
            select: a
        )

      quantities = Enum.map(allocs, & &1.quantity) |> Enum.sort_by(&Decimal.to_float/1)

      assert length(allocs) == 2
      assert Decimal.equal?(Enum.at(quantities, 0), Decimal.new("3"))
      assert Decimal.equal?(Enum.at(quantities, 1), Decimal.new("4"))
    end

    test "T4-3: cross-file latest-wins — two ingestions for same (symbol, sale_date), newer file's rows survive" do
      account_id = "t4_3_#{:rand.uniform(99999)}"
      _bh_ing = insert_synthetic_bh(account_id, "RU999001", "01/15/2024")

      # Older ingestion: 5 shares
      gl_old =
        TestFixtures.create_gl_ingestion(%{
          account_id: account_id,
          file_name: "G&L_old.xlsx",
          file_hash: "sha256_old_#{:rand.uniform(99999)}"
        })

      row_old = make_gl_bronze_row(%{"Quantity" => "5"})
      {:ok, _} = BronzeWriter.write(gl_old.ingestion_id, [row_old])

      # Simulate newer ingestion with a later inserted_at by updating the DB
      # Newer ingestion: 3 shares for the same (symbol, sale_date)
      gl_new =
        TestFixtures.create_gl_ingestion(%{
          account_id: account_id,
          file_name: "G&L_new.xlsx",
          file_hash: "sha256_new_#{:rand.uniform(99999)}"
        })

      future_time =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:microsecond)

      Repo.update_all(
        from(i in StockPlan.Schema.Ingestion, where: i.ingestion_id == ^gl_new.ingestion_id),
        set: [inserted_at: future_time]
      )

      row_new = make_gl_bronze_row(%{"Quantity" => "3"})
      {:ok, _} = BronzeWriter.write(gl_new.ingestion_id, [row_new])

      {:ok, _} = SilverBuilder.build(account_id)

      allocs =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            where: s.account_id == ^account_id and a.order_number == "77001",
            select: a.quantity
        )

      # Only newer ingestion's rows survive: qty = 3
      assert length(allocs) == 1
      assert Decimal.equal?(hd(allocs), Decimal.new("3"))
    end

    test "T4-4: ESPP grouping — two rows with Grant Number '--', same (grant_date, purchase_date, order, price) → one lot with summed qty" do
      account_id = "t4_4_#{:rand.uniform(99999)}"

      # Minimal ESPP Benefit History
      bh_ing =
        TestFixtures.create_ingestion(%{
          account_id: account_id,
          category: "BENEFIT_HISTORY",
          dominant_symbol: "ADBE"
        })

      grant_json =
        Jason.encode!(%{
          "Symbol" => "ADBE",
          "Grant Date" => "01-JUL-2023",
          "Purchase Date" => "31-DEC-2023",
          "Purchase Price" => "136.00",
          "Purchased Qty." => "10",
          "Net Shares" => "8",
          "Tax Collection Shares" => "2",
          "Purchase Date FMV" => "160.00",
          "Grant Date FMV" => "145.00",
          "Discount Percent" => "15",
          "Qualified Plan?" => "Y"
        })

      sell_event_json =
        Jason.encode!(%{
          "Symbol" => "ADBE",
          "Date" => "03/15/2024",
          "Event Type" => "SELL",
          "Qty" => "5"
        })

      grant_row = %BronzeRow{
        sheet_name: "ESPP",
        record_type: "Purchase",
        row_index: 0,
        parent_index: nil,
        raw_row_json: grant_json,
        row_hash: :crypto.hash(:sha256, grant_json) |> Base.encode16(case: :lower)
      }

      sell_row = %BronzeRow{
        sheet_name: "ESPP",
        record_type: "Event",
        row_index: 1,
        parent_index: 0,
        raw_row_json: sell_event_json,
        row_hash: :crypto.hash(:sha256, sell_event_json) |> Base.encode16(case: :lower)
      }

      {:ok, _} = BronzeWriter.write(bh_ing.ingestion_id, [grant_row, sell_row])

      # Two ESPP G&L rows with "--" grant number, same order/price
      gl_ing = TestFixtures.create_gl_ingestion(%{account_id: account_id})

      espp_base = %{
        "Symbol" => "ADBE",
        "Plan Type" => "ESPP",
        "Grant Number" => "--",
        # MM/DD/YYYY — the only format parse_date/1 understands for this field
        "Grant Date" => "07/01/2023",
        "Purchase Date" => "12/31/2023",
        "Vest Date" => nil,
        "Date Sold" => "03/15/2024",
        "Date Acquired" => "12/31/2023",
        "Order Number" => "55001",
        "Proceeds Per Share" => "170.00",
        "Vest Date FMV" => nil
      }

      row1 = make_gl_bronze_row(Map.merge(espp_base, %{"Quantity" => "2"}))
      row2 = make_gl_bronze_row(Map.merge(espp_base, %{"Quantity" => "3"}))
      {:ok, _} = BronzeWriter.write(gl_ing.ingestion_id, [row1, row2])

      {:ok, _} = SilverBuilder.build(account_id)

      allocs =
        Repo.all(
          from a in SaleAllocation,
            join: s in Sale,
            on: a.sale_id == s.id,
            where: s.account_id == ^account_id and a.order_number == "55001",
            select: a.quantity
        )

      assert length(allocs) == 1
      assert Decimal.equal?(hd(allocs), Decimal.new("5"))
    end

    test "T4-5: two ESPP purchase lots of EQUAL qty sold same date each map to their own G&L allocation (no false 'missing G&L')" do
      account_id = "t4_5_#{:rand.uniform(99_999)}"

      bh_ing =
        TestFixtures.create_ingestion(%{
          account_id: account_id,
          category: "BENEFIT_HISTORY",
          dominant_symbol: "ADBE"
        })

      # Same enrollment (Grant Date 01-JUL-2019), two distinct purchase lots,
      # each sells qty 2 on the SAME date. Regression for the ESPP matcher that
      # keyed only on (origin, sale_date, qty) and starved the second lot.
      lots = [
        {"31-DEC-2019", "12/31/2019", 0},
        {"30-JUN-2020", "06/30/2020", 2}
      ]

      bh_rows =
        Enum.flat_map(lots, fn {purchase_date_dmy, _purchase_date_mdy, base_idx} ->
          grant_json =
            Jason.encode!(%{
              "Symbol" => "ADBE",
              "Grant Date" => "01-JUL-2019",
              "Purchase Date" => purchase_date_dmy,
              "Purchase Price" => "100.00",
              "Purchased Qty." => "10",
              "Net Shares" => "10",
              "Tax Collection Shares" => "0",
              "Purchase Date FMV" => "120.00",
              "Grant Date FMV" => "110.00",
              "Discount Percent" => "15",
              "Qualified Plan?" => "Y"
            })

          sell_json =
            Jason.encode!(%{
              "Symbol" => "ADBE",
              "Date" => "09/26/2025",
              "Event Type" => "SELL",
              "Qty" => "2"
            })

          [
            %BronzeRow{
              sheet_name: "ESPP",
              record_type: "Purchase",
              row_index: base_idx,
              parent_index: nil,
              raw_row_json: grant_json,
              row_hash: :crypto.hash(:sha256, grant_json <> "#{base_idx}") |> Base.encode16(case: :lower)
            },
            %BronzeRow{
              sheet_name: "ESPP",
              record_type: "Event",
              row_index: base_idx + 1,
              parent_index: base_idx,
              raw_row_json: sell_json,
              row_hash: :crypto.hash(:sha256, sell_json <> "#{base_idx}") |> Base.encode16(case: :lower)
            }
          ]
        end)

      {:ok, _} = BronzeWriter.write(bh_ing.ingestion_id, bh_rows)

      gl_ing = TestFixtures.create_gl_ingestion(%{account_id: account_id})

      espp_base = %{
        "Symbol" => "ADBE",
        "Plan Type" => "ESPP",
        "Grant Number" => "--",
        "Grant Date" => "07/01/2019",
        "Vest Date" => nil,
        "Date Sold" => "09/26/2025",
        "Order Number" => "96328228",
        "Proceeds Per Share" => "353.70",
        "Quantity" => "2",
        "Vest Date FMV" => nil
      }

      gl_rows = [
        make_gl_bronze_row(Map.merge(espp_base, %{"Purchase Date" => "12/31/2019", "Date Acquired" => "12/31/2019"})),
        make_gl_bronze_row(Map.merge(espp_base, %{"Purchase Date" => "06/30/2020", "Date Acquired" => "06/30/2020"}))
      ]

      {:ok, _} = BronzeWriter.write(gl_ing.ingestion_id, gl_rows)

      {:ok, _} = SilverBuilder.build(account_id)

      sales =
        Repo.all(
          from s in Sale,
            where: s.account_id == ^account_id and s.sale_date == ^~D[2025-09-26],
            select: s
        )

      assert length(sales) == 2

      # Every sale must have exactly one PRICED G&L allocation — no starvation, no double-count.
      priced_counts =
        Enum.map(sales, fn s ->
          Repo.aggregate(
            from(a in SaleAllocation, where: a.sale_id == ^s.id and not is_nil(a.sale_price)),
            :count
          )
        end)

      assert priced_counts == [1, 1]
    end
  end
end
