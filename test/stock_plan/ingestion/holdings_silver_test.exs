defmodule StockPlan.Ingestion.HoldingsSilverTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Ingestion.{HoldingsParser, BronzeWriter, HoldingsSilverBuilder}
  alias StockPlan.Schema.Holding
  alias StockPlan.{Repo, TestFixtures}
  import Ecto.Query

  @holdings_sample3 "docs/Sample-Data/SampleUser - 3/Sample3-ByBenefitType_expanded.xlsx"
  @holdings_sample2 "docs/Sample-Data/SampleUser - 2/Sample2-ByBenefitType_expanded.xlsx"

  defp ingest_holdings(file, account_id) do
    ing =
      TestFixtures.create_holdings_ingestion(%{
        account_id: account_id,
        file_name: Path.basename(file),
        file_hash: "sha256_" <> StockPlan.ID.generate()
      })

    {:ok, rows, _} = HoldingsParser.parse(file)
    {:ok, _} = BronzeWriter.write(ing.ingestion_id, rows)
    ing
  end

  describe "build/1 — SampleUser-3 (ESPP + RSU with Sellable Shares)" do
    setup do
      account = "user3_hsilver"
      _ing = ingest_holdings(@holdings_sample3, account)
      {:ok, result} = HoldingsSilverBuilder.build(account)
      %{account: account, result: result}
    end

    test "creates RSU holdings rows", %{result: result} do
      assert result.rsu_rows == 77
    end

    test "creates ESPP holdings rows", %{result: result} do
      assert result.espp_rows == 4
    end

    test "RSU vested with Sellable Shares has sellable_qty > 0", %{account: account} do
      with_sellable =
        Repo.all(
          from h in Holding,
            where:
              h.account_id == ^account and h.plan_type == "RSU" and
                h.status == "VESTED" and not is_nil(h.sellable_qty) and
                h.sellable_qty != ^Decimal.new(0)
        )

      assert length(with_sellable) > 0
    end

    test "RSU vested without Sellable Shares has sellable_qty = 0", %{account: account} do
      sold =
        Repo.all(
          from h in Holding,
            where:
              h.account_id == ^account and h.plan_type == "RSU" and
                h.status == "VESTED" and h.sellable_qty == ^Decimal.new(0)
        )

      assert length(sold) > 0
    end

    test "RSU unvested has sellable_qty = nil", %{account: account} do
      unvested =
        Repo.all(
          from h in Holding,
            where:
              h.account_id == ^account and h.plan_type == "RSU" and
                h.status == "UNVESTED"
        )

      assert length(unvested) > 0
      assert Enum.all?(unvested, &is_nil(&1.sellable_qty))
    end

    test "RSU unvested has vested_qty (scheduled quantity)", %{account: account} do
      unvested =
        Repo.all(
          from h in Holding,
            where:
              h.account_id == ^account and h.plan_type == "RSU" and
                h.status == "UNVESTED" and not is_nil(h.vested_qty)
        )

      assert length(unvested) > 0
    end

    test "ESPP cost_basis is Purchase Date FMV", %{account: account} do
      espp =
        Repo.one(
          from h in Holding,
            where: h.account_id == ^account and h.plan_type == "ESPP",
            limit: 1
        )

      # cost_basis should be FMV (~336), not discounted price (~286)
      assert espp.cost_basis != nil
      assert Decimal.gt?(espp.cost_basis, Decimal.new(300))
    end

    test "ESPP purchase_price is discounted buy price", %{account: account} do
      espp =
        Repo.one(
          from h in Holding,
            where: h.account_id == ^account and h.plan_type == "ESPP",
            limit: 1
        )

      assert espp.purchase_price != nil
      assert Decimal.lt?(espp.purchase_price, espp.cost_basis)
    end

    test "metadata_json contains blocked info", %{account: account} do
      h =
        Repo.one(
          from h in Holding,
            where:
              h.account_id == ^account and h.plan_type == "RSU" and
                not is_nil(h.sellable_qty) and h.sellable_qty != ^Decimal.new(0),
            limit: 1
        )

      meta = Jason.decode!(h.metadata_json)
      assert meta["blocked"] != nil
    end
  end

  describe "build/1 — SampleUser-2 (RSU only, no Sellable Shares)" do
    setup do
      account = "user2_hsilver"
      _ing = ingest_holdings(@holdings_sample2, account)
      {:ok, result} = HoldingsSilverBuilder.build(account)
      %{account: account, result: result}
    end

    test "creates RSU rows", %{result: result} do
      assert result.rsu_rows == 64
    end

    test "no ESPP rows", %{result: result} do
      assert result.espp_rows == 0
    end

    test "all vested have sellable_qty = 0 (fully sold)", %{account: account} do
      vested =
        Repo.all(
          from h in Holding,
            where: h.account_id == ^account and h.status == "VESTED"
        )

      for h <- vested do
        assert h.sellable_qty != nil

        assert Decimal.equal?(h.sellable_qty, Decimal.new(0)),
               "Expected sellable=0 for vested period #{h.vest_period}, got #{h.sellable_qty}"
      end
    end
  end

  describe "build/1 — no Holdings ingestion" do
    test "returns error" do
      assert {:error, :no_holdings} = HoldingsSilverBuilder.build("nonexistent")
    end
  end

  describe "rebuild idempotency" do
    test "second build produces same row count" do
      account = "rebuild_test"
      _ing = ingest_holdings(@holdings_sample3, account)

      {:ok, first} = HoldingsSilverBuilder.build(account)
      {:ok, second} = HoldingsSilverBuilder.build(account)

      assert first.rsu_rows == second.rsu_rows
      assert first.espp_rows == second.espp_rows

      count = Repo.aggregate(from(h in Holding, where: h.account_id == ^account), :count)
      assert count == first.rsu_rows + first.espp_rows
    end
  end
end
