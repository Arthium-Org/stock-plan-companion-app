defmodule StockPlan.Tax.SellAdvisorV2 do
  @moduledoc """
  v2 Sell Advisor — 2-stage pass-based algorithm.

  Stage 1: Offset existing FY gains with loss lots (tax loss harvesting)
    1a: STOffsetPass — pick STCL lots to offset baseline STCG
    1b: LTOffsetPass — pick LTCL lots to offset baseline LTCG (minus STCL cross-offset)

  Stage 2: Fill remaining user constraint with incremental marginal evaluation.

  Reuses evaluate_tax, compute_charges, build_entry, etc. from SellAdvisor (v1).
  """

  alias StockPlan.Tax.SellAdvisor

  defdelegate compute_basket_proceeds(basket, current_price, current_fx), to: SellAdvisor
  defdelegate basket_to_csv(basket, current_price, current_fx), to: SellAdvisor

  @doc """
  Main entry point. Returns {:ok, result} or {:error, reason}.

  target can be:
    {:shares, n}  — sell exactly n shares
    {:usd, amount} — sell >= $amount worth
    {:inr, amount} — sell >= amount worth
    :harvest      — pure tax loss harvest (no user constraint)
  """
  def advise(account_id, target, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())
    explicit_symbol = Keyword.get(opts, :symbol)

    # Early exit: check for sellable lots before fetching price.
    # This avoids a spurious :no_current_price error for users with no Holdings.
    lots_check = SellAdvisor.load_sellable_lots(account_id, explicit_symbol)

    if lots_check == [] do
      {:error, :no_sellable_lots}
    else
      current_price = Keyword.get(opts, :current_price)
      current_fx = Keyword.get(opts, :current_fx)
      symbol = explicit_symbol || resolve_default_symbol(account_id)

      current_price =
        SellAdvisor.ensure_decimal(
          current_price ||
            (symbol && StockPlan.StockPrice.current_price(symbol))
        )

      current_fx = SellAdvisor.ensure_decimal(current_fx || StockPlan.FX.current_rate())

      with :ok <- SellAdvisor.validate_price_fx(current_price, current_fx),
           {:ok, target_shares} <- resolve_target_v2(target, current_price, current_fx),
           lots when lots != [] <- lots_check do
        enriched = SellAdvisor.enrich_lots(lots, current_price, current_fx, today)

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

          fy_baseline = SellAdvisor.load_fy_baseline(account_id, today)

          # Enrich lots with 4-way classification
          classified_lots = classify_lots(valid_lots, today)

          # Stage 1: Offset existing FY gains
          {stage1_entries, stage1_committed_ids, stage1_plan_types} =
            run_stage1(classified_lots, fy_baseline, current_price, current_fx)

          if target == :harvest do
            # Pure harvest mode: Stage 1 only
            basket =
              build_v2_basket(
                "Tax Harvest (v2)",
                stage1_entries,
                target,
                target_shares,
                fy_baseline
              )

            harvest_summary = build_harvest_summary(stage1_entries, fy_baseline)

            {:ok,
             %{
               version: "v2",
               baskets: [basket],
               current_price: current_price,
               current_fx: current_fx,
               total_sellable: total_sellable,
               target_shares: target_shares,
               target: target,
               fy_baseline: fy_baseline,
               warnings: warnings,
               harvest_summary: harvest_summary
             }}
          else
            # Stage 2: Fill remaining constraint
            stage1_shares =
              Enum.reduce(stage1_entries, Decimal.new(0), fn e, acc ->
                Decimal.add(acc, e.qty_to_sell)
              end)

            remaining_target = Decimal.sub(target_shares, stage1_shares)

            stage2_entries =
              if Decimal.gt?(remaining_target, Decimal.new(0)) do
                uncommitted =
                  Enum.reject(classified_lots, fn lot ->
                    MapSet.member?(stage1_committed_ids, lot.holding_id)
                  end)

                fill_with_plan_preference(
                  uncommitted,
                  remaining_target,
                  fy_baseline,
                  current_price,
                  current_fx,
                  stage1_plan_types
                )
              else
                []
              end

            all_entries = stage1_entries ++ stage2_entries

            basket =
              build_v2_basket(
                "2-Stage Optimized (v2)",
                all_entries,
                target,
                target_shares,
                fy_baseline
              )

            {:ok,
             %{
               version: "v2",
               baskets: [basket],
               current_price: current_price,
               current_fx: current_fx,
               total_sellable: total_sellable,
               target_shares: target_shares,
               target: target,
               fy_baseline: fy_baseline,
               warnings: warnings
             }}
          end
        end
      else
        [] -> {:error, :no_sellable_lots}
        {:error, _} = err -> err
      end
    end
  end

  # ============================================================
  # Target Resolution (supports :harvest)
  # ============================================================

  defp resolve_default_symbol(account_id) do
    case StockPlan.Portfolio.held_symbols(account_id) do
      [] -> nil
      [s | _] -> s
    end
  end

  defp resolve_target_v2(:harvest, _price, _fx) do
    # No constraint — return 0 as target (Stage 1 only)
    {:ok, Decimal.new(0)}
  end

  defp resolve_target_v2(target, price, fx) do
    SellAdvisor.resolve_target(target, price, fx)
  end

  # ============================================================
  # 4-Way Classification
  # ============================================================

  defp classify_lots(lots, today) do
    Enum.map(lots, fn lot ->
      classification = classify(lot.vest_date, lot.gain_per_share_inr, today)
      Map.put(lot, :classification, classification)
    end)
  end

  defp classify(vest_date, gain_per_share_inr, today) do
    long_term = Date.compare(today, Date.shift(vest_date, year: 2)) == :gt
    loss = gain_per_share_inr != nil and Decimal.negative?(gain_per_share_inr)

    case {long_term, loss} do
      {true, true} -> :LTCL
      {true, false} -> :LTCG
      {false, true} -> :STCL
      {false, false} -> :STCG
    end
  end

  # ============================================================
  # Stage 1: Offset Existing FY Gains
  # ============================================================

  defp run_stage1(lots, fy_baseline, current_price, current_fx) do
    # Stage 1a: Offset baseline STCG with STCL lots
    net_st =
      Decimal.sub(fy_baseline.realized_st_gain, fy_baseline.realized_st_loss)

    {stage1a_entries, stage1a_committed_ids, excess_stcl} =
      if Decimal.gt?(net_st, Decimal.new(0)) do
        stcl_lots =
          lots
          |> Enum.filter(&(&1.classification == :STCL))
          |> Enum.sort_by(
            fn lot -> Decimal.to_float(Decimal.abs(lot.gain_per_share_inr)) end,
            :asc
          )

        pick_offset_lots(
          stcl_lots,
          net_st,
          [],
          fy_baseline,
          current_price,
          current_fx
        )
      else
        # No STCG to offset, but compute excess STCL (baseline ST loss > ST gain)
        excess = Decimal.abs(Decimal.min(net_st, Decimal.new(0)))
        {[], MapSet.new(), excess}
      end

    # Stage 1b: Offset baseline LTCG with LTCL lots (minus STCL cross-offset)
    net_lt =
      Decimal.sub(fy_baseline.realized_lt_gain, fy_baseline.realized_lt_loss)

    remaining_lt_target = Decimal.sub(net_lt, excess_stcl)

    {stage1b_entries, stage1b_committed_ids, _excess_ltcl} =
      if Decimal.gt?(remaining_lt_target, Decimal.new(0)) do
        ltcl_lots =
          lots
          |> Enum.filter(fn lot ->
            lot.classification == :LTCL and
              not MapSet.member?(stage1a_committed_ids, lot.holding_id)
          end)
          |> Enum.sort_by(
            fn lot -> Decimal.to_float(Decimal.abs(lot.gain_per_share_inr)) end,
            :asc
          )

        pick_offset_lots(
          ltcl_lots,
          remaining_lt_target,
          stage1a_entries,
          fy_baseline,
          current_price,
          current_fx
        )
      else
        {[], MapSet.new(), Decimal.new(0)}
      end

    all_entries = stage1a_entries ++ stage1b_entries
    all_committed = MapSet.union(stage1a_committed_ids, stage1b_committed_ids)

    plan_types =
      all_entries
      |> Enum.map(& &1.lot.plan_type)
      |> MapSet.new()

    {all_entries, all_committed, plan_types}
  end

  # Pick loss lots to offset a gain target, with cost justification.
  # Returns {entries, committed_ids, excess_loss}
  defp pick_offset_lots(
         loss_lots,
         target_gain,
         existing_basket,
         fy_baseline,
         current_price,
         current_fx
       ) do
    {entries, committed_ids, accumulated_loss} =
      Enum.reduce_while(
        loss_lots,
        {[], MapSet.new(), Decimal.new(0)},
        fn lot, {entries_acc, ids_acc, loss_acc} ->
          if Decimal.gte?(loss_acc, target_gain) do
            {:halt, {entries_acc, ids_acc, loss_acc}}
          else
            entry =
              SellAdvisor.build_entry(lot, lot.sellable_qty, current_price, current_fx)

            if cost_justified?(
                 entry,
                 existing_basket ++ entries_acc,
                 fy_baseline,
                 current_fx
               ) do
              lot_loss = Decimal.abs(entry.gain_inr)
              new_loss = Decimal.add(loss_acc, lot_loss)
              new_ids = MapSet.put(ids_acc, lot.holding_id)

              {:cont, {entries_acc ++ [entry], new_ids, new_loss}}
            else
              {:cont, {entries_acc, ids_acc, loss_acc}}
            end
          end
        end
      )

    excess = Decimal.max(Decimal.new(0), Decimal.sub(accumulated_loss, target_gain))
    {entries, committed_ids, excess}
  end

  # ============================================================
  # Cost Justification
  # ============================================================

  defp cost_justified?(entry, current_basket, fy_baseline, current_fx) do
    tax_before = SellAdvisor.evaluate_tax(current_basket, fy_baseline)
    tax_after = SellAdvisor.evaluate_tax(current_basket ++ [entry], fy_baseline)
    tax_saved = Decimal.sub(tax_before.total_tax, tax_after.total_tax)

    # Marginal charge for this lot
    charges = marginal_charge(entry, current_basket, current_fx)

    Decimal.gt?(tax_saved, charges)
  end

  defp marginal_charge(entry, current_basket, current_fx) do
    plan_type = entry.lot.plan_type

    existing_plan_types =
      current_basket
      |> Enum.map(& &1.lot.plan_type)
      |> MapSet.new()

    if MapSet.member?(existing_plan_types, plan_type) do
      # Same plan type already committed — zero marginal charge
      Decimal.new(0)
    else
      if MapSet.size(existing_plan_types) == 0 do
        # First lot ever: bears wire fee + brokerage
        wire_inr = Decimal.mult(Decimal.new("25"), current_fx)
        wire_inr
      else
        # Adding a new plan type: bears brokerage for new order
        # (brokerage is 0 in Phase 1, but structure is correct)
        Decimal.new(0)
      end
    end
  end

  # ============================================================
  # Stage 2 Fill with Plan Type Preference
  # ============================================================

  @epsilon Decimal.new("0.0001")
  @sentinel Decimal.new("1.0E12")

  defp fill_with_plan_preference(
         lots,
         target_shares,
         fy_baseline,
         current_price,
         current_fx,
         committed_plan_types
       ) do
    do_fill_v2(
      lots,
      [],
      target_shares,
      fy_baseline,
      current_price,
      current_fx,
      committed_plan_types
    )
  end

  defp do_fill_v2(
         remaining_lots,
         selected,
         remaining,
         fy_baseline,
         current_price,
         current_fx,
         committed_types
       ) do
    cond do
      Decimal.lte?(remaining, Decimal.new(0)) ->
        Enum.reverse(selected)

      remaining_lots == [] ->
        Enum.reverse(selected)

      true ->
        scored =
          Enum.map(remaining_lots, fn lot ->
            qty = Decimal.min(lot.sellable_qty, remaining)
            candidate_entry = SellAdvisor.build_entry(lot, qty, current_price, current_fx)

            tax_with = SellAdvisor.evaluate_tax(selected ++ [candidate_entry], fy_baseline)
            tax_without = SellAdvisor.evaluate_tax(selected, fy_baseline)
            marginal_tax = Decimal.sub(tax_with.total_tax, tax_without.total_tax)

            mt_per_share =
              if Decimal.equal?(qty, Decimal.new(0)) do
                @sentinel
              else
                Decimal.div(marginal_tax, qty)
              end

            mt_score =
              if Decimal.lt?(Decimal.abs(mt_per_share), @epsilon),
                do: Decimal.new(0),
                else: mt_per_share

            is_gain = if Decimal.negative?(lot.gain_per_share_inr), do: 0, else: 1

            # Track which plan types are already in the basket
            basket_types =
              Enum.reduce(selected, committed_types, fn e, acc ->
                MapSet.put(acc, e.lot.plan_type)
              end)

            # 0 = same plan type (no extra order), 1 = new plan type (extra charge)
            plan_penalty = if MapSet.member?(basket_types, lot.plan_type), do: 0, else: 1

            # Preserve STCL for future: prefer LTCL (0) over STCL (1) when both are losses
            # STCL is more valuable — can offset both STCG + LTCG
            # LTCL is less valuable — can only offset LTCG
            loss_preservation =
              case Map.get(lot, :classification, lot.gain_type) do
                # use first (lower future value)
                :LTCL -> 0
                :LTCG -> 1
                # preserve (higher future value)
                :STCL -> 2
                :STCG -> 3
                _ -> 1
              end

            future_cost =
              if Decimal.negative?(lot.gain_per_share_inr),
                do: Decimal.abs(lot.gain_per_share_inr),
                else: Decimal.new(0)

            {lot, qty, Decimal.to_float(mt_score), is_gain, plan_penalty, loss_preservation,
             Decimal.to_float(future_cost)}
          end)

        # Sort: marginal tax → loss preferred → same plan type → LTCL before STCL → smallest future cost
        {best_lot, best_qty, _, _, _, _, _} =
          Enum.min_by(scored, fn {_, _, mt, ig, pp, lp, fc} -> {mt, ig, pp, lp, fc} end, fn ->
            nil
          end)

        if best_lot == nil do
          Enum.reverse(selected)
        else
          entry = SellAdvisor.build_entry(best_lot, best_qty, current_price, current_fx)
          new_remaining = Decimal.sub(remaining, best_qty)

          new_remaining_lots =
            Enum.reject(remaining_lots, &(&1.holding_id == best_lot.holding_id))

          do_fill_v2(
            new_remaining_lots,
            [entry | selected],
            new_remaining,
            fy_baseline,
            current_price,
            current_fx,
            committed_types
          )
        end
    end
  end

  # ============================================================
  # Basket Output Builder
  # ============================================================

  defp build_v2_basket(name, entries, target, target_shares, fy_baseline) do
    basket = SellAdvisor.build_basket_output(name, entries, target, target_shares, fy_baseline)

    # Marginal tax impact: tax before vs after this sale
    tax_before_sale = SellAdvisor.evaluate_tax([], fy_baseline).total_tax
    tax_after_sale = SellAdvisor.evaluate_tax(entries, fy_baseline).total_tax
    tax_impact = Decimal.sub(tax_after_sale, tax_before_sale)

    basket
    |> Map.put(:version, "v2")
    |> Map.put(:tax_before_sale, tax_before_sale)
    |> Map.put(:tax_after_sale, tax_after_sale)
    |> Map.put(:tax_impact, tax_impact)
  end

  # ============================================================
  # Harvest Summary
  # ============================================================

  defp build_harvest_summary(entries, fy_baseline) do
    if entries == [] do
      %{
        message: "No cost-justified tax loss harvesting available.",
        lots_to_sell: 0,
        tax_saved_inr: Decimal.new(0)
      }
    else
      tax_before = SellAdvisor.evaluate_tax([], fy_baseline)
      tax_after = SellAdvisor.evaluate_tax(entries, fy_baseline)
      tax_saved = Decimal.sub(tax_before.total_tax, tax_after.total_tax)

      total_shares =
        Enum.reduce(entries, Decimal.new(0), fn e, acc ->
          Decimal.add(acc, e.qty_to_sell)
        end)

      %{
        message:
          "Sell #{length(entries)} lot(s) (#{Decimal.to_string(total_shares)} shares) to save #{format_inr(tax_saved)} in FY tax.",
        lots_to_sell: length(entries),
        shares_to_sell: total_shares,
        tax_saved_inr: tax_saved
      }
    end
  end

  defp format_inr(amount) do
    rounded = Decimal.round(amount, 0)
    "INR #{Decimal.to_string(rounded)}"
  end
end
