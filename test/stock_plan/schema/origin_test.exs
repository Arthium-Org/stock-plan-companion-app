defmodule StockPlan.Schema.OriginTest do
  use StockPlan.DataCase, async: true

  alias StockPlan.Schema.Origin
  alias StockPlan.Repo
  alias StockPlan.TestFixtures

  @rsu_attrs %{
    id: "origin_rsu_00001",
    ingestion_id: "placeholder",
    account_id: "default",
    symbol: "ADBE",
    plan_type: "RSU",
    grant_number: "RU422478",
    origin_date: ~D[2025-01-24],
    total_quantity: "100",
    origin_fmv: "450.00",
    origin_fx_rate: "83.50",
    currency: "USD"
  }

  @espp_attrs %{
    id: "origin_espp_0001",
    ingestion_id: "placeholder",
    account_id: "default",
    symbol: "ADBE",
    plan_type: "ESPP",
    origin_date: ~D[2024-06-30],
    total_quantity: "25",
    origin_fmv: "160.00",
    origin_fx_rate: "83.00",
    currency: "USD",
    metadata_json: ~s({"lock_in_price":"150.00","buy_price":"127.50","discount_percent":"15"})
  }

  @esop_attrs %{
    id: "origin_esop_0001",
    ingestion_id: "placeholder",
    account_id: "default",
    symbol: "ADBE",
    plan_type: "ESOP",
    grant_number: "EF03554",
    origin_date: ~D[2020-03-15],
    total_quantity: "500",
    origin_fmv: "300.00",
    origin_fx_rate: "75.00",
    currency: "USD",
    metadata_json: ~s({"strike_price":"72.36","option_type":"NQ","expiry_date":"2030-03-15"})
  }

  describe "changeset/2 — unit" do
    test "valid RSU origin" do
      changeset = Origin.changeset(%Origin{}, @rsu_attrs)
      assert changeset.valid?
    end

    test "valid ESPP origin (no grant_number)" do
      changeset = Origin.changeset(%Origin{}, @espp_attrs)
      assert changeset.valid?
    end

    test "valid ESOP origin" do
      changeset = Origin.changeset(%Origin{}, @esop_attrs)
      assert changeset.valid?
    end

    test "invalid plan_type rejected" do
      attrs = Map.put(@rsu_attrs, :plan_type, "PHANTOM")
      changeset = Origin.changeset(%Origin{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).plan_type
    end

    test "invalid currency rejected" do
      attrs = Map.put(@rsu_attrs, :currency, "EUR")
      changeset = Origin.changeset(%Origin{}, attrs)
      refute changeset.valid?
    end

    test "missing symbol rejected" do
      attrs = Map.delete(@rsu_attrs, :symbol)
      changeset = Origin.changeset(%Origin{}, attrs)
      refute changeset.valid?
    end

    test "empty attrs gives 7 errors" do
      changeset = Origin.changeset(%Origin{}, %{})
      refute changeset.valid?
      assert length(changeset.errors) == 7
    end

    test "origin_date as Date with SafeDecimal total_quantity" do
      changeset = Origin.changeset(%Origin{}, @rsu_attrs)
      assert changeset.valid?
      assert get_field(changeset, :origin_date) == ~D[2025-01-24]
    end
  end

  describe "Repo integration" do
    test "insert RSU origin, read back typed fields" do
      ing = TestFixtures.create_ingestion()
      attrs = Map.put(@rsu_attrs, :ingestion_id, ing.ingestion_id)

      {:ok, _} = Origin.changeset(%Origin{}, attrs) |> Repo.insert()
      fetched = Repo.get(Origin, "origin_rsu_00001")

      assert fetched.origin_date == ~D[2025-01-24]
      assert %Decimal{} = fetched.total_quantity
      assert Decimal.equal?(fetched.total_quantity, Decimal.new("100"))
      assert %Decimal{} = fetched.origin_fmv
      assert Decimal.equal?(fetched.origin_fmv, Decimal.new("450.00"))
    end

    test "insert ESPP with metadata_json stored unchanged" do
      ing = TestFixtures.create_ingestion()
      attrs = Map.put(@espp_attrs, :ingestion_id, ing.ingestion_id)

      {:ok, _} = Origin.changeset(%Origin{}, attrs) |> Repo.insert()
      fetched = Repo.get(Origin, "origin_espp_0001")

      assert fetched.metadata_json =~ "lock_in_price"
      assert fetched.metadata_json =~ "127.50"
    end

    test "FK rejects non-existent ingestion_id" do
      assert_raise Ecto.ConstraintError, ~r/foreign_key/, fn ->
        Origin.changeset(%Origin{}, @rsu_attrs) |> Repo.insert!()
      end
    end

    test "nullable fields accept nil" do
      ing = TestFixtures.create_ingestion()

      attrs = %{
        id: "origin_nil_test1",
        ingestion_id: ing.ingestion_id,
        account_id: "default",
        symbol: "ADBE",
        plan_type: "RSU",
        origin_date: ~D[2025-01-01],
        total_quantity: "50",
        currency: "USD"
      }

      {:ok, origin} = Origin.changeset(%Origin{}, attrs) |> Repo.insert()
      assert origin.origin_fmv == nil
      assert origin.origin_fx_rate == nil
      assert origin.status == nil
      assert origin.metadata_json == nil
    end

    test "unique constraint rejects duplicate ingestion_id + grant_number" do
      ing = TestFixtures.create_ingestion()
      attrs = Map.put(@rsu_attrs, :ingestion_id, ing.ingestion_id)

      {:ok, _} = Origin.changeset(%Origin{}, attrs) |> Repo.insert()

      duplicate = Map.put(attrs, :id, "origin_rsu_dupl1")

      assert {:error, changeset} = Origin.changeset(%Origin{}, duplicate) |> Repo.insert()
      assert "has already been taken" in errors_on(changeset).ingestion_id
    end

    test "same grant_number in different ingestion succeeds" do
      ing1 = TestFixtures.create_ingestion()
      ing2 = TestFixtures.create_ingestion()

      attrs1 = Map.merge(@rsu_attrs, %{ingestion_id: ing1.ingestion_id, id: "origin_ing1_001"})
      attrs2 = Map.merge(@rsu_attrs, %{ingestion_id: ing2.ingestion_id, id: "origin_ing2_001"})

      {:ok, _} = Origin.changeset(%Origin{}, attrs1) |> Repo.insert()
      {:ok, _} = Origin.changeset(%Origin{}, attrs2) |> Repo.insert()
    end
  end
end
