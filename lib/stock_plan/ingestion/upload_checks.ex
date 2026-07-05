defmodule StockPlan.Ingestion.UploadChecks do
  @moduledoc """
  Post-upload diagnostics — checks what data is missing and produces
  actionable nudges plus feature readiness status for the user.
  """

  alias StockPlan.Repo
  alias StockPlan.Schema.{Sale, SaleAllocation, Ingestion}
  alias StockPlan.Ingestions
  alias StockPlan.Tax.ScheduleFA
  import Ecto.Query

  @type severity :: :error | :warning | :info
  @type status :: :ready | :limited | :blocked | :not_applicable

  @type nudge :: %{
          severity: severity(),
          code: atom(),
          reason: String.t(),
          impact: String.t(),
          action: String.t()
        }

  @type readiness :: %{
          portfolio: status(),
          vesting_schedule: status(),
          schedule_fa: status(),
          capital_gains: status(),
          schedule_fsi: status(),
          sell_advisor: status()
        }

  @doc """
  Run all upload diagnostics for an account.
  Returns `%{nudges: [nudge], readiness: readiness}`.
  """
  @spec check(String.t()) :: %{nudges: [nudge()], readiness: readiness()}
  def check(account_id) do
    has_bh = Ingestions.any_active_bh?(account_id)
    has_holdings = Ingestions.has_active_holdings?(account_id)

    snapshots = if has_bh, do: load_bh_snapshots(account_id), else: []
    bh = aggregate_snapshots(snapshots)

    has_current_shares = bh.vested_unsold_origins > 0 or bh.unvested > 0

    gl_coverage =
      if has_bh,
        do: compute_gl_coverage_gaps(account_id),
        else: %{uncovered_cy1: [], uncovered_cy: []}

    symbol_nudges = check_symbol_consistency(account_id, bh_symbols_with_unsold(snapshots))

    nudges =
      []
      |> maybe_add_no_bh(has_bh)
      |> maybe_add_no_holdings(has_bh, has_current_shares, has_holdings)
      |> add_gl_coverage_nudges(gl_coverage)
      |> Kernel.++(symbol_nudges)

    cy1_year = Date.utc_today().year - 1
    fa_readiness = schedule_fa_readiness(account_id, cy1_year)

    readiness =
      build_readiness(has_bh, has_current_shares, has_holdings, gl_coverage, fa_readiness)

    %{nudges: nudges, readiness: readiness}
  end

  @doc """
  Produce per-symbol nudges based on BH vs Holdings symbol coverage.
  - :bh_without_holdings (:info) — BH for SYM with unsold shares but no Holdings uploaded
  - :holdings_without_bh (:warning) — Holdings for SYM but no BH (likely missing upload)

  `bh_symbols_with_unsold` is a MapSet of symbols known to have unsold vested or unvested shares
  per BH snapshot. `:bh_without_holdings` is suppressed for fully-sold symbols.
  """
  @spec check_symbol_consistency(String.t(), MapSet.t()) :: [map()]
  def check_symbol_consistency(account_id, bh_symbols_with_unsold \\ MapSet.new()) do
    bh = MapSet.new(Ingestions.active_bh_symbols(account_id))
    hold = MapSet.new(Ingestions.active_holdings_symbols(account_id))

    bh_only = MapSet.difference(bh, hold) |> Enum.sort()
    hold_only = MapSet.difference(hold, bh) |> Enum.sort()

    Enum.flat_map(bh_only, fn s ->
      if MapSet.member?(bh_symbols_with_unsold, s) do
        [
          %{
            severity: :info,
            code: :bh_without_holdings,
            reason: "BH for #{s} but no Holdings file uploaded",
            impact:
              "Portfolio + Sell Advisor for #{s} may not be accurate without Holdings data.",
            action: "Upload Holdings (ByBenefitType) for #{s} from E*Trade"
          }
        ]
      else
        []
      end
    end) ++
      Enum.map(hold_only, fn s ->
        %{
          severity: :warning,
          code: :holdings_without_bh,
          reason: "Holdings for #{s} but no BH file uploaded",
          impact:
            "Tax features (Schedule FA, Capital Gains, Schedule FSI) for #{s} can't be computed without BH",
          action: "Upload Benefit History for #{s}"
        }
      end)
  end

  @doc """
  FA readiness for a given calendar year, using M26 P1/P2 gates.
  Used by Upload page (default CY-1) and Tax Centre (selected year).

      :blocked — no BH, P1 fails (G&L missing), or P2 fails (Holdings needed)
      :limited  — P1+P2 pass but BH shows current unsold shares and no Holdings
      :ready    — all checks pass
  """
  @spec schedule_fa_readiness(String.t(), integer()) :: status()
  def schedule_fa_readiness(account_id, calendar_year) do
    has_bh = Ingestions.any_active_bh?(account_id)

    if not has_bh do
      :blocked
    else
      case ScheduleFA.pre_check(account_id, calendar_year) do
        {:error, _} ->
          :blocked

        :ok ->
          has_holdings = Ingestions.has_active_holdings?(account_id)
          snapshots = load_bh_snapshots(account_id)
          bh = aggregate_snapshots(snapshots)
          has_current_shares = bh.vested_unsold_origins > 0 or bh.unvested > 0

          if has_current_shares and not has_holdings, do: :limited, else: :ready
      end
    end
  end

  # ============================================================
  # BH Snapshot Helpers
  # ============================================================

  defp load_bh_snapshots(account_id) do
    Repo.all(
      from i in Ingestion,
        where:
          i.account_id == ^account_id and
            i.status == "ACTIVE" and
            i.category == "BENEFIT_HISTORY" and
            not is_nil(i.bh_snapshot_json),
        select: {i.dominant_symbol, i.bh_snapshot_json}
    )
    |> Enum.map(fn {symbol, json} -> {symbol, Jason.decode!(json)} end)
  end

  defp aggregate_snapshots(snapshots) do
    jsons = Enum.map(snapshots, &elem(&1, 1))

    %{
      vested_unsold_origins: Enum.sum(Enum.map(jsons, & &1["vested_unsold_origin_count"])),
      unvested: Enum.sum(Enum.map(jsons, & &1["unvested_count"])),
      sale_years: jsons |> Enum.flat_map(& &1["sale_years"]) |> Enum.uniq() |> Enum.sort()
    }
  end

  defp bh_symbols_with_unsold(snapshots) do
    snapshots
    |> Enum.filter(fn {_, json} ->
      json["vested_unsold_origin_count"] > 0 or json["unvested_count"] > 0
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  # ============================================================
  # G&L Coverage Gap Check
  # ============================================================

  defp compute_gl_coverage_gaps(account_id) do
    today = Date.utc_today()
    cy1_start = Date.new!(today.year - 1, 1, 1)
    cy1_end = Date.new!(today.year - 1, 12, 31)
    cy_start = Date.new!(today.year, 1, 1)

    bh_sales =
      Repo.all(
        from s in Sale,
          where:
            s.account_id == ^account_id and
              s.sale_date >= ^cy1_start and
              s.sale_date <= ^today,
          select: {s.id, s.sale_date}
      )

    if bh_sales == [] do
      %{uncovered_cy1: [], uncovered_cy: []}
    else
      sale_ids = Enum.map(bh_sales, &elem(&1, 0))

      covered_ids =
        Repo.all(
          from a in SaleAllocation,
            where: a.sale_id in ^sale_ids and not is_nil(a.sale_price),
            distinct: true,
            select: a.sale_id
        )
        |> MapSet.new()

      uncovered = Enum.reject(bh_sales, fn {id, _} -> MapSet.member?(covered_ids, id) end)

      uncovered_cy1 =
        for {id, d} <- uncovered,
            Date.compare(d, cy1_start) != :lt and Date.compare(d, cy1_end) != :gt,
            do: {id, d}

      uncovered_cy =
        for {id, d} <- uncovered,
            Date.compare(d, cy_start) != :lt,
            do: {id, d}

      %{uncovered_cy1: uncovered_cy1, uncovered_cy: uncovered_cy}
    end
  end

  # ============================================================
  # Nudge Builders
  # ============================================================

  defp maybe_add_no_bh(nudges, false) do
    [
      %{
        severity: :error,
        code: :no_benefit_history,
        reason: "No Benefit History uploaded",
        impact: "All features require Benefit History data",
        action: "Download Benefit History from E*Trade and upload"
      }
      | nudges
    ]
  end

  defp maybe_add_no_bh(nudges, true), do: nudges

  defp maybe_add_no_holdings(nudges, false, _has_current_shares, _has_holdings), do: nudges
  defp maybe_add_no_holdings(nudges, true, _has_current_shares, true), do: nudges
  # No current shares — Holdings upload wouldn't show anything useful
  defp maybe_add_no_holdings(nudges, true, false, false), do: nudges

  defp maybe_add_no_holdings(nudges, true, true, false) do
    [
      %{
        severity: :error,
        code: :no_holdings,
        reason: "Holdings not uploaded",
        impact: "Portfolio cannot be shown without Holdings data.",
        action: "Download ByBenefitType (expanded) from E*Trade and upload"
      }
      | nudges
    ]
  end

  defp add_gl_coverage_nudges(nudges, %{uncovered_cy1: cy1, uncovered_cy: cy}) do
    nudges
    |> add_cy1_gl_nudge(cy1)
    |> add_cy_gl_nudge(cy)
  end

  defp add_cy1_gl_nudge(nudges, []), do: nudges

  defp add_cy1_gl_nudge(nudges, uncovered) do
    dates = Enum.map(uncovered, &elem(&1, 1)) |> Enum.sort(Date)
    year = hd(dates).year
    earliest = hd(dates)
    latest = List.last(dates)

    [
      %{
        severity: :warning,
        code: :no_gl_for_dates,
        reason: "G&L missing for #{length(uncovered)} sale lot(s) in #{year}",
        impact: "Capital Gains, Schedule FSI, and Schedule FA for #{year} cannot be computed",
        action: "Download G&L Expanded from E*Trade covering #{earliest} to #{latest}"
      }
      | nudges
    ]
  end

  defp add_cy_gl_nudge(nudges, []), do: nudges

  defp add_cy_gl_nudge(nudges, uncovered) do
    dates = Enum.map(uncovered, &elem(&1, 1)) |> Enum.sort(Date)
    year = hd(dates).year
    earliest = hd(dates)
    latest = List.last(dates)

    [
      %{
        severity: :info,
        code: :no_gl_for_dates,
        reason: "G&L not yet uploaded for #{length(uncovered)} sale lot(s) in #{year}",
        impact: "Capital Gains for #{year} cannot be computed yet",
        action: "Download G&L Expanded from E*Trade covering #{earliest} to #{latest}"
      }
      | nudges
    ]
  end

  # ============================================================
  # Readiness
  # ============================================================

  defp build_readiness(has_bh, has_current_shares, has_holdings, gl_coverage, fa_readiness) do
    %{
      portfolio: readiness_portfolio(has_bh, has_current_shares, has_holdings),
      vesting_schedule: readiness_vesting(has_bh),
      schedule_fa: fa_readiness,
      capital_gains: readiness_capital_gains(has_bh, gl_coverage),
      schedule_fsi: readiness_capital_gains(has_bh, gl_coverage),
      sell_advisor: readiness_sell_advisor(has_bh, has_holdings)
    }
  end

  defp readiness_portfolio(false, _has_current_shares, _has_holdings), do: :blocked
  defp readiness_portfolio(true, false, _has_holdings), do: :not_applicable
  defp readiness_portfolio(true, true, false), do: :blocked
  defp readiness_portfolio(true, true, true), do: :ready

  defp readiness_vesting(false), do: :blocked
  defp readiness_vesting(true), do: :ready

  defp readiness_capital_gains(false, _gl_coverage), do: :blocked
  defp readiness_capital_gains(true, %{uncovered_cy1: [_ | _]}), do: :blocked
  defp readiness_capital_gains(true, _gl_coverage), do: :ready

  defp readiness_sell_advisor(false, _), do: :blocked
  defp readiness_sell_advisor(true, false), do: :limited
  defp readiness_sell_advisor(true, true), do: :ready
end
