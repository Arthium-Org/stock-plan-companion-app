defmodule StockPlan.Schema.SaleAllocationTest do
  use StockPlan.DataCase, async: true

  alias StockPlan.Schema.{SaleAllocation, Sale, Origin, Tranche, Exercise}
  alias StockPlan.Repo
  alias StockPlan.TestFixtures
  alias StockPlan.ID

  defp create_sale_with_tranche do
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

    tranche =
      %Tranche{}
      |> Tranche.changeset(%{
        id: ID.generate(),
        origin_id: origin.id,
        ingestion_id: ing.ingestion_id,
        vest_date: ~D[2025-07-24],
        vest_quantity: "25",
        vest_fmv: "480.00",
        net_quantity: "16",
        status: "VESTED"
      })
      |> Repo.insert!()

    sale =
      %Sale{}
      |> Sale.changeset(%{
        id: ID.generate(),
        ingestion_id: ing.ingestion_id,
        origin_id: origin.id,
        account_id: "default",
        symbol: "ADBE",
        sale_date: ~D[2026-08-01],
        total_quantity: "10",
        sale_price: "520.00"
      })
      |> Repo.insert!()

    {ing, origin, tranche, sale}
  end

  @valid_attrs %{
    id: "alloc_test_00001",
    sale_id: "placeholder",
    tranche_id: "placeholder",
    quantity: "10"
  }

  describe "changeset/2 — unit" do
    test "valid with tranche_id (RSU/ESPP)" do
      changeset = SaleAllocation.changeset(%SaleAllocation{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid with tranche_id + exercise_id (ESOP)" do
      attrs = Map.put(@valid_attrs, :exercise_id, "some_exercise_id0")
      changeset = SaleAllocation.changeset(%SaleAllocation{}, attrs)
      assert changeset.valid?
    end

    test "exercise_id nil is valid (RSU/ESPP)" do
      changeset = SaleAllocation.changeset(%SaleAllocation{}, @valid_attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :exercise_id) == nil
    end

    test "missing tranche_id rejected" do
      attrs = Map.delete(@valid_attrs, :tranche_id)
      changeset = SaleAllocation.changeset(%SaleAllocation{}, attrs)
      refute changeset.valid?
    end

    test "missing quantity rejected" do
      attrs = Map.delete(@valid_attrs, :quantity)
      changeset = SaleAllocation.changeset(%SaleAllocation{}, attrs)
      refute changeset.valid?
    end

    test "empty attrs gives errors on required fields" do
      changeset = SaleAllocation.changeset(%SaleAllocation{}, %{})
      refute changeset.valid?
      assert length(changeset.errors) == 4
    end
  end

  describe "Repo integration" do
    test "insert allocation linked to sale and tranche" do
      {_ing, _origin, tranche, sale} = create_sale_with_tranche()
      attrs = %{@valid_attrs | sale_id: sale.id, tranche_id: tranche.id}

      {:ok, _} = SaleAllocation.changeset(%SaleAllocation{}, attrs) |> Repo.insert()
      fetched = Repo.get(SaleAllocation, "alloc_test_00001")

      assert %Decimal{} = fetched.quantity
      assert Decimal.equal?(fetched.quantity, Decimal.new("10"))
      assert fetched.tranche_id == tranche.id
      assert fetched.exercise_id == nil
    end

    test "FK rejects non-existent sale_id" do
      {_ing, _origin, tranche, _sale} = create_sale_with_tranche()
      attrs = %{@valid_attrs | sale_id: "nonexistent_0000", tranche_id: tranche.id}

      assert_raise Ecto.ConstraintError, ~r/foreign_key/, fn ->
        SaleAllocation.changeset(%SaleAllocation{}, attrs) |> Repo.insert!()
      end
    end

    test "FK rejects non-existent tranche_id" do
      {_ing, _origin, _tranche, sale} = create_sale_with_tranche()
      attrs = %{@valid_attrs | sale_id: sale.id, tranche_id: "nonexistent_0000"}

      assert_raise Ecto.ConstraintError, ~r/foreign_key/, fn ->
        SaleAllocation.changeset(%SaleAllocation{}, attrs) |> Repo.insert!()
      end
    end
  end
end
