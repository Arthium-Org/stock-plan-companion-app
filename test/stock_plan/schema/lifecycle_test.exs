defmodule StockPlan.Schema.LifecycleTest do
  use StockPlan.DataCase, async: true

  alias StockPlan.Schema.{Origin, Tranche, Exercise, Sale, SaleAllocation}
  alias StockPlan.Repo
  alias StockPlan.TestFixtures
  alias StockPlan.ID

  describe "RSU full chain" do
    test "ingestion → origin → tranche (VESTED) → sale → allocation" do
      ing = TestFixtures.create_ingestion()

      # Origin (RSU grant)
      origin =
        %Origin{}
        |> Origin.changeset(%{
          id: ID.generate(),
          ingestion_id: ing.ingestion_id,
          account_id: "default",
          symbol: "ADBE",
          plan_type: "RSU",
          grant_number: "RU422478",
          origin_date: ~D[2025-01-24],
          total_quantity: "100",
          origin_fmv: "450.00",
          origin_fx_rate: "83.50",
          currency: "USD"
        })
        |> Repo.insert!()

      # Tranche (vest)
      tranche =
        %Tranche{}
        |> Tranche.changeset(%{
          id: ID.generate(),
          origin_id: origin.id,
          ingestion_id: ing.ingestion_id,
          vest_date: ~D[2025-07-24],
          vest_quantity: "25",
          vest_fmv: "480.00",
          vest_fx_rate: "84.00",
          tax_withheld_qty: "9",
          net_quantity: "16",
          status: "VESTED"
        })
        |> Repo.insert!()

      # Sale
      sale =
        %Sale{}
        |> Sale.changeset(%{
          id: ID.generate(),
          ingestion_id: ing.ingestion_id,
          origin_id: origin.id,
          account_id: "default",
          symbol: "ADBE",
          sale_date: ~D[2026-01-15],
          total_quantity: "10",
          sale_price: "520.00",
          sale_fx_rate: "84.50"
        })
        |> Repo.insert!()

      # Sale Allocation (RSU: tranche is the lot)
      alloc =
        %SaleAllocation{}
        |> SaleAllocation.changeset(%{
          id: ID.generate(),
          sale_id: sale.id,
          tranche_id: tranche.id,
          quantity: "10"
        })
        |> Repo.insert!()

      assert alloc.tranche_id == tranche.id
      assert alloc.exercise_id == nil
    end
  end

  describe "ESPP full chain" do
    test "ingestion → origin (enrollment) → tranche (purchase) → sale → allocation" do
      ing = TestFixtures.create_ingestion()

      # Origin (ESPP enrollment — lock-in date + terms)
      origin =
        %Origin{}
        |> Origin.changeset(%{
          id: ID.generate(),
          ingestion_id: ing.ingestion_id,
          account_id: "default",
          symbol: "ADBE",
          plan_type: "ESPP",
          origin_date: ~D[2024-01-01],
          total_quantity: "25",
          origin_fmv: "150.00",
          origin_fx_rate: "83.00",
          currency: "USD",
          metadata_json: ~s({"discount_percent":"15","qualified_plan":true})
        })
        |> Repo.insert!()

      # Tranche (ESPP purchase — equivalent to RSU vest)
      tranche =
        %Tranche{}
        |> Tranche.changeset(%{
          id: ID.generate(),
          origin_id: origin.id,
          ingestion_id: ing.ingestion_id,
          vest_date: ~D[2024-06-30],
          vest_quantity: "25",
          vest_fmv: "160.00",
          vest_fx_rate: "83.50",
          tax_withheld_qty: "4",
          net_quantity: "21",
          status: "VESTED",
          metadata_json: ~s({"buy_price":"127.50"})
        })
        |> Repo.insert!()

      # Sale
      sale =
        %Sale{}
        |> Sale.changeset(%{
          id: ID.generate(),
          ingestion_id: ing.ingestion_id,
          origin_id: origin.id,
          account_id: "default",
          symbol: "ADBE",
          sale_date: ~D[2025-08-01],
          total_quantity: "15",
          sale_price: "500.00"
        })
        |> Repo.insert!()

      # Sale Allocation (ESPP: tranche is the lot, no exercise needed)
      alloc =
        %SaleAllocation{}
        |> SaleAllocation.changeset(%{
          id: ID.generate(),
          sale_id: sale.id,
          tranche_id: tranche.id,
          quantity: "15"
        })
        |> Repo.insert!()

      assert alloc.tranche_id == tranche.id
      assert alloc.exercise_id == nil
    end
  end

  describe "ESOP full chain" do
    test "ingestion → origin → tranche → exercise → sale → allocation" do
      ing = TestFixtures.create_ingestion()

      # Origin (ESOP grant)
      origin =
        %Origin{}
        |> Origin.changeset(%{
          id: ID.generate(),
          ingestion_id: ing.ingestion_id,
          account_id: "default",
          symbol: "ADBE",
          plan_type: "ESOP",
          grant_number: "EF03554",
          origin_date: ~D[2020-03-15],
          total_quantity: "500",
          origin_fmv: "300.00",
          origin_fx_rate: "75.00",
          currency: "USD",
          metadata_json: ~s({"strike_price":"72.36","option_type":"NQ"})
        })
        |> Repo.insert!()

      # Tranche (vest — unlocks exercise right)
      tranche =
        %Tranche{}
        |> Tranche.changeset(%{
          id: ID.generate(),
          origin_id: origin.id,
          ingestion_id: ing.ingestion_id,
          vest_date: ~D[2021-03-15],
          vest_quantity: "125",
          status: "VESTED"
        })
        |> Repo.insert!()

      # Exercise (converts right into owned shares)
      exercise =
        %Exercise{}
        |> Exercise.changeset(%{
          id: ID.generate(),
          tranche_id: tranche.id,
          ingestion_id: ing.ingestion_id,
          exercise_date: ~D[2025-06-15],
          exercise_quantity: "50",
          exercise_price: "72.36",
          exercise_fmv: "500.00",
          exercise_fx_rate: "84.00",
          tax_withheld_qty: "18",
          net_quantity: "32"
        })
        |> Repo.insert!()

      # Sale
      sale =
        %Sale{}
        |> Sale.changeset(%{
          id: ID.generate(),
          ingestion_id: ing.ingestion_id,
          origin_id: origin.id,
          account_id: "default",
          symbol: "ADBE",
          sale_date: ~D[2026-01-10],
          total_quantity: "20",
          sale_price: "550.00"
        })
        |> Repo.insert!()

      # Sale Allocation (EXERCISE source)
      alloc =
        %SaleAllocation{}
        |> SaleAllocation.changeset(%{
          id: ID.generate(),
          sale_id: sale.id,
          tranche_id: tranche.id,
          exercise_id: exercise.id,
          quantity: "20"
        })
        |> Repo.insert!()

      assert alloc.tranche_id == tranche.id
      assert alloc.exercise_id == exercise.id
    end
  end

  describe "FK enforcement — deletion order" do
    setup do
      ing = TestFixtures.create_ingestion()

      origin =
        %Origin{}
        |> Origin.changeset(%{
          id: ID.generate(),
          ingestion_id: ing.ingestion_id,
          account_id: "default",
          symbol: "ADBE",
          plan_type: "RSU",
          grant_number: "RU_DEL_TEST",
          origin_date: ~D[2025-01-01],
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
          vest_date: ~D[2025-07-01],
          vest_quantity: "25",
          status: "VESTED",
          vest_fmv: "450.00",
          net_quantity: "16"
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
          sale_date: ~D[2026-01-01],
          total_quantity: "10",
          sale_price: "500.00"
        })
        |> Repo.insert!()

      alloc =
        %SaleAllocation{}
        |> SaleAllocation.changeset(%{
          id: ID.generate(),
          sale_id: sale.id,
          tranche_id: tranche.id,
          quantity: "10"
        })
        |> Repo.insert!()

      %{origin: origin, tranche: tranche, sale: sale, alloc: alloc}
    end

    test "cannot delete origin while tranches exist", %{origin: origin} do
      assert_raise Ecto.ConstraintError, fn -> Repo.delete(origin) end
    end

    test "cannot delete sale while allocations exist", %{sale: sale} do
      assert_raise Ecto.ConstraintError, fn -> Repo.delete(sale) end
    end

    test "correct deletion order succeeds", %{
      origin: origin,
      tranche: tranche,
      sale: sale,
      alloc: alloc
    } do
      Repo.delete(alloc)
      Repo.delete(sale)
      Repo.delete(tranche)
      Repo.delete(origin)
    end
  end
end
