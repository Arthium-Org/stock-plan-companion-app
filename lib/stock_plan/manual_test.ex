defmodule StockPlan.ManualTest do
  @moduledoc """
  Golden-file verification against E*Trade XLSX exports.

  Compares what the app would show in Portfolio, Tax Centre (Capital Gains,
  Schedule FA) with the reference files under `test/fixtures/sample-data/`.
  Intended as a repeatable substitute for manual UI spot-checks after code
  changes.

  ## Usage

      mix stock_plan.manual_test
      mix stock_plan.manual_test --user 3
      mix stock_plan.manual_test --account default --only portfolio
      mix stock_plan.manual_test --only capital_gains
      mix stock_plan.manual_test --only schedule_fa
      mix stock_plan.manual_test --cy 2025

  Requires the target account to already have data uploaded (same as when you
  test via the running server). Reads the configured SQLite DB for `MIX_ENV`.
  """

  alias StockPlan.ManualTest.{
    BHReconciliation,
    CapitalGains,
    Fixtures,
    Portfolio,
    Result,
    ScheduleFA
  }

  @default_account "default"
  @default_user 3

  @type opts :: [
          account_id: String.t(),
          user: pos_integer(),
          only: :all | :portfolio | :capital_gains | :schedule_fa,
          calendar_year: pos_integer()
        ]

  @spec run(keyword()) :: :ok | :error
  def run(opts \\ []) do
    account_id = Keyword.get(opts, :account_id, @default_account)
    user_id = Keyword.get(opts, :user, @default_user)
    only = Keyword.get(opts, :only, :all)
    calendar_year = Keyword.get(opts, :calendar_year, Date.utc_today().year - 1)

    fixtures = Fixtures.fetch!(user_id)

    Mix.Task.run("app.start")
    Logger.configure(level: :warning)

    IO.puts("""
    ═══════════════════════════════════════════════════════════════
      Stock Plan Manual Test
      account=#{account_id}  user=#{user_id} (#{fixtures.label})
      checks=#{only_label(only)}  schedule_fa_cy=#{calendar_year}
    ═══════════════════════════════════════════════════════════════
    """)

    results =
      []
      |> maybe_run_portfolio(only, account_id, fixtures.holdings_path)
      |> maybe_run_capital_gains(only, account_id, fixtures)
      |> maybe_run_schedule_fa(only, account_id, fixtures, calendar_year)
      |> maybe_run_bh_reconciliation(only, account_id)

    print_results(results)

    if Result.all_pass?(results) do
      IO.puts("\n✓ ALL CHECKS PASSED\n")
      :ok
    else
      IO.puts("\n✗ CHECKS FAILED — see details above\n")
      :error
    end
  end

  defp maybe_run_portfolio(results, only, account_id, holdings_path)
       when only in [:all, :portfolio] do
    results ++ [Portfolio.verify(account_id, holdings_path)]
  end

  defp maybe_run_portfolio(results, _only, _account_id, _holdings_path), do: results

  defp maybe_run_capital_gains(results, only, account_id, fixtures)
       when only in [:all, :capital_gains] do
    results ++ CapitalGains.verify(account_id, fixtures.gl_paths, fixtures.capital_gains_fys)
  end

  defp maybe_run_capital_gains(results, _only, _account_id, _fixtures), do: results

  defp maybe_run_schedule_fa(results, only, account_id, fixtures, calendar_year)
       when only in [:all, :schedule_fa] do
    results ++ ScheduleFA.verify(account_id, fixtures.gl_paths, calendar_year)
  end

  defp maybe_run_schedule_fa(results, _only, _account_id, _fixtures, _calendar_year),
    do: results

  defp maybe_run_bh_reconciliation(results, only, account_id)
       when only in [:all, :capital_gains] do
    results ++ [BHReconciliation.verify(account_id)]
  end

  defp maybe_run_bh_reconciliation(results, _only, _account_id), do: results

  defp print_results(results) do
    Enum.each(results, fn result ->
      icon = if result.status == :pass, do: "✓", else: "✗"

      IO.puts("#{icon} #{result.section}")
      IO.puts("  #{result.summary}")

      Enum.each(result.details, fn line ->
        IO.puts("  #{line}")
      end)

      Enum.each(result.failures, fn line ->
        IO.puts("  FAIL: #{line}")
      end)

      IO.puts("")
    end)
  end

  defp only_label(:all), do: "portfolio + capital_gains + bh_reconciliation + schedule_fa"
  defp only_label(:portfolio), do: "portfolio"
  defp only_label(:capital_gains), do: "capital_gains + bh_reconciliation"
  defp only_label(:schedule_fa), do: "schedule_fa"
end
