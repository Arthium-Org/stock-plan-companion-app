defmodule StockPlan.Tax.SellAdvisor do
  @moduledoc """
  Sell Advisor — recommends which lots to sell to minimize tax + transaction cost.

  Given a sell target (shares, USD, or INR), generates 2 baskets:

  1. Exact Target — Incremental marginal tax evaluation, fills exactly to target
  2. Cost Optimized — Whole-lot combinations minimizing (tax + charges) / proceeds

  Uses TaxEvaluator offset cascade (Indian tax rules) with FY baseline context.
  """

  alias StockPlan.Repo
  alias StockPlan.Schema.Holding
  alias StockPlan.Tax.CapitalGains
  import Ecto.Query

  # Tax rates (Phase 1): conservative estimates with 4% cess
  @stcg_rate Decimal.new("0.312")
  @ltcg_rate Decimal.new("0.13")

  # Transaction costs
  @wire_fee_usd Decimal.new("25")
  @brokerage_per_order Decimal.new("0")

  # Basket 2 constraints
  @max_evaluations 5000
  @max_combo_lots 12

  # Division guard sentinel
  @sentinel Decimal.new("1.0E12")

  # Epsilon for snapping near-zero marginal tax
  @epsilon Decimal.new("0.0001")

  @type target :: {:shares, Decimal.t()} | {:usd, Decimal.t()} | {:inr, Decimal.t()}

  @doc """
  Main entry point. Returns {:ok, result} or {:error, reason}.

  result = %{
    baskets: [basket],
    current_price: Decimal,
    current_fx: Decimal,
    total_sellable: Decimal,
    target_shares: Decimal,
    target: target,
    fy_baseline: map,
    warnings: [String]
  }
  """
  def advise(account_id, target, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())
    current_price = Keyword.get(opts, :current_price)
    current_fx = Keyword.get(opts, :current_fx)
    symbol = Keyword.get(opts, :symbol) || resolve_default_symbol(account_id)

    current_price =
      ensure_decimal(
        current_price ||
          (symbol && StockPlan.StockPrice.current_price(symbol))
      )

    current_fx = ensure_decimal(current_fx || StockPlan.FX.current_rate())

    with :ok <- validate_price_fx(current_price, current_fx),
         {:ok, target_shares} <- resolve_target(target, current_price, current_fx),
         lots when lots != [] <- load_sellable_lots(account_id, symbol) do
      enriched = enrich_lots(lots, current_price, current_fx, today)

      # Filter out lots with nil cost_basis
      {valid_lots, excluded} = Enum.split_with(enriched, &(&1.cost_basis != nil))

      warnings =
        if excluded != [] do
          ["#{length(excluded)} lot(s) excluded — cost basis unavailable"]
        else
          []
        end

      if valid_lots == [] do
        {:error, :no_valid_lots}
      else
        total_sellable =
          Enum.reduce(valid_lots, Decimal.new(0), fn lot, acc ->
            Decimal.add(acc, lot.sellable_qty)
          end)

        fy_baseline = load_fy_baseline(account_id, today)

        basket1 =
          build_basket1_exact(
            valid_lots,
            target,
            target_shares,
            fy_baseline,
            current_price,
            current_fx
          )

        basket2 =
          build_basket2_cost_optimized(
            valid_lots,
            target,
            target_shares,
            fy_baseline,
            current_price,
            current_fx
          )

        baskets = dedup_baskets(basket1, basket2)

        {:ok,
         %{
           baskets: baskets,
           current_price: current_price,
           current_fx: current_fx,
           total_sellable: total_sellable,
           target_shares: target_shares,
           target: target,
           fy_baseline: fy_baseline,
           warnings: warnings
         }}
      end
    else
      [] -> {:error, :no_sellable_lots}
      {:error, _} = err -> err
    end
  end

  @doc """
  Compute basket proceeds from lots, current_price, and current_fx.
  Called at display time since proceeds depend on live price.
  """
  def compute_basket_proceeds(basket, current_price, current_fx) do
    total_proceeds_usd = Decimal.mult(basket.total_shares, current_price)
    total_proceeds_inr = Decimal.mult(total_proceeds_usd, current_fx)
    charges_inr = Decimal.mult(basket.charges.total_charges_usd, current_fx)

    net_proceeds_inr =
      total_proceeds_inr
      |> Decimal.sub(basket.total_tax_inr)
      |> Decimal.sub(charges_inr)

    %{
      total_proceeds_usd: total_proceeds_usd,
      total_proceeds_inr: total_proceeds_inr,
      charges_inr: charges_inr,
      net_proceeds_inr: net_proceeds_inr
    }
  end

  @doc """
  Generate CSV content for a basket.
  """
  def basket_to_csv(basket, current_price, current_fx) do
    header =
      "Plan Type,Grant #,Vest Date,Qty to Sell,Cost Basis (USD),Current Price (USD),Gain Type,Est. Gain (INR),Est. Tax (INR)\r\n"

    rows =
      basket.entries
      |> Enum.map(fn e ->
        [
          e.lot.plan_type,
          e.lot.grant_number || "",
          Date.to_iso8601(e.lot.vest_date),
          Decimal.to_string(e.qty_to_sell),
          Decimal.round(e.lot.cost_basis, 2) |> Decimal.to_string(),
          Decimal.round(current_price, 2) |> Decimal.to_string(),
          Atom.to_string(e.gain_type),
          Decimal.round(e.gain_inr, 2) |> Decimal.to_string(),
          Decimal.round(e.tax_inr, 2) |> Decimal.to_string()
        ]
        |> Enum.join(",")
      end)
      |> Enum.join("\r\n")

    proceeds = compute_basket_proceeds(basket, current_price, current_fx)

    summary_row =
      [
        "TOTAL",
        "",
        "",
        Decimal.to_string(basket.total_shares),
        "",
        "",
        "",
        "",
        Decimal.round(basket.total_tax_inr, 2) |> Decimal.to_string()
      ]
      |> Enum.join(",")

    proceeds_usd_str = Decimal.round(proceeds.total_proceeds_usd, 2) |> Decimal.to_string()
    proceeds_inr_str = Decimal.round(proceeds.total_proceeds_inr, 2) |> Decimal.to_string()
    net_str = Decimal.round(proceeds.net_proceeds_inr, 2) |> Decimal.to_string()
    charges_str = Decimal.round(basket.charges.total_charges_usd, 2) |> Decimal.to_string()

    header <>
      rows <>
      "\r\n" <>
      summary_row <>
      "\r\nProceeds (USD)," <>
      proceeds_usd_str <>
      "\r\nProceeds (INR)," <>
      proceeds_inr_str <>
      "\r\nNet Proceeds (INR)," <>
      net_str <>
      "\r\nCharges (USD)," <> charges_str
  end

  # ============================================================
  # Target Resolution
  # ============================================================

  @doc false
  def resolve_target({:shares, n}, _price, _fx) do
    n = ensure_decimal(n)

    if Decimal.gt?(n, Decimal.new(0)) do
      {:ok, n}
    else
      {:error, :invalid_target}
    end
  end

  @doc false
  def resolve_target({:usd, amount}, price, _fx) do
    amount = ensure_decimal(amount)

    if Decimal.gt?(amount, Decimal.new(0)) do
      shares = Decimal.div(amount, price) |> Decimal.round(0, :ceiling)

      if Decimal.gt?(shares, Decimal.new(0)) do
        {:ok, shares}
      else
        {:error, :target_too_small}
      end
    else
      {:error, :invalid_target}
    end
  end

  @doc false
  def resolve_target({:inr, amount}, price, fx) do
    amount = ensure_decimal(amount)

    if Decimal.gt?(amount, Decimal.new(0)) do
      usd = Decimal.div(amount, fx)
      shares = Decimal.div(usd, price) |> Decimal.round(0, :ceiling)

      if Decimal.gt?(shares, Decimal.new(0)) do
        {:ok, shares}
      else
        {:error, :target_too_small}
      end
    else
      {:error, :invalid_target}
    end
  end

  def resolve_target(_, _, _), do: {:error, :invalid_target}

  # ============================================================
  # Load Sellable Lots
  # ============================================================

  @doc false
  def load_sellable_lots(account_id, symbol \\ nil)

  def load_sellable_lots(account_id, nil) do
    Repo.all(
      from h in Holding,
        where:
          h.account_id == ^account_id and
            h.status == "VESTED" and
            not is_nil(h.sellable_qty) and
            h.sellable_qty > ^Decimal.new(0),
        order_by: [asc: h.vest_date]
    )
  end

  def load_sellable_lots(account_id, symbol) when is_binary(symbol) do
    Repo.all(
      from h in Holding,
        where:
          h.account_id == ^account_id and
            h.symbol == ^symbol and
            h.status == "VESTED" and
            not is_nil(h.sellable_qty) and
            h.sellable_qty > ^Decimal.new(0),
        order_by: [asc: h.vest_date]
    )
  end

  defp resolve_default_symbol(account_id) do
    case StockPlan.Portfolio.held_symbols(account_id) do
      [] -> nil
      [s | _] -> s
    end
  end

  # ============================================================
  # Lot Enrichment
  # ============================================================

  @doc false
  def enrich_lots(lots, current_price, current_fx, today) do
    Enum.map(lots, fn lot -> enrich_lot(lot, current_price, current_fx, today) end)
  end

  defp enrich_lot(lot, current_price, current_fx, today) do
    gain_type = classify_gain_type(lot.vest_date, today)

    vest_fx = lot.vest_fx_rate || current_fx

    gain_per_share_inr =
      if lot.cost_basis != nil do
        current_value_inr = Decimal.mult(current_price, current_fx)
        cost_basis_inr = Decimal.mult(lot.cost_basis, vest_fx)
        Decimal.sub(current_value_inr, cost_basis_inr)
      else
        nil
      end

    gain_per_share_usd =
      if lot.cost_basis != nil do
        Decimal.sub(current_price, lot.cost_basis)
      else
        nil
      end

    cost_basis_inr =
      if lot.cost_basis != nil do
        Decimal.mult(lot.cost_basis, vest_fx)
      else
        nil
      end

    current_value_inr = Decimal.mult(current_price, current_fx)

    %{
      holding_id: lot.id,
      grant_number: lot.grant_number,
      plan_type: lot.plan_type,
      symbol: lot.symbol,
      vest_date: lot.vest_date,
      vest_period: lot.vest_period,
      sellable_qty: lot.sellable_qty,
      cost_basis: lot.cost_basis,
      vest_fx_rate: vest_fx,
      gain_type: gain_type,
      gain_per_share_usd: gain_per_share_usd,
      gain_per_share_inr: gain_per_share_inr,
      cost_basis_inr: cost_basis_inr,
      current_value_inr: current_value_inr
    }
  end

  defp classify_gain_type(vest_date, today) do
    threshold = Date.shift(vest_date, year: 2)

    if Date.compare(today, threshold) == :gt do
      :LTCG
    else
      :STCG
    end
  end

  # ============================================================
  # FY Baseline
  # ============================================================

  @doc false
  def load_fy_baseline(account_id, today) do
    fy_start = if today.month >= 4, do: today.year, else: today.year - 1

    case CapitalGains.build(account_id, fy_start) do
      {rows, _summary} ->
        # Decompose into gains and losses by type
        stcg_rows = Enum.filter(rows, &(&1.gain_type == :STCG && &1.gain_loss_inr != nil))
        ltcg_rows = Enum.filter(rows, &(&1.gain_type == :LTCG && &1.gain_loss_inr != nil))

        realized_st_gain = sum_positive(stcg_rows, :gain_loss_inr)
        realized_st_loss = sum_negative_abs(stcg_rows, :gain_loss_inr)
        realized_lt_gain = sum_positive(ltcg_rows, :gain_loss_inr)
        realized_lt_loss = sum_negative_abs(ltcg_rows, :gain_loss_inr)

        %{
          realized_st_gain: realized_st_gain,
          realized_st_loss: realized_st_loss,
          realized_lt_gain: realized_lt_gain,
          realized_lt_loss: realized_lt_loss
        }

      _ ->
        zero_baseline()
    end
  end

  defp sum_positive(rows, field) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc ->
      val = Map.get(row, field)

      if val != nil and Decimal.positive?(val) do
        Decimal.add(acc, val)
      else
        acc
      end
    end)
  end

  defp sum_negative_abs(rows, field) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc ->
      val = Map.get(row, field)

      if val != nil and Decimal.negative?(val) do
        Decimal.add(acc, Decimal.abs(val))
      else
        acc
      end
    end)
  end

  @doc false
  def zero_baseline do
    %{
      realized_st_gain: Decimal.new(0),
      realized_st_loss: Decimal.new(0),
      realized_lt_gain: Decimal.new(0),
      realized_lt_loss: Decimal.new(0)
    }
  end

  # ============================================================
  # Tax Evaluator (Offset Cascade)
  # ============================================================

  @doc """
  Evaluate tax for a set of basket entries against FY baseline.
  Returns %{st_tax, lt_tax, total_tax, gross_st_gain, gross_st_loss, gross_lt_gain, gross_lt_loss}.
  """
  def evaluate_tax(entries, fy_baseline) do
    # Aggregate basket gains/losses by type
    {st_gain, st_loss, lt_gain, lt_loss} = aggregate_by_type(entries)

    # Combine with FY baseline
    total_st_gain = Decimal.add(fy_baseline.realized_st_gain, st_gain)
    total_st_loss = Decimal.add(fy_baseline.realized_st_loss, st_loss)
    total_lt_gain = Decimal.add(fy_baseline.realized_lt_gain, lt_gain)
    total_lt_loss = Decimal.add(fy_baseline.realized_lt_loss, lt_loss)

    # Step 1: Net ST position
    net_st = Decimal.sub(total_st_gain, total_st_loss)
    leftover_st_loss = Decimal.max(Decimal.new(0), Decimal.negate(net_st))

    # Step 2: Cross-offset STCL -> LTCG
    net_lt = Decimal.sub(total_lt_gain, total_lt_loss)
    adj_net_lt = Decimal.sub(net_lt, leftover_st_loss)

    # Step 3: Compute tax
    st_taxable = Decimal.max(Decimal.new(0), net_st)
    lt_taxable = Decimal.max(Decimal.new(0), adj_net_lt)

    st_tax = Decimal.mult(st_taxable, @stcg_rate)
    lt_tax = Decimal.mult(lt_taxable, @ltcg_rate)

    %{
      st_tax: st_tax,
      lt_tax: lt_tax,
      total_tax: Decimal.add(st_tax, lt_tax),
      gross_st_gain: st_gain,
      gross_st_loss: st_loss,
      gross_lt_gain: lt_gain,
      gross_lt_loss: lt_loss
    }
  end

  defp aggregate_by_type(entries) do
    Enum.reduce(
      entries,
      {Decimal.new(0), Decimal.new(0), Decimal.new(0), Decimal.new(0)},
      fn entry, {sg, sl, lg, ll} ->
        gain_inr = entry.gain_inr

        case entry.gain_type do
          :STCG ->
            {Decimal.add(sg, gain_inr), sl, lg, ll}

          :STCL ->
            {sg, Decimal.add(sl, Decimal.abs(gain_inr)), lg, ll}

          :LTCG ->
            {sg, sl, Decimal.add(lg, gain_inr), ll}

          :LTCL ->
            {sg, sl, lg, Decimal.add(ll, Decimal.abs(gain_inr))}

          # Fallback for 2-way (v1 without classification)
          _ ->
            if Decimal.positive?(gain_inr) do
              {Decimal.add(sg, gain_inr), sl, lg, ll}
            else
              {sg, Decimal.add(sl, Decimal.abs(gain_inr)), lg, ll}
            end
        end
      end
    )
  end

  # ============================================================
  # Transaction Charges
  # ============================================================

  @doc false
  def compute_charges(entries) do
    has_espp = Enum.any?(entries, &(&1.lot.plan_type == "ESPP"))
    has_rsu = Enum.any?(entries, &(&1.lot.plan_type == "RSU"))

    order_count = if(has_espp, do: 1, else: 0) + if has_rsu, do: 1, else: 0
    brokerage = Decimal.mult(@brokerage_per_order, Decimal.new(order_count))
    total = Decimal.add(@wire_fee_usd, brokerage)

    %{
      wire_fee_usd: @wire_fee_usd,
      brokerage_usd: brokerage,
      order_count: order_count,
      total_charges_usd: total
    }
  end

  # ============================================================
  # Basket Entry Builder
  # ============================================================

  @doc false
  def build_entry(lot, qty, current_price, current_fx) do
    proceeds_usd = Decimal.mult(qty, current_price)
    proceeds_inr = Decimal.mult(proceeds_usd, current_fx)
    cost_basis_total_inr = Decimal.mult(qty, lot.cost_basis_inr)
    gain_inr = Decimal.sub(proceeds_inr, cost_basis_total_inr)

    %{
      lot: lot,
      qty_to_sell: qty,
      proceeds_usd: proceeds_usd,
      proceeds_inr: proceeds_inr,
      cost_basis_total_inr: cost_basis_total_inr,
      gain_inr: gain_inr,
      gain_type: Map.get(lot, :classification, lot.gain_type)
    }
  end

  # ============================================================
  # Basket 1: Exact Target (Incremental Marginal Evaluation)
  # ============================================================

  defp build_basket1_exact(lots, target, target_shares, fy_baseline, current_price, current_fx) do
    entries = fill_basket_incremental(lots, target_shares, fy_baseline, current_price, current_fx)
    build_basket_output("Exact Target", entries, target, target_shares, fy_baseline)
  end

  @doc false
  def fill_basket_incremental(lots, target_shares, fy_baseline, current_price, current_fx) do
    do_fill_incremental(lots, [], target_shares, fy_baseline, current_price, current_fx)
  end

  defp do_fill_incremental(
         remaining_lots,
         selected,
         remaining,
         fy_baseline,
         current_price,
         current_fx
       ) do
    cond do
      Decimal.lte?(remaining, Decimal.new(0)) ->
        Enum.reverse(selected)

      remaining_lots == [] ->
        Enum.reverse(selected)

      true ->
        # For each candidate lot, compute marginal tax if we add it
        scored =
          Enum.map(remaining_lots, fn lot ->
            qty = Decimal.min(lot.sellable_qty, remaining)
            candidate_entry = build_entry(lot, qty, current_price, current_fx)

            # Tax WITH this lot
            tax_with = evaluate_tax(selected ++ [candidate_entry], fy_baseline)
            # Tax WITHOUT (current basket)
            tax_without = evaluate_tax(selected, fy_baseline)

            marginal_tax = Decimal.sub(tax_with.total_tax, tax_without.total_tax)

            # Per-share normalization
            mt_per_share =
              if Decimal.equal?(qty, Decimal.new(0)) do
                @sentinel
              else
                Decimal.div(marginal_tax, qty)
              end

            # Epsilon snap: prevent Decimal precision noise
            mt_score =
              if Decimal.lt?(Decimal.abs(mt_per_share), @epsilon) do
                Decimal.new(0)
              else
                mt_per_share
              end

            # Tiebreaker: is_gain (0=loss, 1=gain)
            is_gain = if Decimal.negative?(lot.gain_per_share_inr), do: 0, else: 1

            # Future cost: |gain_per_share| for loss lots
            future_cost =
              if Decimal.negative?(lot.gain_per_share_inr) do
                Decimal.abs(lot.gain_per_share_inr)
              else
                Decimal.new(0)
              end

            {lot, qty, mt_score, is_gain, future_cost}
          end)

        # Pick lot with lowest marginal tax per share, then loss preferred, then smallest future cost
        # NOTE: Must convert Decimals to floats for tuple comparison —
        # Erlang term ordering does NOT compare Decimal structs numerically
        {best_lot, best_qty, _mt, _ig, _fc} =
          Enum.min_by(
            scored,
            fn {_lot, _qty, mt, is_gain, fc} ->
              {Decimal.to_float(mt), is_gain, Decimal.to_float(fc)}
            end,
            fn -> nil end
          )

        if best_lot == nil do
          Enum.reverse(selected)
        else
          entry = build_entry(best_lot, best_qty, current_price, current_fx)
          new_remaining = Decimal.sub(remaining, best_qty)

          new_remaining_lots =
            Enum.reject(remaining_lots, &(&1.holding_id == best_lot.holding_id))

          do_fill_incremental(
            new_remaining_lots,
            [entry | selected],
            new_remaining,
            fy_baseline,
            current_price,
            current_fx
          )
        end
    end
  end

  # ============================================================
  # Basket 2: Cost Optimized (Whole-Lot Combinations)
  # ============================================================

  defp build_basket2_cost_optimized(
         lots,
         target,
         target_shares,
         fy_baseline,
         current_price,
         current_fx
       ) do
    if length(lots) > @max_combo_lots do
      # Fallback: greedy with whole-lot rounding
      entries =
        greedy_whole_lot_fallback(lots, target_shares, fy_baseline, current_price, current_fx)

      build_basket_output("Cost Optimized", entries, target, target_shares, fy_baseline)
    else
      # Pre-filter: sort by |gain_per_share| for relevance
      sorted_lots =
        Enum.sort_by(
          lots,
          fn lot ->
            if lot.gain_per_share_inr,
              do: Decimal.abs(lot.gain_per_share_inr),
              else: Decimal.new(0)
          end,
          {:desc, Decimal}
        )
        |> Enum.take(@max_combo_lots)

      {min_qty, max_qty} = compute_qty_bounds(target, target_shares, current_price, current_fx)

      best =
        enumerate_combinations(
          sorted_lots,
          min_qty,
          max_qty,
          target_shares,
          fy_baseline,
          current_price,
          current_fx
        )

      case best do
        nil ->
          # No valid combo found — fall back to Basket 1 style
          entries =
            fill_basket_incremental(lots, target_shares, fy_baseline, current_price, current_fx)

          build_basket_output("Cost Optimized", entries, target, target_shares, fy_baseline)

        entries ->
          build_basket_output("Cost Optimized", entries, target, target_shares, fy_baseline)
      end
    end
  end

  defp compute_qty_bounds({:shares, _}, target_shares, _price, _fx) do
    min_qty = Decimal.mult(target_shares, Decimal.new("0.7"))
    max_qty = Decimal.mult(target_shares, Decimal.new("1.3"))
    {min_qty, max_qty}
  end

  defp compute_qty_bounds({:usd, _amount}, target_shares, _price, _fx) do
    # For USD/INR mode: must meet at least target, no upper cap beyond reason
    {target_shares, Decimal.mult(target_shares, Decimal.new("1.5"))}
  end

  defp compute_qty_bounds({:inr, _amount}, target_shares, _price, _fx) do
    {target_shares, Decimal.mult(target_shares, Decimal.new("1.5"))}
  end

  defp enumerate_combinations(
         lots,
         min_qty,
         max_qty,
         target_shares,
         fy_baseline,
         current_price,
         current_fx
       ) do
    # Use a counter to cap evaluations
    counter = :counters.new(1, [:atomics])

    combos =
      generate_combos(
        lots,
        [],
        Decimal.new(0),
        min_qty,
        max_qty,
        counter,
        current_price,
        current_fx
      )

    if combos == [] do
      nil
    else
      # Evaluate each combo
      ranked =
        combos
        |> Enum.map(fn entries ->
          tax_result = evaluate_tax(entries, fy_baseline)
          charges = compute_charges(entries)

          total_cost =
            Decimal.add(tax_result.total_tax, Decimal.mult(charges.total_charges_usd, current_fx))

          total_proceeds =
            Enum.reduce(entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.proceeds_inr) end)

          total_qty =
            Enum.reduce(entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.qty_to_sell) end)

          cost_ratio =
            if Decimal.positive?(total_proceeds) do
              Decimal.div(total_cost, total_proceeds)
            else
              @sentinel
            end

          overshoot = Decimal.sub(total_qty, target_shares) |> Decimal.abs()

          {entries, cost_ratio, overshoot, tax_result, charges}
        end)
        |> Enum.sort_by(fn {_entries, cost_ratio, overshoot, _tax, _charges} ->
          {cost_ratio, overshoot}
        end)

      case ranked do
        [{entries, _cr, _os, _tax, _charges} | _] -> entries
        [] -> nil
      end
    end
  end

  defp generate_combos(lots, current_entries, current_qty, min_qty, max_qty, counter, price, fx) do
    count = :counters.get(counter, 1)

    cond do
      # Budget exhausted
      count >= @max_evaluations ->
        if Decimal.gte?(current_qty, min_qty) and current_entries != [] do
          [current_entries]
        else
          []
        end

      # Exceeded max qty — prune
      Decimal.gt?(current_qty, max_qty) ->
        []

      # No more lots to consider
      lots == [] ->
        if Decimal.gte?(current_qty, min_qty) and current_entries != [] do
          [current_entries]
        else
          []
        end

      true ->
        [lot | rest] = lots

        # Branch 1: skip this lot
        without =
          generate_combos(
            rest,
            current_entries,
            current_qty,
            min_qty,
            max_qty,
            counter,
            price,
            fx
          )

        # Branch 2: include this lot (whole qty)
        entry = build_entry(lot, lot.sellable_qty, price, fx)
        new_qty = Decimal.add(current_qty, lot.sellable_qty)

        :counters.add(counter, 1, 1)

        with_lot =
          if Decimal.gt?(new_qty, max_qty) do
            if Decimal.gte?(new_qty, min_qty) do
              [[entry | current_entries]]
            else
              []
            end
          else
            valid_current =
              if Decimal.gte?(new_qty, min_qty) do
                [[entry | current_entries]]
              else
                []
              end

            valid_current ++
              generate_combos(
                rest,
                [entry | current_entries],
                new_qty,
                min_qty,
                max_qty,
                counter,
                price,
                fx
              )
          end

        without ++ with_lot
    end
  end

  defp greedy_whole_lot_fallback(lots, target_shares, fy_baseline, current_price, current_fx) do
    # Use incremental selection but round to whole lots
    incremental =
      fill_basket_incremental(lots, target_shares, fy_baseline, current_price, current_fx)

    # Round each lot to whole qty
    Enum.map(incremental, fn entry ->
      # If last lot was partial, decide whether to include full or drop
      if Decimal.lt?(entry.qty_to_sell, entry.lot.sellable_qty) do
        full_entry = build_entry(entry.lot, entry.lot.sellable_qty, current_price, current_fx)

        overshoot_pct =
          Decimal.div(
            Decimal.sub(entry.lot.sellable_qty, entry.qty_to_sell),
            entry.lot.sellable_qty
          )

        if Decimal.lt?(overshoot_pct, Decimal.new("0.3")) do
          full_entry
        else
          entry
        end
      else
        entry
      end
    end)
  end

  # ============================================================
  # Basket Output Builder
  # ============================================================

  @doc false
  def build_basket_output(name, entries, _target, target_shares, fy_baseline) do
    total_shares =
      Enum.reduce(entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.qty_to_sell) end)

    fills_target = Decimal.gte?(total_shares, target_shares)
    remaining = Decimal.sub(target_shares, total_shares)

    shortfall =
      if Decimal.positive?(remaining), do: remaining, else: nil

    overshoot =
      if Decimal.negative?(remaining), do: Decimal.abs(remaining), else: nil

    # Tax evaluation on the complete basket
    tax_result = evaluate_tax(entries, fy_baseline)
    charges = compute_charges(entries)

    # Per-entry tax attribution (for display)
    entries_with_tax = attribute_entry_tax(entries)

    # STCG/LTCG breakdown
    stcg_entries = Enum.filter(entries_with_tax, &(&1.gain_type == :STCG))
    ltcg_entries = Enum.filter(entries_with_tax, &(&1.gain_type == :LTCG))

    stcg_shares =
      Enum.reduce(stcg_entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.qty_to_sell) end)

    ltcg_shares =
      Enum.reduce(ltcg_entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.qty_to_sell) end)

    %{
      name: name,
      entries: entries_with_tax,
      total_shares: total_shares,
      stcg_shares: stcg_shares,
      ltcg_shares: ltcg_shares,
      stcg_tax_inr: tax_result.st_tax,
      ltcg_tax_inr: tax_result.lt_tax,
      total_tax_inr: tax_result.total_tax,
      gross_st_gain: tax_result.gross_st_gain,
      gross_st_loss: tax_result.gross_st_loss,
      gross_lt_gain: tax_result.gross_lt_gain,
      gross_lt_loss: tax_result.gross_lt_loss,
      charges: charges,
      fills_target: fills_target,
      shortfall: shortfall,
      overshoot: overshoot,
      target_shares: target_shares
    }
  end

  defp attribute_entry_tax(entries) do
    # Simple per-entry tax estimation for display (proportional)
    # The authoritative tax is from TaxEvaluator on the whole basket
    Enum.map(entries, fn entry ->
      rate = if entry.gain_type == :STCG, do: @stcg_rate, else: @ltcg_rate

      tax_inr =
        if Decimal.positive?(entry.gain_inr) do
          Decimal.mult(entry.gain_inr, rate)
        else
          Decimal.new(0)
        end

      Map.put(entry, :tax_inr, tax_inr)
    end)
  end

  # ============================================================
  # Deduplication
  # ============================================================

  defp dedup_baskets(basket1, basket2) do
    if baskets_identical?(basket1, basket2) do
      [basket1]
    else
      [basket1, basket2]
    end
  end

  defp baskets_identical?(b1, b2) do
    e1 = Enum.sort_by(b1.entries, & &1.lot.holding_id)
    e2 = Enum.sort_by(b2.entries, & &1.lot.holding_id)

    length(e1) == length(e2) and
      Enum.zip(e1, e2)
      |> Enum.all?(fn {a, b} ->
        a.lot.holding_id == b.lot.holding_id and
          Decimal.equal?(a.qty_to_sell, b.qty_to_sell)
      end)
  end

  # ============================================================
  # Helpers
  # ============================================================

  @doc false
  def ensure_decimal(nil), do: nil
  def ensure_decimal(%Decimal{} = d), do: d
  def ensure_decimal(v) when is_binary(v), do: Decimal.new(v)
  def ensure_decimal(v) when is_integer(v), do: Decimal.new(v)
  def ensure_decimal(v) when is_float(v), do: Decimal.from_float(v)

  @doc false
  def validate_price_fx(nil, _), do: {:error, :no_current_price}
  def validate_price_fx(_, nil), do: {:error, :no_current_fx}
  def validate_price_fx(_, _), do: :ok
end
