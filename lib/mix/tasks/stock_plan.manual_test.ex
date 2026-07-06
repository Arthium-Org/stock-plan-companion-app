defmodule Mix.Tasks.StockPlan.ManualTest do
  @shortdoc "Verify Portfolio, Capital Gains, Schedule FA against Sample-Data XLSX"

  @moduledoc """
  Run golden-file checks that mimic manual UI verification.

  ## Examples

      mix stock_plan.manual_test
      mix stock_plan.manual_test --user 3 --account default
      mix stock_plan.manual_test --only portfolio
      mix stock_plan.manual_test --only capital_gains
      mix stock_plan.manual_test --only schedule_fa --cy 2025

  ## Options

    * `--account` — SQLite account id (default: `default`)
    * `--user`    — sample user id under `test/fixtures/sample-data/` (default: `3`)
    * `--only`    — `portfolio`, `capital_gains`, `schedule_fa`, or omit for all
    * `--cy`      — Schedule FA calendar year (default: previous calendar year)

  Exit code 0 when all checks pass, 1 otherwise.

  Prerequisite: upload the sample user's files to the dev DB first (via UI or
  CLI ingest), then run this task against the same `MIX_ENV` database.
  """

  use Mix.Task

  @switches [
    account: :string,
    user: :integer,
    only: :string,
    cy: :integer
  ]

  @impl Mix.Task
  def run(argv) do
    # StockPlan.Application boots StockPlan.FX.Sync.seed_from_bundle/0 in an
    # unawaited Task.start/1 so a real server boot is never blocked on it.
    # This one-shot CLI task calls System.halt/1 as soon as the checks
    # finish, which can kill the BEAM before that async seed task completes
    # -- non-deterministically leaving FxMonthlyRate rows missing and
    # causing spurious "not reflected in any FA row" failures unrelated to
    # any real Schedule FA / G&L reconciliation defect. seed_from_bundle/0
    # reads only the local bundled JSON (no network) and upserts
    # idempotently, so calling it synchronously here — before running the
    # checks — makes this task's result deterministic regardless of
    # scheduler timing.
    StockPlan.FX.Sync.seed_from_bundle()

    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)

    only =
      case Keyword.get(opts, :only) do
        nil ->
          :all

        "portfolio" ->
          :portfolio

        "capital_gains" ->
          :capital_gains

        "schedule_fa" ->
          :schedule_fa

        other ->
          Mix.raise(
            "invalid --only #{inspect(other)}; use portfolio, capital_gains, or schedule_fa"
          )
      end

    run_opts =
      [
        account_id: Keyword.get(opts, :account, "default"),
        user: Keyword.get(opts, :user, 3),
        only: only
      ]
      |> maybe_put_calendar_year(opts)

    case StockPlan.ManualTest.run(run_opts) do
      :ok -> System.halt(0)
      :error -> System.halt(1)
    end
  end

  defp maybe_put_calendar_year(run_opts, opts) do
    case Keyword.get(opts, :cy) do
      nil -> run_opts
      cy -> Keyword.put(run_opts, :calendar_year, cy)
    end
  end
end
