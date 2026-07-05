defmodule StockPlanWeb.SellAdvisorLive do
  use StockPlanWeb, :live_view

  alias StockPlan.Tax.SellAdvisorV2, as: SellAdvisor
  alias StockPlan.{Ingestions, Portfolio}

  @account_id "default"

  @impl true
  def mount(_params, _session, socket) do
    held = Portfolio.held_symbols(@account_id)
    symbol = default_symbol(held, @account_id)

    current_price =
      if symbol, do: ensure_decimal(StockPlan.StockPrice.current_price(symbol)), else: nil

    current_fx = StockPlan.FX.current_rate()
    current_fx_info = StockPlan.FX.current_rate_info()

    total_sellable = compute_total_sellable(symbol)
    fy_baseline = load_fy_baseline()

    {:ok,
     socket
     |> assign(:page_title, "Sell Advisor")
     |> assign(:last_upload_at, Ingestions.latest_upload_at(@account_id))
     |> assign(:held_symbols, held)
     |> assign(:symbol, symbol)
     |> assign(:current_price, current_price)
     |> assign(:current_fx, current_fx)
     |> assign(:current_fx_info, current_fx_info)
     |> assign(:fx_info_open, false)
     |> assign(:mode, "shares")
     |> assign(:target_input, "")
     |> assign(:baskets, nil)
     |> assign(:error, nil)
     |> assign(:warnings, [])
     |> assign(:total_sellable, total_sellable)
     |> assign(:fy_baseline, fy_baseline)
     |> assign(:expanded, MapSet.new())}
  end

  @impl true
  def handle_event("show_fx_info", _params, socket) do
    {:noreply, assign(socket, fx_info_open: true)}
  end

  def handle_event("hide_fx_info", _params, socket) do
    {:noreply, assign(socket, fx_info_open: false)}
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: mode, error: nil)}
  end

  def handle_event("update_input", %{"target" => value}, socket) do
    {:noreply, assign(socket, target_input: value, error: nil)}
  end

  def handle_event("select_symbol", %{"symbol" => symbol}, socket) do
    current_price = ensure_decimal(StockPlan.StockPrice.current_price(symbol))
    total_sellable = compute_total_sellable(symbol)

    {:noreply,
     socket
     |> assign(:symbol, symbol)
     |> assign(:current_price, current_price)
     |> assign(:total_sellable, total_sellable)
     |> assign(:baskets, nil)
     |> assign(:error, nil)}
  end

  def handle_event("advise", _params, socket) do
    case parse_target(socket.assigns.mode, socket.assigns.target_input) do
      {:ok, target} ->
        case SellAdvisor.advise(@account_id, target, symbol: socket.assigns.symbol) do
          {:ok, result} ->
            {:noreply,
             socket
             |> assign(:baskets, result.baskets)
             |> assign(:current_price, result.current_price)
             |> assign(:current_fx, result.current_fx)
             |> assign(:total_sellable, result.total_sellable)
             |> assign(:fy_baseline, result.fy_baseline)
             |> assign(:warnings, result.warnings)
             |> assign(:error, nil)
             |> assign(:expanded, MapSet.new())}

          {:error, :no_sellable_lots} ->
            {:noreply, assign(socket, error: "No sellable lots found.", baskets: nil)}

          {:error, :no_valid_lots} ->
            {:noreply,
             assign(socket,
               error: "No lots with known cost basis. Cannot compute tax estimates.",
               baskets: nil
             )}

          {:error, :no_current_price} ->
            {:noreply, assign(socket, error: "Current stock price unavailable.", baskets: nil)}

          {:error, :no_current_fx} ->
            {:noreply, assign(socket, error: "Current FX rate unavailable.", baskets: nil)}

          {:error, :target_too_small} ->
            {:noreply,
             assign(socket,
               error: "Target amount too small to buy even 1 share.",
               baskets: nil
             )}

          {:error, _} ->
            {:noreply, assign(socket, error: "Something went wrong.", baskets: nil)}
        end

      {:error, msg} ->
        {:noreply, assign(socket, error: msg, baskets: nil)}
    end
  end

  def handle_event("toggle_expand", %{"basket" => basket_name}, socket) do
    expanded = socket.assigns.expanded

    new_expanded =
      if MapSet.member?(expanded, basket_name),
        do: MapSet.delete(expanded, basket_name),
        else: MapSet.put(expanded, basket_name)

    {:noreply, assign(socket, expanded: new_expanded)}
  end

  def handle_event("download_csv", %{"basket" => basket_idx_str}, socket) do
    idx = String.to_integer(basket_idx_str)

    case Enum.at(socket.assigns.baskets || [], idx) do
      nil ->
        {:noreply, socket}

      basket ->
        csv =
          SellAdvisor.basket_to_csv(
            basket,
            socket.assigns.current_price,
            socket.assigns.current_fx
          )

        safe_name = String.replace(basket.name, " ", "_")
        date_str = Date.utc_today() |> Date.to_iso8601()
        filename = "Sell_Advisor_#{safe_name}_#{date_str}.csv"

        {:noreply,
         push_event(socket, "download", %{
           content: Base.encode64(csv),
           filename: filename,
           content_type: "text/csv"
         })}
    end
  end

  # ============================================================
  # Helpers
  # ============================================================

  defp parse_target(mode, input) do
    case Float.parse(String.trim(input)) do
      {num, _} when num > 0 ->
        d = Decimal.new(input |> String.trim())

        case mode do
          "shares" -> {:ok, {:shares, d}}
          "usd" -> {:ok, {:usd, d}}
          "inr" -> {:ok, {:inr, d}}
        end

      {_, _} ->
        {:error, "Please enter a positive number."}

      :error ->
        {:error, "Please enter a valid number."}
    end
  end

  defp compute_total_sellable(nil), do: Decimal.new(0)

  defp compute_total_sellable(symbol) do
    alias StockPlan.Repo
    alias StockPlan.Schema.Holding
    import Ecto.Query

    result =
      Repo.one(
        from h in Holding,
          where:
            h.account_id == ^@account_id and
              h.status == "VESTED" and
              h.symbol == ^symbol and
              not is_nil(h.sellable_qty),
          select: sum(h.sellable_qty)
      )

    case result do
      nil -> Decimal.new(0)
      %Decimal{} = d -> d
      f when is_float(f) -> Decimal.from_float(f)
      v -> Decimal.new(to_string(v))
    end
  end

  defp default_symbol([], _account_id), do: nil
  defp default_symbol([only], _account_id), do: only

  defp default_symbol(symbols, account_id) do
    # Choose symbol with most held shares
    prices = Map.new(symbols, fn s -> {s, nil} end)
    summaries = StockPlan.Portfolio.symbol_summaries(account_id, prices)

    case summaries do
      [] ->
        List.first(symbols)

      _ ->
        summaries
        |> Enum.max_by(fn s -> Decimal.to_float(s.held_qty || Decimal.new(0)) end)
        |> Map.get(:symbol)
    end
  end

  defp load_fy_baseline do
    today = Date.utc_today()
    fy_start = if today.month >= 4, do: today.year, else: today.year - 1

    case StockPlan.Tax.CapitalGains.build(@account_id, fy_start) do
      {rows, _summary} ->
        stcg_rows =
          Enum.filter(rows, &(&1.gain_type in [:STCG, :STCL] && &1.gain_loss_inr != nil))

        ltcg_rows =
          Enum.filter(rows, &(&1.gain_type in [:LTCG, :LTCL] && &1.gain_loss_inr != nil))

        %{
          realized_st_gain: sum_positive(stcg_rows),
          realized_st_loss: sum_negative_abs(stcg_rows),
          realized_lt_gain: sum_positive(ltcg_rows),
          realized_lt_loss: sum_negative_abs(ltcg_rows)
        }

      _ ->
        StockPlan.Tax.SellAdvisor.zero_baseline()
    end
  end

  defp sum_positive(rows) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc ->
      if row.gain_loss_inr != nil and Decimal.positive?(row.gain_loss_inr) do
        Decimal.add(acc, row.gain_loss_inr)
      else
        acc
      end
    end)
  end

  defp sum_negative_abs(rows) do
    Enum.reduce(rows, Decimal.new(0), fn row, acc ->
      if row.gain_loss_inr != nil and Decimal.negative?(row.gain_loss_inr) do
        Decimal.add(acc, Decimal.abs(row.gain_loss_inr))
      else
        acc
      end
    end)
  end

  defp ensure_decimal(nil), do: nil
  defp ensure_decimal(%Decimal{} = d), do: d
  defp ensure_decimal(v) when is_binary(v), do: Decimal.new(v)

  # ============================================================
  # Formatting Helpers
  # ============================================================

  defp format_inr(nil), do: "—"

  defp format_inr(%Decimal{} = d) do
    rounded = Decimal.round(d, 0)

    if Decimal.compare(rounded, Decimal.new(0)) == :eq do
      "0"
    else
      format_indian_number(Decimal.to_string(rounded))
    end
  end

  defp format_usd(nil), do: "—"
  defp format_usd(%Decimal{} = d), do: "$#{Decimal.round(d, 2) |> Decimal.to_string()}"

  defp format_qty(nil), do: "—"
  defp format_qty(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()
  defp format_qty(v) when is_float(v), do: Float.round(v, 2) |> Float.to_string()
  defp format_qty(v) when is_integer(v), do: Integer.to_string(v)

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%d-%b-%Y")

  defp format_indian_number(str) do
    {sign, abs_str} =
      if String.starts_with?(str, "-"),
        do: {"-", String.trim_leading(str, "-")},
        else: {"", str}

    int_part =
      case String.split(abs_str, ".") do
        [i | _] -> i
      end

    len = String.length(int_part)

    formatted =
      if len <= 3 do
        int_part
      else
        last3 = String.slice(int_part, (len - 3)..(len - 1))
        rest = String.slice(int_part, 0..(len - 4))

        grouped =
          rest
          |> String.graphemes()
          |> Enum.reverse()
          |> Enum.chunk_every(2)
          |> Enum.map(&Enum.reverse/1)
          |> Enum.reverse()
          |> Enum.map(&Enum.join/1)
          |> Enum.join(",")

        "#{grouped},#{last3}"
      end

    "#{sign}#{formatted}"
  end

  defp format_grant_label(lot) do
    case lot.plan_type do
      "ESPP" ->
        "—"

      _ ->
        base = lot.grant_number || "—"

        case Map.get(lot, :vest_period) do
          nil -> base
          period -> "#{base} ##{period}"
        end
    end
  end

  defp format_tax_impact(nil), do: "₹0"

  defp format_tax_impact(%Decimal{} = d) do
    cond do
      Decimal.negative?(d) -> "Saves ₹#{format_inr(Decimal.abs(d))}"
      Decimal.compare(d, Decimal.new(0)) == :eq -> "₹0"
      true -> "+₹#{format_inr(d)}"
    end
  end

  defp tax_impact_class(nil), do: ""

  defp tax_impact_class(%Decimal{} = d) do
    cond do
      Decimal.negative?(d) -> "text-green-600"
      Decimal.positive?(d) -> "text-red-600"
      true -> ""
    end
  end

  defp gain_class(nil), do: ""

  defp gain_class(%Decimal{} = d) do
    cond do
      Decimal.positive?(d) -> "text-green-600"
      Decimal.negative?(d) -> "text-red-600"
      true -> ""
    end
  end

  defp plan_badge("RSU"), do: "badge-primary"
  defp plan_badge("ESPP"), do: "badge-secondary"
  defp plan_badge(_), do: "badge-ghost"

  defp gain_type_badge(:STCG), do: "badge badge-xs badge-warning"
  defp gain_type_badge(:STCL), do: "badge badge-xs badge-error"
  defp gain_type_badge(:LTCG), do: "badge badge-xs badge-success"
  defp gain_type_badge(:LTCL), do: "badge badge-xs badge-info"
  defp gain_type_badge(_), do: "badge badge-xs badge-ghost"

  defp mode_label("shares"), do: "shares"
  defp mode_label("usd"), do: "USD"
  defp mode_label("inr"), do: "INR"

  defp mode_suffix("shares"), do: "shares"
  defp mode_suffix("usd"), do: "USD value"
  defp mode_suffix("inr"), do: "INR value"

  defp fy_label do
    today = Date.utc_today()
    fy_year = if today.month >= 4, do: today.year, else: today.year - 1
    next = rem(fy_year + 1, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "FY #{fy_year}-#{next}"
  end

  defp net_fy_value(baseline, type) do
    case type do
      :st -> Decimal.sub(baseline.realized_st_gain, baseline.realized_st_loss)
      :lt -> Decimal.sub(baseline.realized_lt_gain, baseline.realized_lt_loss)
    end
  end

  # ============================================================
  # Render
  # ============================================================

  @impl true
  def render(assigns) do
    ~H"""
    <.context_bar
      symbols={@held_symbols}
      active_symbol={@symbol}
      prices={if @symbol, do: %{@symbol => @current_price}, else: %{}}
      last_upload_at={@last_upload_at}
    />
    <div class="max-w-6xl mx-auto py-6 px-4" id="sell-advisor" phx-hook="Download">
      <div class="flex items-center justify-between mb-4">
        <h1 class="text-2xl font-bold">Sell Advisor</h1>
        <StockPlanWeb.Layouts.fx_rate_display
          info={@current_fx_info}
          open={@fx_info_open}
          format={:compact}
        />
      </div>

      <%!-- Input Section --%>
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body py-4">
          <div class="flex flex-wrap items-end gap-4">
            <div>
              <label class="text-sm font-semibold mb-2 block">I want to sell:</label>
              <div class="flex gap-2">
                <button
                  :for={m <- ["shares", "usd", "inr"]}
                  phx-click="set_mode"
                  phx-value-mode={m}
                  class={"btn btn-sm " <> if(@mode == m, do: "btn-primary", else: "btn-outline")}
                >
                  {mode_label(m)}
                </button>
              </div>
            </div>
            <form phx-change="update_input" phx-submit="advise" class="flex items-end gap-4 flex-1">
              <div class="flex-1 max-w-xs">
                <input
                  type="text"
                  inputmode="decimal"
                  name="target"
                  value={@target_input}
                  placeholder={"Enter #{mode_suffix(@mode)}..."}
                  class="input input-bordered w-full"
                />
              </div>
              <button type="submit" class="btn btn-primary">
                Advise
              </button>
            </form>
          </div>

          <%= if @total_sellable do %>
            <div class="text-xs text-base-content/50 mt-2">
              Total sellable: {format_qty(@total_sellable)} shares
              <%= if @current_price do %>
                <%= if @mode == "inr" and @current_fx do %>
                  <span class="ml-2">
                    (₹{format_inr(
                      Decimal.mult(Decimal.mult(@total_sellable, @current_price), @current_fx)
                    )})
                  </span>
                <% else %>
                  <span class="ml-2">
                    ({format_usd(Decimal.mult(@total_sellable, @current_price))})
                  </span>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Error --%>
      <%= if @error do %>
        <div class="alert alert-error mb-4">
          <span>{@error}</span>
        </div>
      <% end %>

      <%!-- Warnings --%>
      <%= for w <- @warnings do %>
        <div class="alert alert-warning mb-2">
          <span>{w}</span>
        </div>
      <% end %>

      <%!-- FY Context --%>
      <%= if @fy_baseline do %>
        <div class="flex gap-6 mb-4 text-sm text-base-content/60">
          <span class="font-semibold">{fy_label()} context:</span>
          <span>
            STCG:
            <span class={gain_class(net_fy_value(@fy_baseline, :st))}>
              ₹{format_inr(net_fy_value(@fy_baseline, :st))}
            </span>
          </span>
          <span>
            LTCG:
            <span class={gain_class(net_fy_value(@fy_baseline, :lt))}>
              ₹{format_inr(net_fy_value(@fy_baseline, :lt))}
            </span>
          </span>
        </div>
      <% end %>

      <%!-- Basket Results --%>
      <%= if @baskets do %>
        <div class="space-y-4">
          <%= for {basket, idx} <- Enum.with_index(@baskets) do %>
            <% proceeds =
              SellAdvisor.compute_basket_proceeds(basket, @current_price, @current_fx) %>
            <% expanded = MapSet.member?(@expanded, basket.name) %>
            <div class="card bg-base-100 shadow">
              <div class="card-body py-4">
                <%!-- Basket Header --%>
                <div class="flex justify-between items-start">
                  <div>
                    <h3 class="font-bold text-lg">
                      Basket {idx + 1}: {basket.name}
                    </h3>
                    <div class="flex flex-wrap gap-x-6 gap-y-1 mt-1 text-sm">
                      <span>
                        <span class="text-base-content/50">Shares:</span>
                        <span class="font-mono font-semibold">
                          {format_qty(basket.total_shares)}
                          <%= if basket.overshoot do %>
                            <span class="text-xs text-info">(+{format_qty(basket.overshoot)})</span>
                          <% end %>
                        </span>
                      </span>
                      <span>
                        <span class="text-base-content/50">Proceeds:</span>
                        <span class="font-mono">₹{format_inr(proceeds.total_proceeds_inr)}</span>
                      </span>
                      <span>
                        <span class="text-base-content/50">Tax impact:</span>
                        <span class={"font-mono " <> tax_impact_class(basket[:tax_impact])}>
                          {format_tax_impact(basket[:tax_impact])}
                        </span>
                      </span>
                      <span>
                        <span class="text-base-content/50">Charges:</span>
                        <span class="font-mono">{format_usd(basket.charges.total_charges_usd)}</span>
                      </span>
                      <span>
                        <span class="text-base-content/50">Net:</span>
                        <span class="font-mono font-semibold text-success">
                          ₹{format_inr(proceeds.net_proceeds_inr)}
                        </span>
                      </span>
                    </div>
                    <div class="flex gap-4 mt-1 text-xs text-base-content/50">
                      <span>
                        STCG: {format_qty(basket.stcg_shares)} shr / ₹{format_inr(basket.stcg_tax_inr)} tax
                      </span>
                      <span>
                        LTCG: {format_qty(basket.ltcg_shares)} shr / ₹{format_inr(basket.ltcg_tax_inr)} tax
                      </span>
                      <span>
                        {basket.charges.order_count} order(s)
                      </span>
                      <%= if basket[:tax_before_sale] do %>
                        <span>
                          FY tax ₹{format_inr(basket.tax_before_sale)} → ₹{format_inr(
                            basket.tax_after_sale
                          )}
                        </span>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex gap-2">
                    <button
                      phx-click="toggle_expand"
                      phx-value-basket={basket.name}
                      class="btn btn-sm btn-ghost"
                    >
                      {if expanded, do: "▾ Hide lots", else: "▸ View lots"}
                    </button>
                    <button
                      phx-click="download_csv"
                      phx-value-basket={idx}
                      class="btn btn-sm btn-outline"
                    >
                      CSV
                    </button>
                  </div>
                </div>

                <%!-- Overshoot note for Basket 2 --%>
                <%= if basket.overshoot && basket.name == "Cost Optimized" do %>
                  <div class="text-xs text-info mt-1">
                    Sells {format_qty(basket.overshoot)} extra share(s) to avoid partial lot / reduce cost
                  </div>
                <% end %>

                <%!-- Partial fill warning --%>
                <%= if not basket.fills_target do %>
                  <div class="alert alert-warning mt-2 py-2">
                    <span class="text-sm">
                      Insufficient shares. Target: {format_qty(basket.target_shares)}, Available: {format_qty(
                        basket.total_shares
                      )}, Shortfall: {format_qty(basket.shortfall)}
                    </span>
                  </div>
                <% end %>

                <%!-- Expanded Lot Detail --%>
                <%= if expanded do %>
                  <div class="overflow-x-auto mt-3">
                    <table class="table table-sm table-zebra w-full">
                      <thead>
                        <tr class="text-xs">
                          <th>Plan Type</th>
                          <th>Grant #</th>
                          <th>Vest Date</th>
                          <th class="text-right">Qty</th>
                          <th class="text-right">Cost Basis</th>
                          <th class="text-right">Current Price</th>
                          <th>Gain Type</th>
                          <th class="text-right">Est. Gain (INR)</th>
                          <th class="text-right">Est. Tax (INR)</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for e <- basket.entries do %>
                          <tr>
                            <td>
                              <span class={"badge badge-xs " <> plan_badge(e.lot.plan_type)}>
                                {e.lot.plan_type}
                              </span>
                            </td>
                            <td class="font-mono text-xs">{format_grant_label(e.lot)}</td>
                            <td class="text-xs">{format_date(e.lot.vest_date)}</td>
                            <td class="text-right font-mono text-xs">{format_qty(e.qty_to_sell)}</td>
                            <td class="text-right font-mono text-xs">
                              <div>{format_usd(e.lot.cost_basis)}</div>
                              <div class="text-[10px] text-base-content/50">
                                ₹{format_inr(e.lot.cost_basis_inr)}
                              </div>
                            </td>
                            <td class="text-right font-mono text-xs">
                              <div>{format_usd(@current_price)}</div>
                              <div class="text-[10px] text-base-content/50">
                                ₹{format_inr(e.lot.current_value_inr)}
                              </div>
                            </td>
                            <td>
                              <span class={gain_type_badge(e.gain_type)}>
                                {Atom.to_string(e.gain_type)}
                              </span>
                            </td>
                            <td class={"text-right font-mono text-xs " <> gain_class(e.gain_inr)}>
                              ₹{format_inr(e.gain_inr)}
                            </td>
                            <td class="text-right font-mono text-xs">
                              ₹{format_inr(e.tax_inr)}
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Disclaimer --%>
      <div class="text-xs text-base-content/40 mt-6">
        <p>
          Estimates only. Tax rates: STCG 31.2% (30% + 4% cess), LTCG 13% (12.5% + 4% cess). Consult your tax advisor.
        </p>
      </div>
    </div>
    """
  end
end
