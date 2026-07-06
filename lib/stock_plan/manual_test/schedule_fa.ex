defmodule StockPlan.ManualTest.ScheduleFA do
  @moduledoc false

  alias StockPlan.FX
  alias StockPlan.Ingestion.{GlParser, ValueNormalizer}
  alias StockPlan.ManualTest.Result
  alias StockPlan.Repo
  alias StockPlan.Schema.Holding
  alias StockPlan.StockPrice
  alias StockPlan.Tax.ScheduleFA, as: FA
  import Ecto.Query

  @spec verify(String.t(), [String.t()], pos_integer()) :: [Result.t()]
  def verify(account_id, gl_paths, calendar_year)

  def verify(_account_id, [], calendar_year) do
    # Personas with gl: [] (e.g. su1-unsold, su5-adbe-unsold — Holdings-only,
    # 100% unrealized-path fixtures added in 05-02) have Benefit History sell
    # events but deliberately no G&L file at all. ScheduleFA.build/2's P1
    # hard gate correctly returns {:error, "G&L missing for sell dates..."}
    # for this scenario — that is the intended, correct production behavior
    # (M26 P1: never show FA figures without G&L-confirmed sell data), not a
    # discrepancy to compare against a golden file. There is no G&L data for
    # this check to verify against, so skip it rather than reporting the
    # correct P1 block as a failure (mirrors Portfolio.verify/2's existing
    # "Skipped — no Holdings file configured" pattern for the same reason).
    skipped(calendar_year)
  end

  def verify(account_id, gl_paths, calendar_year) do
    case FA.build(account_id, calendar_year) do
      {:error, {:missing_meta, syms}} ->
        blocked(
          calendar_year,
          "Schedule FA blocked — missing stock metadata",
          ["add metadata for: #{Enum.join(syms, ", ")}"]
        )

      {:error, message} when is_binary(message) ->
        blocked(calendar_year, "Schedule FA blocked — #{message}", [message])

      {:ok, rows, _warnings} ->
        holdings = load_holdings(account_id)
        current_cy = Date.utc_today().year
        sells_in_current_cy = gl_tranche_keys_in_cy(gl_paths, current_cy)

        [
          compare_sale_proceeds(rows, gl_paths, calendar_year),
          compare_closing_vs_holdings(
            rows,
            holdings,
            sells_in_current_cy,
            calendar_year,
            current_cy
          )
        ]
    end
  end

  defp blocked(calendar_year, summary, failures) do
    prefix = "Schedule FA CY #{calendar_year}"

    [
      Result.fail("#{prefix} — sale proceeds vs G&L", summary, failures),
      Result.fail("#{prefix} — closing vs holdings", summary, failures)
    ]
  end

  defp skipped(calendar_year) do
    prefix = "Schedule FA CY #{calendar_year}"
    summary = "Skipped — no G&L files configured for this user (Holdings-only persona)"

    [
      Result.pass("#{prefix} — sale proceeds vs G&L", summary, []),
      Result.pass("#{prefix} — closing vs holdings", summary, [])
    ]
  end

  defp compare_sale_proceeds(fa_rows, gl_paths, calendar_year) do
    section = "Schedule FA CY #{calendar_year} — sale proceeds vs G&L"
    cy_start = Date.new!(calendar_year, 1, 1)
    cy_end = Date.new!(calendar_year, 12, 31)
    proceeds_by_tranche = gl_proceeds_by_tranche(gl_paths, cy_start, cy_end)

    with_proceeds =
      Enum.filter(fa_rows, fn r ->
        r.sale_proceeds_inr != nil and Decimal.gt?(r.sale_proceeds_inr, Decimal.new(0))
      end)

    {row_details, failures} =
      Enum.map_reduce(with_proceeds, [], fn row, failures_acc ->
        expected = expected_proceeds_inr(row, proceeds_by_tranche)
        actual = row.sale_proceeds_inr
        label = fa_row_label(row)

        detail =
          "  #{match_mark(expected, actual)} #{label} " <>
            "ui=#{fmt(actual)} gl=#{fmt(expected)}"

        if proceeds_match?(expected, actual) do
          {detail, failures_acc}
        else
          {detail, [failure_message(label, expected, actual) | failures_acc]}
        end
      end)

    failures = Enum.reverse(failures)

    gl_only =
      fa_covered_tranche_keys(with_proceeds, proceeds_by_tranche)
      |> then(fn fa_keys ->
        Map.keys(proceeds_by_tranche) -- fa_keys
      end)
      |> Enum.filter(fn tk ->
        Decimal.gt?(Map.fetch!(proceeds_by_tranche, tk), Decimal.new(0))
      end)

    extra_failures =
      Enum.map(gl_only, fn tk ->
        "G&L sale proceeds for #{tk} not reflected in any FA row with sale proceeds"
      end)

    failures = failures ++ extra_failures

    details =
      [
        "calendar year: #{calendar_year} (same default as Tax Centre UI)",
        "G&L files: #{Enum.join(gl_paths, ", ")}",
        "FA rows total: #{length(fa_rows)}",
        "FA rows with sale proceeds > 0: #{length(with_proceeds)}",
        "FX: SBI TT buying, previous month month-end (Rule 115)",
        "sale proceeds INR = Σ(qty × proceeds_per_share × FX(sale_date))",
        "rows with sale proceeds:"
      ] ++ row_details

    if failures == [] do
      Result.pass(
        section,
        "All #{length(with_proceeds)} FA sale-proceeds rows match G&L",
        details
      )
    else
      Result.fail(
        section,
        "#{length(failures)} sale proceeds discrepancy(ies) for CY #{calendar_year}",
        failures,
        details
      )
    end
  end

  defp compare_closing_vs_holdings(fa_rows, holdings, sells_in_current_cy, fa_cy, current_cy) do
    section = "Schedule FA CY #{fa_cy} — closing vs holdings (no CY #{current_cy} sales)"
    cy_end = Date.new!(fa_cy, 12, 31)
    dec31_fx = FX.get_rate(cy_end)

    candidates =
      Enum.filter(fa_rows, fn r ->
        no_sale_proceeds?(r) and
          r.closing_value_inr != nil and
          Decimal.gt?(r.closing_value_inr, Decimal.new(0)) and
          not sold_in_current_cy?(r, sells_in_current_cy)
      end)

    {row_details, failures} =
      Enum.map_reduce(candidates, [], fn row, failures_acc ->
        holdings_qty = holdings_sellable_qty(row, holdings)
        expected = expected_closing_inr(row, holdings_qty, cy_end, dec31_fx)
        actual = row.closing_value_inr
        label = fa_row_label(row)

        qty_ok = Decimal.compare(holdings_qty, row.quantity_held) == :eq
        value_ok = proceeds_match?(expected, actual)
        ok = value_ok and qty_ok

        detail =
          "  #{if ok, do: "OK", else: "FAIL"} #{label} " <>
            "fa_close=#{fmt(actual)} holdings=#{fmt(expected)} " <>
            "fa_qty=#{fmt(row.quantity_held)} hold_qty=#{fmt(holdings_qty)}"

        cond do
          value_ok and qty_ok ->
            {detail, failures_acc}

          not qty_ok ->
            {detail,
             [
               "#{label}: qty fa=#{fmt(row.quantity_held)} holdings=#{fmt(holdings_qty)}"
               | failures_acc
             ]}

          true ->
            {detail,
             [
               "#{label}: closing fa=#{fmt(actual)} holdings=#{fmt(expected)}"
               | failures_acc
             ]}
        end
      end)

    failures = Enum.reverse(failures)

    skipped =
      Enum.count(fa_rows, fn r ->
        no_sale_proceeds?(r) and
          r.closing_value_inr != nil and
          Decimal.gt?(r.closing_value_inr, Decimal.new(0)) and
          sold_in_current_cy?(r, sells_in_current_cy)
      end)

    details =
      [
        "FA calendar year: #{fa_cy} | current CY (sales filter): #{current_cy}",
        "eligible rows: FA closing > 0, no sale proceeds in FA CY, no G&L sells in CY #{current_cy}",
        "holdings qty: sellable_qty from Holdings silver (same as TrancheTimeline)",
        "holdings value INR = sellable_qty × Dec31 #{fa_cy} price × Dec31 FX (Rule 115)",
        "checked: #{length(candidates)} | skipped (sold in CY #{current_cy}): #{skipped}",
        "rows:"
      ] ++ row_details

    if failures == [] do
      Result.pass(
        section,
        "All #{length(candidates)} held lots match FA closing and Holdings qty",
        details
      )
    else
      Result.fail(
        section,
        "#{length(failures)} closing/holdings discrepancy(ies)",
        failures,
        details
      )
    end
  end

  defp load_holdings(account_id) do
    Repo.all(
      from h in Holding,
        where: h.account_id == ^account_id and h.status == "VESTED"
    )
  end

  defp holdings_sellable_qty(row, holdings) do
    matching =
      Enum.filter(holdings, fn h ->
        h.symbol == row.symbol and h.vest_date == row.date_acquired and
          holdings_grant_match?(row, h)
      end)

    Enum.reduce(matching, Decimal.new(0), fn h, acc ->
      Decimal.add(acc, h.sellable_qty || Decimal.new(0))
    end)
  end

  defp holdings_grant_match?(_row, _holding), do: true

  defp expected_closing_inr(row, holdings_qty, cy_end, dec31_fx) do
    if Decimal.compare(holdings_qty, Decimal.new(0)) != :gt do
      Decimal.new(0)
    else
      case dec31_price(row.symbol, cy_end) do
        nil -> Decimal.new(0)
        price -> safe_mult3(price, holdings_qty, dec31_fx) || Decimal.new(0)
      end
    end
  end

  defp dec31_price(symbol, cy_end) do
    cy_start = Date.new!(cy_end.year, 1, 1)

    symbol
    |> StockPrice.get_close_range(cy_start, cy_end)
    |> Enum.filter(fn {date, _} -> Date.compare(date, cy_end) != :gt end)
    |> Enum.sort_by(fn {date, _} -> Date.to_iso8601(date) end, :desc)
    |> case do
      [{_, price} | _] -> Decimal.new(price)
      [] -> nil
    end
  end

  defp gl_tranche_keys_in_cy(gl_paths, calendar_year) do
    cy_start = Date.new!(calendar_year, 1, 1)
    cy_end = Date.new!(calendar_year, 12, 31)

    gl_paths
    |> Enum.flat_map(fn path ->
      case GlParser.parse(path) do
        {:ok, rows, _} ->
          Enum.flat_map(rows, fn row ->
            data = Jason.decode!(row.raw_row_json)
            sale_date = ValueNormalizer.parse_date(data["Date Sold"])

            if in_cy?(sale_date, cy_start, cy_end) do
              vest_date =
                ValueNormalizer.parse_date(data["Vest Date"]) ||
                  ValueNormalizer.parse_date(data["Purchase Date"])

              grant = data["Grant Number"]
              plan = data["Plan Type"]
              [tranche_key(grant, plan, vest_date)]
            else
              []
            end
          end)

        {:error, _} ->
          []
      end
    end)
    |> MapSet.new()
  end

  defp sold_in_current_cy?(row, sells_in_current_cy) do
    vest_iso = Date.to_iso8601(row.date_acquired)

    if String.starts_with?(row.plan_type || "", "ESPP") do
      MapSet.member?(sells_in_current_cy, "ESPP|#{row.date_acquired}")
    else
      sells_in_current_cy
      |> MapSet.to_list()
      |> Enum.any?(fn tk -> String.ends_with?(tk, "|#{vest_iso}") end)
    end
  end

  defp no_sale_proceeds?(row) do
    row.sale_proceeds_inr == nil or Decimal.equal?(row.sale_proceeds_inr, Decimal.new(0))
  end

  defp gl_proceeds_by_tranche(gl_paths, cy_start, cy_end) do
    gl_paths
    |> Enum.flat_map(&parse_gl_sells_in_cy(&1, cy_start, cy_end))
    # Sum INR for rows with the same lot_key instead of deduplicating.
    # Wash-sale sub-lots share (tranche, date, order, qty, price) but are distinct lots;
    # summing their INR matches the aggregated quantity Silver now stores per price-group.
    |> Enum.group_by(fn {lot_key, _tranche_key, _inr} -> lot_key end)
    |> Enum.flat_map(fn {_lot_key, entries} ->
      {_, tranche_key, _} = hd(entries)

      summed_inr =
        Enum.reduce(entries, Decimal.new(0), fn {_, _, inr}, acc -> Decimal.add(acc, inr) end)

      [{tranche_key, summed_inr}]
    end)
    |> Enum.group_by(fn {tranche_key, _inr} -> tranche_key end)
    |> Map.new(fn {tranche_key, entries} ->
      total = Enum.reduce(entries, Decimal.new(0), fn {_, inr}, acc -> Decimal.add(acc, inr) end)
      {tranche_key, total}
    end)
  end

  defp parse_gl_sells_in_cy(path, cy_start, cy_end) do
    case GlParser.parse(path) do
      {:ok, rows, _} ->
        Enum.flat_map(rows, fn row ->
          data = Jason.decode!(row.raw_row_json)
          sale_date = ValueNormalizer.parse_date(data["Date Sold"])

          if in_cy?(sale_date, cy_start, cy_end) do
            vest_date =
              ValueNormalizer.parse_date(data["Vest Date"]) ||
                ValueNormalizer.parse_date(data["Purchase Date"])

            quantity = ValueNormalizer.clean_number(data["Quantity"])
            price = ValueNormalizer.clean_number(data["Proceeds Per Share"])
            order = to_string(data["Order Number"] || "")
            plan = data["Plan Type"]
            grant = data["Grant Number"]
            tranche_key = tranche_key(grant, plan, vest_date)

            lot_key = "#{tranche_key}|#{sale_date}|#{order}|#{quantity}|#{price}"

            inr =
              Decimal.mult(
                Decimal.mult(Decimal.new(quantity), Decimal.new(price)),
                FX.get_rate(sale_date)
              )

            [{lot_key, tranche_key, inr}]
          else
            []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp expected_proceeds_inr(row, proceeds_by_tranche) do
    if String.starts_with?(row.plan_type || "", "ESPP") do
      Map.get(proceeds_by_tranche, "ESPP|#{row.date_acquired}", Decimal.new(0))
    else
      vest_iso = Date.to_iso8601(row.date_acquired)

      proceeds_by_tranche
      |> Enum.filter(fn {tranche_key, _} ->
        String.ends_with?(tranche_key, "|#{vest_iso}")
      end)
      |> Enum.reduce(Decimal.new(0), fn {_, inr}, acc -> Decimal.add(acc, inr) end)
    end
  end

  defp fa_covered_tranche_keys(rows, proceeds_by_tranche) do
    Enum.flat_map(rows, fn row ->
      if String.starts_with?(row.plan_type || "", "ESPP") do
        ["ESPP|#{row.date_acquired}"]
      else
        vest_iso = Date.to_iso8601(row.date_acquired)

        Map.keys(proceeds_by_tranche)
        |> Enum.filter(fn tranche_key -> String.ends_with?(tranche_key, "|#{vest_iso}") end)
      end
    end)
    |> Enum.uniq()
  end

  defp tranche_key(_grant, "ESPP", vest_date), do: "ESPP|#{vest_date}"
  defp tranche_key("--", _plan, vest_date), do: "ESPP|#{vest_date}"
  defp tranche_key(grant, _plan, vest_date), do: "#{grant}|#{vest_date}"

  defp in_cy?(nil, _, _), do: false

  defp in_cy?(sale_date, cy_start, cy_end) do
    Date.compare(sale_date, cy_start) != :lt and Date.compare(sale_date, cy_end) != :gt
  end

  defp proceeds_match?(expected, actual) do
    Decimal.compare(expected, actual) == :eq
  end

  defp match_mark(expected, actual) do
    if proceeds_match?(expected, actual), do: "OK", else: "FAIL"
  end

  defp failure_message(label, expected, actual) do
    "#{label}: ui=#{fmt(actual)} gl=#{fmt(expected)}"
  end

  defp fa_row_label(row) do
    plan =
      if String.starts_with?(row.plan_type || "", "ESPP"),
        do: "ESPP",
        else: row.plan_type || "RSU"

    "#{row.symbol} #{plan} vest=#{Date.to_iso8601(row.date_acquired)}"
  end

  defp safe_mult3(nil, _, _), do: nil
  defp safe_mult3(_, nil, _), do: nil
  defp safe_mult3(_, _, nil), do: nil

  defp safe_mult3(a, b, c), do: Decimal.mult(Decimal.mult(a, b), c)

  defp fmt(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt(nil), do: "nil"
end
