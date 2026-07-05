defmodule StockPlan.ManualTest.Portfolio do
  @moduledoc false

  alias StockPlan.{Portfolio, Repo}
  alias StockPlan.Ingestion.{HoldingsParser, ValueNormalizer}
  alias StockPlan.ManualTest.Result
  alias StockPlan.Schema.Holding
  import Ecto.Query

  @spec verify(String.t(), String.t()) :: Result.t()
  def verify(account_id, holdings_path) do
    section = "Portfolio vs Holdings XLSX"

    cond do
      is_nil(holdings_path) ->
        Result.pass(section, "Skipped — no Holdings file configured for this user", [])

      not File.exists?(holdings_path) ->
        Result.fail(section, "Holdings file not found: #{holdings_path}", [
          "missing file: #{holdings_path}"
        ])

      true ->
        case parse_expected(holdings_path) do
          {:error, result} ->
            result

          {:ok, expected_visible} ->
            compare(section, expected_visible, load_actual(account_id), holdings_path)
        end
    end
  end

  defp parse_expected(holdings_path) do
    case HoldingsParser.parse(holdings_path) do
      {:error, reason} ->
        {:error,
         Result.fail("Portfolio vs Holdings XLSX", "Failed to parse holdings file", [
           "parse error: #{inspect(reason)}"
         ])}

      {:ok, bronze_rows, warnings} ->
        grouped = Enum.group_by(bronze_rows, & &1.sheet_name)

        expected =
          parse_rsu(grouped["Holdings_RSU"] || [])
          |> Kernel.++(parse_espp(grouped["Holdings_ESPP"] || []))

        visible =
          Enum.filter(expected, fn r ->
            case r.status do
              "VESTED" ->
                r.sellable_qty != nil and
                  Decimal.gt?(Decimal.new(r.sellable_qty), Decimal.new(0))

              "UNVESTED" ->
                true

              _ ->
                false
            end
          end)

        details =
          if warnings == [] do
            []
          else
            ["XLSX parse warnings: #{length(warnings)}"]
          end

        {:ok, {visible, details}}
    end
  end

  defp parse_rsu(rows) do
    rows
    |> Enum.map(fn row -> {row, Jason.decode!(row.raw_row_json)} end)
    |> Enum.group_by(fn {_row, data} -> data["Grant Number"] end)
    |> Enum.flat_map(fn {grant_number, row_pairs} ->
      sellable_map = build_sellable_map(row_pairs)

      row_pairs
      |> Enum.filter(fn {row, _} -> row.record_type == "Vest Schedule" end)
      |> Enum.map(fn {_row, data} ->
        period = to_string(data["Vest Period"])
        vest_date = ValueNormalizer.parse_date(data["Vest Date"])
        released_qty = ValueNormalizer.clean_number_keep_zero(data["Released Qty"])
        vest_qty_period = ValueNormalizer.clean_number(data["Granted Qty._2"])
        is_vested = released_qty != nil and released_qty != "0"
        sellable = Map.get(sellable_map, period)

        {sellable_qty, cost_basis, status, quantity} =
          cond do
            sellable ->
              sq = sellable.sellable_qty
              {sq, sellable.cost_basis, "VESTED", sq}

            is_vested ->
              {"0", nil, "VESTED", "0"}

            true ->
              {nil, nil, "UNVESTED", vest_qty_period}
          end

        %{
          key: "RSU|#{grant_number}|#{vest_date}",
          plan_type: "RSU",
          grant_number: grant_number,
          vest_date: vest_date,
          status: status,
          quantity: quantity,
          sellable_qty: sellable_qty,
          cost_basis: cost_basis
        }
      end)
    end)
  end

  defp build_sellable_map(row_pairs) do
    row_pairs
    |> Enum.filter(fn {row, _} -> row.record_type == "Sellable Shares" end)
    |> Enum.reduce(%{}, fn {_row, data}, acc ->
      period = to_string(data["Vest Period"])
      sq = ValueNormalizer.clean_number_keep_zero(data["Sellable Qty._3"])
      bq = ValueNormalizer.clean_number_keep_zero(data["Blocked Share Qty."])

      Map.put(acc, period, %{
        sellable_qty: add_qty(sq, bq),
        cost_basis: ValueNormalizer.clean_number(data["Est. Cost Basis (per share):"])
      })
    end)
  end

  defp parse_espp(rows) do
    rows
    |> Enum.filter(&(&1.record_type == "Purchase"))
    |> Enum.map(fn row ->
      data = Jason.decode!(row.raw_row_json)
      grant_date = ValueNormalizer.parse_date(data["Grant Date"])
      purchase_date = ValueNormalizer.parse_date(data["Purchase Date"])
      symbol = data["Symbol"]
      sellable_qty = ValueNormalizer.clean_number_keep_zero(data["Sellable Qty."])
      cost_basis = ValueNormalizer.clean_number(data["Purchase Date FMV"])

      espp_grant =
        if symbol && grant_date do
          "ESPP:#{symbol}:#{Date.to_iso8601(grant_date)}"
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)
          |> String.slice(0, 16)
        end

      %{
        key: "ESPP|#{espp_grant}|#{purchase_date}",
        plan_type: "ESPP",
        grant_number: espp_grant,
        vest_date: purchase_date,
        status: "VESTED",
        quantity: sellable_qty,
        sellable_qty: sellable_qty,
        cost_basis: cost_basis
      }
    end)
  end

  defp load_actual(account_id) do
    all_count =
      Repo.aggregate(from(h in Holding, where: h.account_id == ^account_id), :count, :id)

    flat = Portfolio.build(account_id) |> Portfolio.flat_holdings()

    rows =
      Enum.map(flat, fn h ->
        %{
          key: "#{h.plan_type}|#{h.grant_number}|#{h.vest_date}",
          plan_type: h.plan_type,
          grant_number: h.grant_number,
          vest_date: h.vest_date,
          status: h.status,
          quantity: norm_decimal(h.quantity),
          sellable_qty: norm_decimal(h.sellable_qty),
          cost_basis: norm_decimal(h.cost_basis_per_share)
        }
      end)

    {rows, all_count}
  end

  defp compare(section, {expected_visible, parse_details}, {actual, all_count}, holdings_path) do
    exp_by_key = Map.new(expected_visible, &{&1.key, &1})
    act_by_key = Map.new(actual, &{&1.key, &1})

    missing = Map.keys(exp_by_key) -- Map.keys(act_by_key)
    extra = Map.keys(act_by_key) -- Map.keys(exp_by_key)

    mismatches =
      for {key, exp} <- exp_by_key,
          act = Map.get(act_by_key, key),
          act != nil,
          reduce: [] do
        acc ->
          diffs =
            for {field, ev, av} <- [
                  {:quantity, exp.quantity, act.quantity},
                  {:sellable_qty, exp.sellable_qty, act.sellable_qty},
                  {:cost_basis, exp.cost_basis, act.cost_basis},
                  {:status, exp.status, act.status}
                ],
                norm(ev) != norm(av),
                do: {field, ev, av}

          if diffs == [], do: acc, else: [{key, diffs} | acc]
      end

    vested = Enum.count(actual, &(&1.status == "VESTED"))
    unvested = Enum.count(actual, &(&1.status == "UNVESTED"))

    details =
      parse_details ++
        [
          "holdings file: #{holdings_path}",
          "silver holdings rows: #{all_count}",
          "visible UI rows: #{length(actual)} (vested=#{vested}, unvested=#{unvested})",
          "XLSX visible rows: #{length(expected_visible)}"
        ]

    failures =
      Enum.map(missing, fn k ->
        e = Map.get(exp_by_key, k)
        "missing in UI: #{k} (#{e.plan_type} qty=#{e.quantity})"
      end) ++
        Enum.map(extra, fn k ->
          a = Map.get(act_by_key, k)
          "extra in UI: #{k} (#{a.plan_type} qty=#{a.quantity})"
        end) ++
        Enum.flat_map(Enum.sort(mismatches), fn {key, diffs} ->
          Enum.map(diffs, fn {field, exp, act} ->
            "#{key} #{field}: xlsx=#{inspect(exp)} ui=#{inspect(act)}"
          end)
        end)

    if failures == [] do
      Result.pass(
        section,
        "All #{length(actual)} visible portfolio rows match Holdings XLSX",
        details
      )
    else
      Result.fail(
        section,
        "#{length(failures)} discrepancy(ies) between Portfolio UI and Holdings XLSX",
        failures,
        details
      )
    end
  end

  defp add_qty(nil, nil), do: nil
  defp add_qty(nil, b), do: b
  defp add_qty(a, nil), do: a

  defp add_qty(a, b) do
    Decimal.add(Decimal.new(a), Decimal.new(b)) |> Decimal.to_string()
  end

  defp norm_decimal(nil), do: nil
  defp norm_decimal(%Decimal{} = d), do: Decimal.to_string(d)
  defp norm_decimal(v), do: v

  defp norm(nil), do: nil
  defp norm(v) when is_binary(v), do: String.trim(v)
  defp norm(%Date{} = d), do: Date.to_iso8601(d)
  defp norm(v), do: v
end
