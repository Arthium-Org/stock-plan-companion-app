defmodule StockPlan.Schema.Exercise do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "stock_plan_exercises" do
    field :tranche_id, :string
    field :ingestion_id, :string
    field :exercise_date, :date
    field :exercise_quantity, StockPlan.Types.SafeDecimal
    field :exercise_fmv, StockPlan.Types.SafeDecimal
    field :exercise_fx_rate, StockPlan.Types.SafeDecimal
    field :exercise_price, StockPlan.Types.SafeDecimal
    field :tax_withheld_qty, StockPlan.Types.SafeDecimal
    field :net_quantity, StockPlan.Types.SafeDecimal
    field :metadata_json, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(id tranche_id ingestion_id exercise_date exercise_quantity exercise_price)a
  @optional ~w(exercise_fmv exercise_fx_rate tax_withheld_qty net_quantity metadata_json)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_positive(:exercise_quantity)
    |> validate_positive(:exercise_price)
  end

  defp validate_positive(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if value != nil and Decimal.gt?(value, Decimal.new(0)),
        do: [],
        else: [{field, "must be positive"}]
    end)
  end
end
