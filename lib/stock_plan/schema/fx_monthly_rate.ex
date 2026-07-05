defmodule StockPlan.Schema.FxMonthlyRate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "stock_plan_fx_monthly_rates" do
    field :rate_date, :date
    field :year_month, :string
    field :currency_pair, :string
    field :tt_buying_rate_month_end, StockPlan.Types.SafeDecimal
    field :standard_rate_month_end, StockPlan.Types.SafeDecimal
    field :standard_rate_month_avg, StockPlan.Types.SafeDecimal
    field :source, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(id rate_date year_month currency_pair)a
  @optional ~w(tt_buying_rate_month_end standard_rate_month_end standard_rate_month_avg source)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint([:year_month, :currency_pair])
  end
end
