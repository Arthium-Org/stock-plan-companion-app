defmodule StockPlan.Schema.Tranche do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "stock_plan_tranches" do
    field :origin_id, :string
    field :ingestion_id, :string
    field :vest_date, :date
    field :vest_quantity, StockPlan.Types.SafeDecimal
    field :vest_fmv, StockPlan.Types.SafeDecimal
    field :vest_fx_rate, StockPlan.Types.SafeDecimal
    field :tax_withheld_qty, StockPlan.Types.SafeDecimal
    field :net_quantity, StockPlan.Types.SafeDecimal
    field :status, :string
    field :vest_day_close, StockPlan.Types.SafeDecimal
    field :sellable_qty, StockPlan.Types.SafeDecimal
    field :cost_basis_broker, StockPlan.Types.SafeDecimal
    field :metadata_json, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(id origin_id ingestion_id vest_date status)a
  @optional ~w(vest_quantity vest_fmv vest_fx_rate vest_day_close tax_withheld_qty net_quantity sellable_qty cost_basis_broker metadata_json)a
  @statuses ~w(UNVESTED VESTED FORFEITED CANCELLED EXPIRED)

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> validate_positive(:vest_quantity)
  end

  defp validate_positive(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if value != nil and Decimal.gt?(value, Decimal.new(0)),
        do: [],
        else: [{field, "must be positive"}]
    end)
  end
end
