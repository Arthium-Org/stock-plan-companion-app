defmodule StockPlan.Schema.SaleAllocation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "stock_plan_sale_allocations" do
    field :sale_id, :string
    field :tranche_id, :string
    field :exercise_id, :string
    field :quantity, StockPlan.Types.SafeDecimal
    field :sale_price, StockPlan.Types.SafeDecimal
    field :order_number, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(id sale_id tranche_id quantity)a
  @optional ~w(exercise_id sale_price order_number)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_positive(:quantity)
  end

  defp validate_positive(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if value != nil and Decimal.gt?(value, Decimal.new(0)),
        do: [],
        else: [{field, "must be positive"}]
    end)
  end
end
