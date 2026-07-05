defmodule StockPlan.ManualTest.CapitalGains do
  @moduledoc false

  alias StockPlan.FX
  alias StockPlan.Ingestion.{GlParser, ValueNormalizer}
  alias StockPlan.ManualTest.Result
  alias StockPlan.Tax.CapitalGains, as: CG

  @spec verify(String.t(), [String.t()], [pos_integer()]) :: [Result.t()]
  def verify(account_id, gl_paths, fy_years) do
    gl_rows = load_gl_rows(gl_paths)

    Enum.map(fy_years, fn fy ->
      verify_fy(account_id, gl_rows, fy, gl_paths)
    end)
  end

  defp load_gl_rows(gl_paths) do
    Enum.flat_map(gl_paths, fn path ->
      case GlParser.parse(path) do
        {:ok, rows, _} ->
          Enum.map(rows, fn row -> {path, Jason.decode!(row.raw_row_json)} end)

        {:error, _} ->
          []
      end
    end)
  end

  defp verify_fy(account_id, gl_rows, fy, gl_paths) do
    fy_label = fy_label(fy)
    section = "Capital Gains FY #{fy_label}"

    fy_start = Date.new!(fy, 4, 1)
    fy_end = Date.new!(fy + 1, 3, 31)

    expected =
      gl_rows
      |> Enum.filter(fn {_path, data} ->
        sd = ValueNormalizer.parse_date(data["Date Sold"])
        sd && Date.compare(sd, fy_start) != :lt && Date.compare(sd, fy_end) != :gt
      end)
      |> Enum.map(&gl_row_to_expected/1)
      |> aggregate_gl_expected()

    {ui_rows, summary} = CG.build(account_id, fy)

    ui =
      Enum.map(ui_rows, fn r ->
        %{
          key:
            row_key(
              r.grant_number,
              r.plan_type,
              r.sale_date,
              r.order_number,
              r.vest_date,
              r.sale_price
            ),
          grant_number: r.grant_number,
          plan_type: plan_label(r.plan_type),
          sale_date: r.sale_date,
          vest_date: r.vest_date,
          quantity: norm_decimal(r.quantity),
          sale_price: norm_decimal(r.sale_price),
          cost_basis: norm_decimal(r.cost_basis_per_share),
          cost_basis_source: r.cost_basis_source,
          order_number: r.order_number || "",
          gain_type: r.gain_type,
          gain_inr: norm_decimal(r.gain_loss_inr)
        }
      end)

    exp_by_key = Map.new(expected, &{&1.key, &1})
    ui_by_key = Map.new(ui, &{&1.key, &1})

    missing = Map.keys(exp_by_key) -- Map.keys(ui_by_key)
    extra = Map.keys(ui_by_key) -- Map.keys(exp_by_key)

    mismatches =
      for {key, gl} <- exp_by_key,
          u = Map.get(ui_by_key, key),
          u != nil,
          reduce: [] do
        acc ->
          diffs = field_diffs(gl, u)
          if diffs == [], do: acc, else: [{key, diffs, gl.source_file} | acc]
      end

    dup_count = length(expected) - map_size(exp_by_key)

    details = [
      "G&L files: #{Enum.join(gl_paths, ", ")}",
      "G&L sell rows in FY window: #{map_size(exp_by_key)} aggregated lots#{dup_suffix(dup_count)}",
      "UI lot rows: #{length(ui)}",
      "net gain INR: #{Decimal.to_string(summary.net_gain_inr)}",
      "STCG INR: #{Decimal.to_string(summary.stcg_inr)} | LTCG INR: #{Decimal.to_string(summary.ltcg_inr)}"
    ]

    row_details =
      Enum.map(Enum.sort_by(ui, &{&1.sale_date, &1.order_number}), fn u ->
        gl = Map.get(exp_by_key, u.key)
        mark = if gl, do: "OK", else: "NO_GL"
        fx = fx_note(gl)

        "  #{mark} #{Date.to_iso8601(u.sale_date)} ord=#{u.order_number} #{u.grant_number} " <>
          "vest=#{Date.to_iso8601(u.vest_date)} qty=#{u.quantity} px=#{u.sale_price} cb=#{u.cost_basis} " <>
          "#{u.gain_type} INR=#{u.gain_inr}#{fx}"
      end)

    failures =
      Enum.map(missing, fn k ->
        g = Map.get(exp_by_key, k)
        "in G&L but not UI: #{k} (from #{g.source_file})"
      end) ++
        Enum.map(extra, fn k ->
          u = Map.get(ui_by_key, k)
          "in UI but not G&L: #{k} (#{u.grant_number} #{u.gain_type})"
        end) ++
        Enum.flat_map(Enum.sort(mismatches), fn {key, diffs, src} ->
          Enum.map(diffs, fn {field, gl, ui} ->
            "#{key} (#{src}) #{field}: gl=#{inspect(gl)} ui=#{inspect(ui)}"
          end)
        end)

    details = details ++ ["rows:" | row_details]

    if failures == [] do
      Result.pass(section, "All #{length(ui)} lot rows match G&L source (DB FX)", details)
    else
      Result.fail(
        section,
        "#{length(failures)} discrepancy(ies) for FY #{fy_label}",
        failures,
        details
      )
    end
  end

  defp gl_row_to_expected({source_file, data}) do
    sale_date = ValueNormalizer.parse_date(data["Date Sold"])

    vest_date =
      ValueNormalizer.parse_date(data["Vest Date"]) ||
        ValueNormalizer.parse_date(data["Purchase Date"])

    qty = ValueNormalizer.clean_number(data["Quantity"])
    price = ValueNormalizer.clean_number(data["Proceeds Per Share"])

    cb =
      ValueNormalizer.clean_number(data["Vest Date FMV"]) ||
        ValueNormalizer.clean_number(data["Purchase Date FMV"])

    order = to_string(data["Order Number"] || "")
    plan = data["Plan Type"]

    sale_fx = FX.get_rate(sale_date)
    vest_fx = FX.get_rate(vest_date)

    gain_inr =
      if price && qty && sale_fx && cb && vest_fx do
        proceeds = Decimal.mult(Decimal.mult(Decimal.new(price), Decimal.new(qty)), sale_fx)
        cost = Decimal.mult(Decimal.mult(Decimal.new(cb), Decimal.new(qty)), vest_fx)
        Decimal.sub(proceeds, cost) |> Decimal.to_string()
      else
        nil
      end

    %{
      key: row_key(data["Grant Number"], plan, sale_date, order, vest_date, price),
      source_file: source_file,
      plan_type: plan,
      grant_number: data["Grant Number"],
      sale_date: sale_date,
      vest_date: vest_date,
      quantity: qty,
      sale_price: price,
      cost_basis: cb,
      order_number: order,
      sale_fx: sale_fx,
      vest_fx: vest_fx,
      sale_fx_ym: FX.previous_month_key(sale_date),
      vest_fx_ym: FX.previous_month_key(vest_date),
      gain_inr: gain_inr
    }
  end

  defp field_diffs(gl, ui) do
    diffs =
      for {field, gv, uv} <- [
            {:quantity, gl.quantity, ui.quantity},
            {:sale_price, gl.sale_price, ui.sale_price}
          ],
          norm(gv) != norm(uv),
          do: {field, gv, uv}

    # ESPP G&L often omits FMV — UI uses BH tranche FMV. Only compare when G&L has a value.
    diffs =
      if gl.cost_basis != nil and norm(gl.cost_basis) != norm(ui.cost_basis) do
        [{:cost_basis, gl.cost_basis, ui.cost_basis} | diffs]
      else
        diffs
      end

    # INR gain: compare when G&L FMV allows computation; otherwise UI must still be present.
    cond do
      gl.gain_inr != nil and ui.gain_inr != nil and
          Decimal.compare(Decimal.new(gl.gain_inr), Decimal.new(ui.gain_inr)) != :eq ->
        [{:gain_inr, gl.gain_inr, ui.gain_inr} | diffs]

      gl.gain_inr == nil and gl.cost_basis == nil and ui.gain_inr == nil ->
        diffs

      gl.gain_inr == nil and gl.cost_basis == nil and ui.gain_inr != nil ->
        # ESPP: cost from BH — skip gain cross-check against raw G&L
        diffs

      true ->
        diffs
    end
  end

  # Group G&L rows by (grant, plan, sale_date, order, vest_date, price) — same key as
  # Silver's aggregate_gl_bronze/1 — and sum quantities and gain_inr within each group.
  # This prevents wash-sale sub-lots (same qty+price, different wash-sale adj) from being
  # silently dropped when Map.new deduplicates by lot_key.
  defp aggregate_gl_expected(rows) do
    rows
    |> Enum.group_by(fn r ->
      {r.grant_number, r.plan_type, r.sale_date, r.order_number, r.vest_date, r.sale_price}
    end)
    |> Enum.map(fn {_group_key, sub_rows} ->
      first = hd(sub_rows)

      total_qty =
        sub_rows
        |> Enum.map(fn r -> Decimal.new(r.quantity) end)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
        |> Decimal.to_string()

      total_gain_inr =
        if Enum.all?(sub_rows, fn r -> r.gain_inr != nil end) do
          sub_rows
          |> Enum.map(fn r -> Decimal.new(r.gain_inr) end)
          |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
          |> Decimal.to_string()
        else
          nil
        end

      %{
        first
        | key:
            row_key(
              first.grant_number,
              first.plan_type,
              first.sale_date,
              first.order_number,
              first.vest_date,
              first.sale_price
            ),
          quantity: total_qty,
          gain_inr: total_gain_inr
      }
    end)
  end

  defp row_key(grant_number, plan_type, sale_date, order, vest_date, price) do
    p = if is_struct(price, Decimal), do: Decimal.to_string(price), else: to_string(price || "")
    grant = grant_key(grant_number, plan_type)
    "#{grant}|#{sale_date}|#{order || ""}|#{vest_date}|#{p}"
  end

  # ESPP: G&L uses "--" for grant; UI uses hashed origin id.
  defp grant_key(_, "ESPP"), do: "ESPP"
  defp grant_key("--", "ESPP"), do: "ESPP"
  defp grant_key("--", _), do: "ESPP"
  defp grant_key(nil, "ESPP"), do: "ESPP"
  defp grant_key(nil, _), do: "ESPP"
  defp grant_key(grant, _), do: to_string(grant)

  defp fx_note(nil), do: ""

  defp fx_note(gl) do
    " src=#{Path.basename(gl.source_file)} " <>
      "fx_sale=#{gl.sale_fx_ym}/#{fmt_fx(gl.sale_fx)} " <>
      "fx_vest=#{gl.vest_fx_ym}/#{fmt_fx(gl.vest_fx)}"
  end

  defp fy_label(fy) do
    short = rem(fy + 1, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{fy}-#{short}"
  end

  defp plan_label("ESPP"), do: "ESPP"
  defp plan_label("RSU"), do: "RSU"
  defp plan_label(other), do: other || "?"

  defp dup_suffix(0), do: ""
  defp dup_suffix(n), do: ", #{n} duplicate G&L row(s) collapsed"

  defp fmt_fx(nil), do: "nil"
  defp fmt_fx(%Decimal{} = d), do: Decimal.to_string(d)

  defp norm_decimal(nil), do: nil
  defp norm_decimal(%Decimal{} = d), do: Decimal.to_string(d)
  defp norm_decimal(v), do: v

  defp norm(nil), do: nil
  defp norm(v) when is_binary(v), do: String.trim(v)
  defp norm(%Date{} = d), do: Date.to_iso8601(d)
  defp norm(v), do: v
end
