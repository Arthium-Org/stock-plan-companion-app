defmodule StockPlan.Schema.Origin do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "stock_plan_origins" do
    field :ingestion_id, :string
    field :account_id, :string
    field :symbol, :string
    field :plan_type, :string
    field :grant_number, :string
    field :origin_date, :date
    field :total_quantity, StockPlan.Types.SafeDecimal
    field :origin_fmv, StockPlan.Types.SafeDecimal
    field :origin_fx_rate, StockPlan.Types.SafeDecimal
    field :currency, :string
    field :status, :string
    field :metadata_json, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(id ingestion_id account_id symbol plan_type origin_date currency)a
  @optional ~w(grant_number total_quantity origin_fmv origin_fx_rate status metadata_json)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:plan_type, ~w(RSU ESPP ESOP))
    |> validate_inclusion(:currency, ~w(USD))
    |> unique_constraint([:ingestion_id, :grant_number])
  end
end
