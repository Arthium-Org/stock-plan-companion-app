defmodule StockPlan.Ingestion.BronzeWriterTest do
  use StockPlan.DataCase, async: false

  @moduletag :requires_fixtures

  alias StockPlan.Ingestion.{BronzeWriter, BronzeRow, XlsxParser}
  alias StockPlan.Schema.BronzeRaw
  alias StockPlan.{Repo, TestFixtures}

  defp make_row(sheet, record_type, index, parent_index \\ nil) do
    json = XlsxParser.row_to_json(["Record Type", "Data"], [record_type, "val_#{index}"])

    %BronzeRow{
      sheet_name: sheet,
      record_type: record_type,
      row_index: index,
      parent_index: parent_index,
      raw_row_json: json,
      row_hash: XlsxParser.compute_hash("#{sheet}:#{index}:#{json}")
    }
  end

  describe "basic operations" do
    test "write empty list returns zeros without DB call" do
      assert {:ok, %{inserted: 0, skipped: 0}} = BronzeWriter.write("anything", [])
    end

    test "write 3 rows inserts all" do
      ing = TestFixtures.create_ingestion()

      rows = [
        make_row("Restricted Stock", "Grant", 0),
        make_row("Restricted Stock", "Event", 1, 0),
        make_row("Restricted Stock", "Event", 2, 0)
      ]

      assert {:ok, %{inserted: 3, skipped: 0}} = BronzeWriter.write(ing.ingestion_id, rows)
    end

    test "written rows exist in DB with correct count" do
      ing = TestFixtures.create_ingestion()

      rows = [
        make_row("ESPP", "Purchase", 0),
        make_row("ESPP", "Event", 1, 0),
        make_row("ESPP", "Event", 2, 0)
      ]

      BronzeWriter.write(ing.ingestion_id, rows)
      assert Repo.aggregate(BronzeRaw, :count) == 3
    end

    test "written rows have correct ingestion_id" do
      ing = TestFixtures.create_ingestion()
      rows = [make_row("Options", "Grant", 0)]

      BronzeWriter.write(ing.ingestion_id, rows)
      [db_row] = Repo.all(BronzeRaw)
      assert db_row.ingestion_id == ing.ingestion_id
    end

    test "written rows have generated 16-char hex IDs" do
      ing = TestFixtures.create_ingestion()
      rows = [make_row("ESPP", "Purchase", 0)]

      BronzeWriter.write(ing.ingestion_id, rows)
      [db_row] = Repo.all(BronzeRaw)
      assert db_row.id =~ ~r/^[0-9a-f]{16}$/
    end

    test "written rows have timestamps" do
      ing = TestFixtures.create_ingestion()
      rows = [make_row("ESPP", "Purchase", 0)]

      BronzeWriter.write(ing.ingestion_id, rows)
      [db_row] = Repo.all(BronzeRaw)
      assert db_row.inserted_at != nil
      assert db_row.updated_at != nil
    end

    test "parent_index persisted correctly" do
      ing = TestFixtures.create_ingestion()

      rows = [
        make_row("Restricted Stock", "Grant", 0),
        make_row("Restricted Stock", "Event", 1, 0),
        make_row("Restricted Stock", "Vest Schedule", 2, 0)
      ]

      BronzeWriter.write(ing.ingestion_id, rows)
      db_rows = Repo.all(BronzeRaw) |> Enum.sort_by(& &1.row_index)

      assert Enum.at(db_rows, 0).parent_index == nil
      assert Enum.at(db_rows, 1).parent_index == 0
      assert Enum.at(db_rows, 2).parent_index == 0
    end
  end

  describe "dedup" do
    test "writing same rows twice — second call skips all" do
      ing = TestFixtures.create_ingestion()

      rows = [
        make_row("ESPP", "Purchase", 0),
        make_row("ESPP", "Event", 1, 0),
        make_row("ESPP", "Event", 2, 0)
      ]

      assert {:ok, %{inserted: 3, skipped: 0}} = BronzeWriter.write(ing.ingestion_id, rows)
      assert {:ok, %{inserted: 0, skipped: 3}} = BronzeWriter.write(ing.ingestion_id, rows)
    end

    test "total DB rows unchanged after duplicate write" do
      ing = TestFixtures.create_ingestion()
      rows = [make_row("Options", "Grant", 0), make_row("Options", "Event", 1, 0)]

      BronzeWriter.write(ing.ingestion_id, rows)
      BronzeWriter.write(ing.ingestion_id, rows)
      assert Repo.aggregate(BronzeRaw, :count) == 2
    end

    test "inserted + skipped = input length" do
      ing = TestFixtures.create_ingestion()
      rows = [make_row("ESPP", "Purchase", 0), make_row("ESPP", "Event", 1, 0)]

      {:ok, counts} = BronzeWriter.write(ing.ingestion_id, rows)
      assert counts.inserted + counts.skipped == length(rows)
    end

    test "same row_hash in different ingestion both insert" do
      ing1 = TestFixtures.create_ingestion()
      ing2 = TestFixtures.create_ingestion()
      rows = [make_row("ESPP", "Purchase", 0)]

      assert {:ok, %{inserted: 1, skipped: 0}} = BronzeWriter.write(ing1.ingestion_id, rows)
      assert {:ok, %{inserted: 1, skipped: 0}} = BronzeWriter.write(ing2.ingestion_id, rows)
    end
  end

  describe "ingestion validation" do
    test "non-existent ingestion_id returns error" do
      rows = [make_row("ESPP", "Purchase", 0)]
      assert {:error, :ingestion_not_found} = BronzeWriter.write("nonexistent_0000", rows)
    end

    test "archived ingestion returns error" do
      ing = TestFixtures.create_ingestion(%{status: "ARCHIVED"})
      rows = [make_row("ESPP", "Purchase", 0)]
      assert {:error, :ingestion_not_active} = BronzeWriter.write(ing.ingestion_id, rows)
    end

    test "active ingestion proceeds" do
      ing = TestFixtures.create_ingestion(%{status: "ACTIVE"})
      rows = [make_row("ESPP", "Purchase", 0)]
      assert {:ok, %{inserted: 1, skipped: 0}} = BronzeWriter.write(ing.ingestion_id, rows)
    end
  end

  describe "end-to-end pipeline (M3 → M4)" do
    @sample1 "test/fixtures/sample-data/su1/sample-Etrade-BenefitHistory.xlsx"

    @tag :integration
    test "parse XLSX and write to bronze" do
      ing = TestFixtures.create_ingestion()
      {:ok, parsed_rows, _warnings} = XlsxParser.parse(@sample1)

      assert {:ok, %{inserted: inserted, skipped: 0}} =
               BronzeWriter.write(ing.ingestion_id, parsed_rows)

      assert inserted == length(parsed_rows)
      assert Repo.aggregate(BronzeRaw, :count) == inserted

      IO.puts("  Pipeline: #{inserted} rows written to bronze")
    end

    @tag :integration
    test "re-write same file is idempotent" do
      ing = TestFixtures.create_ingestion()
      {:ok, parsed_rows, _} = XlsxParser.parse(@sample1)

      BronzeWriter.write(ing.ingestion_id, parsed_rows)

      assert {:ok, %{inserted: 0, skipped: skipped}} =
               BronzeWriter.write(ing.ingestion_id, parsed_rows)

      assert skipped == length(parsed_rows)
    end

    @tag :integration
    test "sample row from DB has valid data" do
      ing = TestFixtures.create_ingestion()
      {:ok, parsed_rows, _} = XlsxParser.parse(@sample1)
      BronzeWriter.write(ing.ingestion_id, parsed_rows)

      sample = Repo.all(BronzeRaw) |> hd()
      assert sample.sheet_name in ["ESPP", "Restricted Stock", "Options"]
      assert {:ok, _} = Jason.decode(sample.raw_row_json)
    end

    @tag :integration
    test "parent rows have nil parent_index, children have set parent_index" do
      ing = TestFixtures.create_ingestion()
      {:ok, parsed_rows, _} = XlsxParser.parse(@sample1)
      BronzeWriter.write(ing.ingestion_id, parsed_rows)

      db_rows = Repo.all(BronzeRaw)
      parents = Enum.filter(db_rows, &(&1.record_type in ["Grant", "Purchase"]))
      children = Enum.filter(db_rows, &(&1.record_type in ["Event", "Vest Schedule"]))

      assert Enum.all?(parents, &(&1.parent_index == nil))
      assert Enum.all?(children, &(&1.parent_index != nil))
    end
  end
end
