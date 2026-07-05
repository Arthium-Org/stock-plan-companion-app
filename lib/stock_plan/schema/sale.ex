defmodule StockPlan.Schema.Sale do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "stock_plan_sales" do
    field :ingestion_id, :string
    field :origin_id, :string
    field :account_id, :string
    field :symbol, :string
    field :sale_date, :date
    field :total_quantity, StockPlan.Types.SafeDecimal
    field :sale_price, StockPlan.Types.SafeDecimal
    field :sale_fx_rate, StockPlan.Types.SafeDecimal
    field :proceeds, StockPlan.Types.SafeDecimal
    field :metadata_json, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(id ingestion_id origin_id account_id symbol sale_date total_quantity)a
  @optional ~w(sale_price sale_fx_rate proceeds metadata_json)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_positive(:total_quantity)
  end

  defp validate_positive(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if value != nil and Decimal.gt?(value, Decimal.new(0)),
        do: [],
        else: [{field, "must be positive"}]
    end)
  end
end
