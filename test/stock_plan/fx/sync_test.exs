defmodule StockPlan.FX.SyncTest do
  use StockPlan.DataCase, async: false

  alias StockPlan.FX.Sync
  alias StockPlan.Repo
  alias StockPlan.Schema.FxMonthlyRate

  setup do
    Repo.delete_all(FxMonthlyRate)
    :ok
  end

  describe "seed_from_bundle/0" do
    test "populates fx rates from the bundled JSON with rate_date + currency_pair set" do
      assert :ok = Sync.seed_from_bundle()

      count = Repo.aggregate(FxMonthlyRate, :count)
      assert count >= 330

      rates = Repo.all(FxMonthlyRate)
      assert Enum.all?(rates, &(&1.rate_date != nil))
      assert Enum.all?(rates, &(&1.currency_pair == "USD/INR"))
    end

    test "is idempotent — calling twice leaves the row count unchanged" do
      assert :ok = Sync.seed_from_bundle()
      first_count = Repo.aggregate(FxMonthlyRate, :count)

      assert :ok = Sync.seed_from_bundle()
      second_count = Repo.aggregate(FxMonthlyRate, :count)

      assert first_count == second_count
    end
  end

  describe "fetch_remote/1" do
    test "silently falls back on a 404-shaped URL, leaving already-seeded rows intact" do
      Sync.seed_from_bundle()
      before_count = Repo.aggregate(FxMonthlyRate, :count)

      assert :ok =
               Sync.fetch_remote(
                 "https://raw.githubusercontent.com/ORG_PLACEHOLDER/REPO_PLACEHOLDER/main/priv/fx/fx_rates.json"
               )

      after_count = Repo.aggregate(FxMonthlyRate, :count)
      assert after_count == before_count
    end

    test "returns :ok without raising for nil or empty url" do
      assert :ok = Sync.fetch_remote(nil)
      assert :ok = Sync.fetch_remote("")
    end
  end
end
