defmodule StockPlan.Schema.TrancheTest do
  use StockPlan.DataCase, async: true

  alias StockPlan.Schema.{Tranche, Origin}
  alias StockPlan.Repo
  alias StockPlan.TestFixtures

  defp create_origin do
    ing = TestFixtures.create_ingestion()

    %Origin{}
    |> Origin.changeset(%{
      id: StockPlan.ID.generate(),
      ingestion_id: ing.ingestion_id,
      account_id: "default",
      symbol: "ADBE",
      plan_type: "RSU",
      grant_number: "RU" <> StockPlan.ID.generate(),
      origin_date: ~D[2025-01-24],
      total_quantity: "100",
      currency: "USD"
    })
    |> Repo.insert!()
    |> then(&{ing, &1})
  end

  @unvested_attrs %{
    id: "tranche_unvest01",
    origin_id: "placeholder",
    ingestion_id: "placeholder",
    vest_date: ~D[2026-01-24],
    vest_quantity: "25",
    status: "UNVESTED"
  }

  @vested_attrs %{
    id: "tranche_vested1",
    origin_id: "placeholder",
    ingestion_id: "placeholder",
    vest_date: ~D[2025-04-24],
    vest_quantity: "25",
    vest_fmv: "480.00",
    vest_fx_rate: "84.00",
    tax_withheld_qty: "9",
    net_quantity: "16",
    status: "VESTED"
  }

  describe "changeset/2 — unit" do
    test "valid UNVESTED tranche (vest_fmv nil)" do
      changeset = Tranche.changeset(%Tranche{}, @unvested_attrs)
      assert changeset.valid?
    end

    test "valid VESTED tranche (vest_fmv populated)" do
      changeset = Tranche.changeset(%Tranche{}, @vested_attrs)
      assert changeset.valid?
    end

    for status <- ~w(UNVESTED VESTED FORFEITED CANCELLED EXPIRED) do
      test "status #{status} accepted" do
        attrs = Map.put(@unvested_attrs, :status, unquote(status))
        changeset = Tranche.changeset(%Tranche{}, attrs)
        assert changeset.valid?
      end
    end

    test "invalid status rejected" do
      attrs = Map.put(@unvested_attrs, :status, "INVALID")
      changeset = Tranche.changeset(%Tranche{}, attrs)
      refute changeset.valid?
    end

    test "missing vest_date rejected" do
      attrs = Map.delete(@unvested_attrs, :vest_date)
      changeset = Tranche.changeset(%Tranche{}, attrs)
      refute changeset.valid?
    end

    test "missing status rejected" do
      attrs = Map.delete(@unvested_attrs, :status)
      changeset = Tranche.changeset(%Tranche{}, attrs)
      refute changeset.valid?
    end

    test "empty attrs gives errors on all required" do
      changeset = Tranche.changeset(%Tranche{}, %{})
      refute changeset.valid?
      assert length(changeset.errors) == 5
    end
  end

  describe "Repo integration" do
    test "insert UNVESTED tranche, read back" do
      {ing, origin} = create_origin()
      attrs = %{@unvested_attrs | origin_id: origin.id, ingestion_id: ing.ingestion_id}

      {:ok, _} = Tranche.changeset(%Tranche{}, attrs) |> Repo.insert()
      fetched = Repo.get(Tranche, "tranche_unvest01")

      assert fetched.vest_date == ~D[2026-01-24]
      assert fetched.vest_fmv == nil
      assert %Decimal{} = fetched.vest_quantity
    end

    test "insert VESTED tranche with financial fields" do
      {ing, origin} = create_origin()
      attrs = %{@vested_attrs | origin_id: origin.id, ingestion_id: ing.ingestion_id}

      {:ok, _} = Tranche.changeset(%Tranche{}, attrs) |> Repo.insert()
      fetched = Repo.get(Tranche, "tranche_vested1")

      assert Decimal.equal?(fetched.vest_fmv, Decimal.new("480.00"))
      assert Decimal.equal?(fetched.net_quantity, Decimal.new("16"))
    end

    test "FK rejects non-existent origin_id" do
      ing = TestFixtures.create_ingestion()
      attrs = %{@unvested_attrs | origin_id: "nonexistent_0000", ingestion_id: ing.ingestion_id}

      assert_raise Ecto.ConstraintError, ~r/foreign_key/, fn ->
        Tranche.changeset(%Tranche{}, attrs) |> Repo.insert!()
      end
    end

    test "FK rejects non-existent ingestion_id" do
      {_ing, origin} = create_origin()
      attrs = %{@unvested_attrs | origin_id: origin.id, ingestion_id: "nonexistent_0000"}

      assert_raise Ecto.ConstraintError, ~r/foreign_key/, fn ->
        Tranche.changeset(%Tranche{}, attrs) |> Repo.insert!()
      end
    end

    test "delete origin while tranche exists raises" do
      {ing, origin} = create_origin()
      attrs = %{@unvested_attrs | origin_id: origin.id, ingestion_id: ing.ingestion_id}
      Tranche.changeset(%Tranche{}, attrs) |> Repo.insert!()

      assert_raise Ecto.ConstraintError, fn ->
        Repo.delete(origin)
      end
    end

    test "multiple tranches allowed for same origin + vest_date (split vests)" do
      {ing, origin} = create_origin()

      attrs1 = %{
        @unvested_attrs
        | origin_id: origin.id,
          ingestion_id: ing.ingestion_id,
          id: "tranche_split_01"
      }

      attrs2 = %{
        @unvested_attrs
        | origin_id: origin.id,
          ingestion_id: ing.ingestion_id,
          id: "tranche_split_02"
      }

      {:ok, _} = Tranche.changeset(%Tranche{}, attrs1) |> Repo.insert()
      {:ok, _} = Tranche.changeset(%Tranche{}, attrs2) |> Repo.insert()
    end
  end
end
