defmodule StockPlan.Schema.Holding do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "stock_plan_holdings" do
    field :ingestion_id, :string
    field :account_id, :string
    field :symbol, :string
    field :plan_type, :string
    field :grant_number, :string
    field :grant_date, :date
    field :granted_qty, StockPlan.Types.SafeDecimal
    field :vest_date, :date
    field :vest_period, :integer
    field :vested_qty, StockPlan.Types.SafeDecimal
    field :released_qty, StockPlan.Types.SafeDecimal
    field :sellable_qty, StockPlan.Types.SafeDecimal
    field :blocked_qty, StockPlan.Types.SafeDecimal
    field :cost_basis, StockPlan.Types.SafeDecimal
    field :purchase_price, StockPlan.Types.SafeDecimal
    field :grant_fmv, StockPlan.Types.SafeDecimal
    field :status, :string
    field :vest_fx_rate, StockPlan.Types.SafeDecimal
    field :metadata_json, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(id ingestion_id account_id plan_type status)a
  @optional ~w(symbol grant_number grant_date granted_qty vest_date vest_period vested_qty released_qty sellable_qty blocked_qty cost_basis purchase_price grant_fmv vest_fx_rate metadata_json)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:plan_type, ~w(RSU ESPP))
    |> validate_inclusion(:status, ~w(VESTED UNVESTED))
  end
end
