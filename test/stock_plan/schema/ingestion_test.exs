defmodule StockPlan.Schema.IngestionTest do
  use StockPlan.DataCase, async: true

  alias StockPlan.Schema.Ingestion
  alias StockPlan.Repo

  @valid_attrs %{
    ingestion_id: "a1b2c3d4e5f67890",
    account_id: "default",
    broker: "ETRADE",
    source_type: "XLSX",
    file_name: "BenefitHistory.xlsx",
    file_hash: "abc123def456",
    status: "ACTIVE"
  }

  describe "changeset/2" do
    test "valid with all required fields" do
      changeset = Ingestion.changeset(%Ingestion{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid with missing required fields" do
      changeset = Ingestion.changeset(%Ingestion{}, %{})
      refute changeset.valid?
      assert length(changeset.errors) == 7
    end

    test "invalid with bad status" do
      attrs = Map.put(@valid_attrs, :status, "INVALID")
      changeset = Ingestion.changeset(%Ingestion{}, attrs)
      refute changeset.valid?

      assert {:status, _} =
               hd(
                 Keyword.get_values(changeset.errors, :status)
                 |> List.wrap()
                 |> Enum.map(&{:status, &1})
               )
    end

    test "invalid with bad broker" do
      attrs = Map.put(@valid_attrs, :broker, "SCHWAB")
      changeset = Ingestion.changeset(%Ingestion{}, attrs)
      refute changeset.valid?
    end

    test "invalid with bad source_type" do
      attrs = Map.put(@valid_attrs, :source_type, "CSV")
      changeset = Ingestion.changeset(%Ingestion{}, attrs)
      refute changeset.valid?
    end
  end

  describe "Repo integration" do
    test "insert and read back" do
      changeset = Ingestion.changeset(%Ingestion{}, @valid_attrs)
      assert {:ok, inserted} = Repo.insert(changeset)
      assert inserted.ingestion_id == "a1b2c3d4e5f67890"
      assert inserted.inserted_at != nil
      assert inserted.updated_at != nil

      fetched = Repo.get(Ingestion, "a1b2c3d4e5f67890")
      assert fetched.account_id == "default"
      assert fetched.status == "ACTIVE"
    end
  end
end
