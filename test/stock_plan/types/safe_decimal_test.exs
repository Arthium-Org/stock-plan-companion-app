defmodule StockPlan.Types.SafeDecimalTest do
  use ExUnit.Case, async: true

  alias StockPlan.Types.SafeDecimal

  describe "cast/1" do
    test "casts valid string" do
      assert {:ok, %Decimal{}} = SafeDecimal.cast("123.45")
      assert {:ok, d} = SafeDecimal.cast("0.001")
      assert Decimal.equal?(d, Decimal.new("0.001"))
    end

    test "casts Decimal unchanged" do
      d = Decimal.new("99.99")
      assert {:ok, ^d} = SafeDecimal.cast(d)
    end

    test "casts integer" do
      assert {:ok, d} = SafeDecimal.cast(42)
      assert Decimal.equal?(d, Decimal.new(42))
    end

    test "casts float via string to avoid precision loss" do
      assert {:ok, d} = SafeDecimal.cast(1.1)
      assert Decimal.equal?(d, Decimal.new("1.1"))
    end

    test "casts nil" do
      assert {:ok, nil} = SafeDecimal.cast(nil)
    end

    test "rejects invalid string" do
      assert :error = SafeDecimal.cast("abc")
      assert :error = SafeDecimal.cast("")
    end

    test "rejects non-numeric types" do
      assert :error = SafeDecimal.cast([1, 2])
      assert :error = SafeDecimal.cast(%{a: 1})
      assert :error = SafeDecimal.cast({:ok, 1})
    end
  end

  describe "dump/1" do
    test "dumps Decimal to string" do
      assert {:ok, "123.45"} = SafeDecimal.dump(Decimal.new("123.45"))
    end

    test "dumps nil" do
      assert {:ok, nil} = SafeDecimal.dump(nil)
    end

    test "rejects non-Decimal" do
      assert :error = SafeDecimal.dump("123")
      assert :error = SafeDecimal.dump(42)
    end
  end

  describe "load/1" do
    test "loads string to Decimal" do
      assert {:ok, d} = SafeDecimal.load("123.45")
      assert Decimal.equal?(d, Decimal.new("123.45"))
    end

    test "loads nil" do
      assert {:ok, nil} = SafeDecimal.load(nil)
    end

    test "rejects invalid string" do
      assert :error = SafeDecimal.load("abc")
    end

    test "rejects non-string" do
      assert :error = SafeDecimal.load(42)
    end
  end

  describe "round-trip" do
    test "cast -> dump -> load preserves value" do
      original = "72.36"
      {:ok, casted} = SafeDecimal.cast(original)
      {:ok, dumped} = SafeDecimal.dump(casted)
      {:ok, loaded} = SafeDecimal.load(dumped)
      assert Decimal.equal?(casted, loaded)
    end

    test "round-trip with high precision" do
      original = "0.000000001"
      {:ok, casted} = SafeDecimal.cast(original)
      {:ok, dumped} = SafeDecimal.dump(casted)
      {:ok, loaded} = SafeDecimal.load(dumped)
      assert Decimal.equal?(casted, loaded)
    end
  end
end
