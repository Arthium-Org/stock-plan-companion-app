defmodule StockPlan.IDTest do
  use ExUnit.Case, async: true

  alias StockPlan.ID

  test "generates 16-character string" do
    id = ID.generate()
    assert String.length(id) == 16
  end

  test "matches lowercase hex format" do
    id = ID.generate()
    assert id =~ ~r/^[0-9a-f]{16}$/
  end

  test "generates unique values" do
    ids = for _ <- 1..1000, do: ID.generate()
    assert length(Enum.uniq(ids)) == 1000
  end
end
