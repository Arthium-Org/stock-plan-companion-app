defmodule StockPlan.Types.SafeDecimal do
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(%Decimal{} = d), do: {:ok, d}

  def cast(value) when is_binary(value) do
    {:ok, Decimal.new(value)}
  rescue
    Decimal.Error -> :error
  end

  def cast(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  def cast(value) when is_float(value), do: {:ok, Decimal.new(Float.to_string(value))}
  def cast(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(%Decimal{} = d), do: {:ok, Decimal.to_string(d)}
  def dump(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    {:ok, Decimal.new(value)}
  rescue
    Decimal.Error -> :error
  end

  def load(_), do: :error
end
