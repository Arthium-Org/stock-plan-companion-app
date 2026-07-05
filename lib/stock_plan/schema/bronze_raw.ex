defmodule StockPlan.Schema.BronzeRaw do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "stock_plan_bronze_raw" do
    field :ingestion_id, :string
    field :sheet_name, :string
    field :record_type, :string
    field :row_index, :integer
    field :parent_index, :integer
    field :raw_row_json, :string
    field :row_hash, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(id ingestion_id sheet_name record_type row_index raw_row_json row_hash)a
  @optional ~w(parent_index)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint([:ingestion_id, :row_hash])
  end
end
