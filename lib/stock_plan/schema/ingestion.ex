defmodule StockPlan.Schema.Ingestion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:ingestion_id, :string, autogenerate: false}
  schema "stock_plan_ingestions" do
    field :account_id, :string
    field :broker, :string
    field :source_type, :string
    field :file_name, :string
    field :file_hash, :string
    field :status, :string
    field :category, :string
    field :dominant_symbol, :string
    field :bh_snapshot_json, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required ~w(ingestion_id account_id broker source_type file_name file_hash status)a
  @optional ~w(category dominant_symbol bh_snapshot_json)a

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ~w(ACTIVE ARCHIVED))
    |> validate_inclusion(:broker, ~w(ETRADE))
    |> validate_inclusion(:source_type, ~w(XLSX PDF))
    |> validate_category()
  end

  defp validate_category(changeset) do
    case get_field(changeset, :category) do
      nil -> changeset
      _ -> validate_inclusion(changeset, :category, ~w(BENEFIT_HISTORY GL_EXPANDED HOLDINGS))
    end
  end
end
