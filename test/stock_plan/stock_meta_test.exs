defmodule StockPlan.StockMetaTest do
  use ExUnit.Case, async: false

  alias StockPlan.StockMeta

  setup do
    StockMeta.__clear_cache__()
    on_exit(fn -> StockMeta.__clear_cache__() end)
    :ok
  end

  describe "get/1" do
    test "returns metadata for known symbol" do
      assert {:ok, meta} = StockMeta.get("ADBE")
      assert meta["legal_name"] == "Adobe Inc."
      assert meta["country_code"] == "2"
      assert meta["zip"] == "95110"
    end

    test "returns {:error, :unknown_symbol} for unknown symbol" do
      assert {:error, :unknown_symbol} = StockMeta.get("NOPE")
    end
  end

  describe "get!/1" do
    test "returns metadata for known symbol" do
      assert %{"legal_name" => "Adobe Inc."} = StockMeta.get!("ADBE")
    end

    test "raises UnknownSymbolError for unknown symbol" do
      assert_raise StockMeta.UnknownSymbolError, fn ->
        StockMeta.get!("NOPE")
      end
    end
  end

  describe "known?/1" do
    test "true for known symbols" do
      assert StockMeta.known?("ADBE")
      assert StockMeta.known?("CRM")
    end

    test "false for unknown symbols" do
      refute StockMeta.known?("NOPE")
    end
  end

  describe "all/0" do
    test "returns full map keyed by symbol" do
      all = StockMeta.all()
      assert is_map(all)
      assert Map.has_key?(all, "ADBE")
    end
  end

  describe "caching" do
    test "second call hits persistent_term cache" do
      # First call seeds cache
      StockMeta.__clear_cache__()
      assert :persistent_term.get({StockMeta, :meta}, :undefined) == :undefined
      _ = StockMeta.all()
      assert is_map(:persistent_term.get({StockMeta, :meta}))
    end
  end
end
