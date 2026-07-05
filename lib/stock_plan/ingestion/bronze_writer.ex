defmodule StockPlan.Ingestion.BronzeWriter do
  @moduledoc false

  alias StockPlan.Repo
  alias StockPlan.Schema.{BronzeRaw, Ingestion}
  alias StockPlan.Ingestion.BronzeRow
  alias StockPlan.ID

  @spec write(String.t(), [BronzeRow.t()]) ::
          {:ok, %{inserted: non_neg_integer(), skipped: non_neg_integer()}}
          | {:error, atom()}
  def write(_ingestion_id, []), do: {:ok, %{inserted: 0, skipped: 0}}

  def write(ingestion_id, bronze_rows) do
    with {:ok, _ing} <- validate_active_ingestion(ingestion_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      rows =
        Enum.map(bronze_rows, fn row ->
          %{
            id: ID.generate(),
            ingestion_id: ingestion_id,
            sheet_name: row.sheet_name,
            record_type: row.record_type,
            row_index: row.row_index,
            parent_index: row.parent_index,
            raw_row_json: row.raw_row_json,
            row_hash: row.row_hash,
            inserted_at: now,
            updated_at: now
          }
        end)

      {inserted, _} =
        Repo.insert_all(BronzeRaw, rows,
          on_conflict: :nothing,
          conflict_target: [:ingestion_id, :row_hash]
        )

      skipped = length(bronze_rows) - inserted
      {:ok, %{inserted: inserted, skipped: skipped}}
    end
  end

  defp validate_active_ingestion(ingestion_id) do
    case Repo.get(Ingestion, ingestion_id) do
      nil -> {:error, :ingestion_not_found}
      %{status: "ACTIVE"} = ing -> {:ok, ing}
      _ -> {:error, :ingestion_not_active}
    end
  end
end
