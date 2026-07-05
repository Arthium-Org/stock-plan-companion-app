defmodule StockPlan.Schema.SaleTest do
  use StockPlan.DataCase, async: true

  alias StockPlan.Schema.{Sale, Origin}
  alias StockPlan.Repo
  alias StockPlan.{TestFixtures, ID}

  defp create_origin do
    ing = TestFixtures.create_ingestion()

    origin =
      %Origin{}
      |> Origin.changeset(%{
        id: ID.generate(),
        ingestion_id: ing.ingestion_id,
        account_id: "default",
        symbol: "ADBE",
        plan_type: "RSU",
        grant_number: "RU" <> ID.generate(),
        origin_date: ~D[2025-01-24],
        total_quantity: "100",
        currency: "USD"
      })
      |> Repo.insert!()

    {ing, origin}
  end

  @valid_attrs %{
    id: "sale_test_000001",
    ingestion_id: "placeholder",
    origin_id: "placeholder",
    account_id: "default",
    symbol: "ADBE",
    sale_date: ~D[2026-08-01],
    total_quantity: "10",
    sale_price: "520.00",
    sale_fx_rate: "84.50",
    proceeds: "5200.00"
  }

  describe "changeset/2 — unit" do
    test "valid sale with all fields" do
      changeset = Sale.changeset(%Sale{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid sale without sale_price (nil from Benefit History)" do
      attrs = Map.delete(@valid_attrs, :sale_price)
      changeset = Sale.changeset(%Sale{}, attrs)
      assert changeset.valid?
    end

    test "missing total_quantity rejected" do
      attrs = Map.delete(@valid_attrs, :total_quantity)
      changeset = Sale.changeset(%Sale{}, attrs)
      refute changeset.valid?
    end

    test "missing origin_id rejected" do
      attrs = Map.delete(@valid_attrs, :origin_id)
      changeset = Sale.changeset(%Sale{}, attrs)
      refute changeset.valid?
    end

    test "optional fields nil valid" do
      attrs = Map.drop(@valid_attrs, [:sale_price, :sale_fx_rate, :proceeds, :metadata_json])
      changeset = Sale.changeset(%Sale{}, attrs)
      assert changeset.valid?
    end

    test "empty attrs gives errors on required fields" do
      changeset = Sale.changeset(%Sale{}, %{})
      refute changeset.valid?
      assert length(changeset.errors) == 7
    end
  end

  describe "Repo integration" do
    test "insert sale with origin, read back" do
      {ing, origin} = create_origin()

      attrs =
        @valid_attrs
        |> Map.put(:ingestion_id, ing.ingestion_id)
        |> Map.put(:origin_id, origin.id)

      {:ok, _} = Sale.changeset(%Sale{}, attrs) |> Repo.insert()
      fetched = Repo.get(Sale, "sale_test_000001")

      assert fetched.sale_date == ~D[2026-08-01]
      assert fetched.origin_id == origin.id
    end

    test "sale without sale_price persists correctly" do
      {ing, origin} = create_origin()

      attrs =
        @valid_attrs
        |> Map.put(:ingestion_id, ing.ingestion_id)
        |> Map.put(:origin_id, origin.id)
        |> Map.delete(:sale_price)

      {:ok, _} = Sale.changeset(%Sale{}, attrs) |> Repo.insert()
      fetched = Repo.get(Sale, "sale_test_000001")
      assert fetched.sale_price == nil
    end

    test "FK rejects non-existent origin_id" do
      ing = TestFixtures.create_ingestion()

      attrs =
        @valid_attrs
        |> Map.put(:ingestion_id, ing.ingestion_id)
        |> Map.put(:origin_id, "nonexistent_0000")

      assert_raise Ecto.ConstraintError, ~r/foreign_key/, fn ->
        Sale.changeset(%Sale{}, attrs) |> Repo.insert!()
      end
    end
  end
end
