defmodule StockPlan.Schema.BronzeRawTest do
  use StockPlan.DataCase, async: true

  alias StockPlan.Schema.{BronzeRaw, Ingestion}
  alias StockPlan.Repo

  @ingestion_attrs %{
    ingestion_id: "ing_bronze_test1",
    account_id: "default",
    broker: "ETRADE",
    source_type: "XLSX",
    file_name: "test.xlsx",
    file_hash: "hash123",
    status: "ACTIVE"
  }

  @valid_attrs %{
    id: "bronze_row_00001",
    ingestion_id: "ing_bronze_test1",
    sheet_name: "Restricted Stock",
    record_type: "Grant",
    row_index: 0,
    raw_row_json: ~s({"Symbol":"ADBE","Grant Date":"24-JAN-2025"}),
    row_hash: "sha256_abc123"
  }

  defp create_ingestion do
    %Ingestion{}
    |> Ingestion.changeset(@ingestion_attrs)
    |> Repo.insert!()
  end

  describe "changeset/2" do
    test "valid with all required fields" do
      changeset = BronzeRaw.changeset(%BronzeRaw{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid with missing fields" do
      changeset = BronzeRaw.changeset(%BronzeRaw{}, %{})
      refute changeset.valid?
      assert length(changeset.errors) == 7
    end

    test "accepts any sheet_name without validation" do
      attrs = Map.put(@valid_attrs, :sheet_name, "New Sheet Type")
      changeset = BronzeRaw.changeset(%BronzeRaw{}, attrs)
      assert changeset.valid?
    end

    test "accepts any record_type without validation" do
      attrs = Map.put(@valid_attrs, :record_type, "Unknown Type")
      changeset = BronzeRaw.changeset(%BronzeRaw{}, attrs)
      assert changeset.valid?
    end
  end

  describe "Repo integration" do
    test "insert with valid parent ingestion" do
      create_ingestion()

      changeset = BronzeRaw.changeset(%BronzeRaw{}, @valid_attrs)
      assert {:ok, row} = Repo.insert(changeset)
      assert row.sheet_name == "Restricted Stock"
      assert row.inserted_at != nil
    end

    test "unique index rejects duplicate row_hash within same ingestion" do
      create_ingestion()

      BronzeRaw.changeset(%BronzeRaw{}, @valid_attrs) |> Repo.insert!()

      duplicate = Map.put(@valid_attrs, :id, "bronze_row_00002")

      assert {:error, changeset} =
               BronzeRaw.changeset(%BronzeRaw{}, duplicate) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).ingestion_id
    end

    test "FK constraint rejects insert with non-existent ingestion_id" do
      attrs = Map.put(@valid_attrs, :ingestion_id, "nonexistent_id00")

      assert_raise Ecto.ConstraintError, ~r/foreign_key/, fn ->
        BronzeRaw.changeset(%BronzeRaw{}, attrs) |> Repo.insert!()
      end
    end
  end
end
