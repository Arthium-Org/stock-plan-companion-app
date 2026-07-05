defmodule StockPlan.Release do
  @moduledoc """
  Release tasks for production deployment.

  Provides migrate/0 and seed_fx_if_needed/0 for use during
  application startup in production releases.

  Can also be invoked from the release CLI:

      bin/stock_plan eval "StockPlan.Release.migrate()"
      bin/stock_plan eval "StockPlan.Release.seed_fx_if_needed()"
  """

  @app :stock_plan

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed_fx_if_needed do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    StockPlan.FX.Sync.seed_from_bundle()
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.load(@app)
  end
end
