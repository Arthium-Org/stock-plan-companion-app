defmodule StockPlan.Schema.ExerciseTest do
  use StockPlan.DataCase, async: true

  alias StockPlan.Schema.{Exercise, Origin, Tranche}
  alias StockPlan.Repo
  alias StockPlan.TestFixtures

  defp create_chain do
    ing = TestFixtures.create_ingestion()

    origin =
      %Origin{}
      |> Origin.changeset(%{
        id: StockPlan.ID.generate(),
        ingestion_id: ing.ingestion_id,
        account_id: "default",
        symbol: "ADBE",
        plan_type: "ESOP",
        grant_number: "EF" <> StockPlan.ID.generate(),
        origin_date: ~D[2020-03-15],
        total_quantity: "500",
        currency: "USD",
        metadata_json: ~s({"strike_price":"72.36","option_type":"NQ"})
      })
      |> Repo.insert!()

    tranche =
      %Tranche{}
      |> Tranche.changeset(%{
        id: StockPlan.ID.generate(),
        origin_id: origin.id,
        ingestion_id: ing.ingestion_id,
        vest_date: ~D[2021-03-15],
        vest_quantity: "125",
        status: "VESTED"
      })
      |> Repo.insert!()

    {ing, origin, tranche}
  end

  @valid_attrs %{
    id: "exercise_test001",
    tranche_id: "placeholder",
    ingestion_id: "placeholder",
    exercise_date: ~D[2026-06-15],
    exercise_quantity: "50",
    exercise_price: "72.36",
    exercise_fmv: "500.00",
    exercise_fx_rate: "84.00",
    tax_withheld_qty: "18",
    net_quantity: "32"
  }

  describe "changeset/2 — unit" do
    test "valid exercise with all fields" do
      changeset = Exercise.changeset(%Exercise{}, @valid_attrs)
      assert changeset.valid?
    end

    test "missing exercise_price rejected" do
      attrs = Map.delete(@valid_attrs, :exercise_price)
      changeset = Exercise.changeset(%Exercise{}, attrs)
      refute changeset.valid?
    end

    test "missing exercise_quantity rejected" do
      attrs = Map.delete(@valid_attrs, :exercise_quantity)
      changeset = Exercise.changeset(%Exercise{}, attrs)
      refute changeset.valid?
    end

    test "optional fields nil is valid" do
      attrs =
        Map.drop(@valid_attrs, [
          :exercise_fmv,
          :exercise_fx_rate,
          :tax_withheld_qty,
          :net_quantity
        ])

      changeset = Exercise.changeset(%Exercise{}, attrs)
      assert changeset.valid?
    end

    test "empty attrs gives errors on required fields" do
      changeset = Exercise.changeset(%Exercise{}, %{})
      refute changeset.valid?
      assert length(changeset.errors) == 6
    end
  end

  describe "Repo integration" do
    test "insert exercise with full parent chain" do
      {ing, _origin, tranche} = create_chain()
      attrs = %{@valid_attrs | tranche_id: tranche.id, ingestion_id: ing.ingestion_id}

      {:ok, _} = Exercise.changeset(%Exercise{}, attrs) |> Repo.insert()
      fetched = Repo.get(Exercise, "exercise_test001")

      assert fetched.exercise_date == ~D[2026-06-15]
      assert Decimal.equal?(fetched.exercise_price, Decimal.new("72.36"))
      assert Decimal.equal?(fetched.exercise_quantity, Decimal.new("50"))
    end

    test "FK rejects non-existent tranche_id" do
      ing = TestFixtures.create_ingestion()
      attrs = %{@valid_attrs | tranche_id: "nonexistent_0000", ingestion_id: ing.ingestion_id}

      assert_raise Ecto.ConstraintError, ~r/foreign_key/, fn ->
        Exercise.changeset(%Exercise{}, attrs) |> Repo.insert!()
      end
    end

    test "SafeDecimal fields round-trip" do
      {ing, _origin, tranche} = create_chain()
      attrs = %{@valid_attrs | tranche_id: tranche.id, ingestion_id: ing.ingestion_id}

      {:ok, _} = Exercise.changeset(%Exercise{}, attrs) |> Repo.insert()
      fetched = Repo.get(Exercise, "exercise_test001")

      assert %Decimal{} = fetched.exercise_fmv
      assert Decimal.equal?(fetched.exercise_fmv, Decimal.new("500.00"))
    end
  end
end
