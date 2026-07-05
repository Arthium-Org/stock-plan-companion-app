defmodule StockPlanWeb.PortfolioLive do
  use StockPlanWeb, :live_view

  alias StockPlan.Portfolio
  alias StockPlan.Ingestions

  @account_id "default"

  @impl true
  def mount(_params, _session, socket) do
    has_bh = Ingestions.any_active_bh?(@account_id)
    has_holdings = Ingestions.has_active_holdings?(@account_id)
    bh_has_current_shares = has_bh and Ingestions.bh_has_current_shares?(@account_id)

    portfolio_state =
      cond do
        not has_bh -> :no_data
        not bh_has_current_shares -> :all_sold
        not has_holdings -> :holdings_required
        true -> :active
      end

    base =
      socket
      |> assign(:page_title, "Portfolio")
      |> assign(:last_upload_at, Ingestions.latest_upload_at(@account_id))
      |> assign(:portfolio_state, portfolio_state)

    if portfolio_state != :active do
      {:ok, base}
    else
      hierarchical = Portfolio.build(@account_id)
      flat = Portfolio.flat_holdings(hierarchical)
      symbols = Portfolio.held_symbols(@account_id)
      current_prices = Map.new(symbols, fn s -> {s, StockPlan.StockPrice.current_price(s)} end)
      current_fx = StockPlan.FX.current_rate()
      current_fx_info = StockPlan.FX.current_rate_info()
      symbol_summaries = Portfolio.symbol_summaries(@account_id, current_prices, current_fx)
      summary = compute_summary_multi(flat, parsed_prices(current_prices))

      {:ok,
       base
       |> assign(:hierarchical, hierarchical)
       |> assign(:flat_holdings, flat)
       |> assign(:symbols, symbols)
       |> assign(:current_prices, current_prices)
       |> assign(:symbol_summaries, symbol_summaries)
       |> assign(:current_fx, current_fx)
       |> assign(:current_fx_info, current_fx_info)
       |> assign(:fx_info_open, false)
       |> assign(:currency, "USD")
       |> assign(:active_tab, "status")
       |> assign(:status_expanded, MapSet.new(["VESTED"]))
       |> assign(:filters, %{
         vested: true,
         unvested: true,
         pnl: nil,
         symbols: MapSet.new(symbols)
       })
       |> assign(:expanded, MapSet.new())
       |> assign(:grant_sort, {:grant_date, :asc})
       |> assign(:summary, summary)
       |> assign_filtered()}
    end
  end

  @impl true
  def handle_event("toggle_currency", %{"currency" => currency}, socket) do
    {:noreply, assign(socket, currency: currency)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, socket |> assign(active_tab: tab) |> assign_filtered()}
  end

  def handle_event("toggle_filter", %{"filter" => filter}, socket) do
    filters = socket.assigns.filters

    new_filters =
      case filter do
        "vested" -> %{filters | vested: !filters.vested}
        "unvested" -> %{filters | unvested: !filters.unvested}
        "profit" -> %{filters | pnl: if(filters.pnl == :profit, do: nil, else: :profit)}
        "loss" -> %{filters | pnl: if(filters.pnl == :loss, do: nil, else: :loss)}
      end

    {:noreply, socket |> assign(filters: new_filters) |> assign_filtered()}
  end

  def handle_event("toggle_symbol_filter", %{"symbol" => sym}, socket) do
    filters = socket.assigns.filters

    new_symbols =
      if MapSet.member?(filters.symbols, sym),
        do: MapSet.delete(filters.symbols, sym),
        else: MapSet.put(filters.symbols, sym)

    {:noreply, socket |> assign(filters: %{filters | symbols: new_symbols}) |> assign_filtered()}
  end

  def handle_event("show_fx_info", _params, socket) do
    {:noreply, assign(socket, fx_info_open: true)}
  end

  def handle_event("hide_fx_info", _params, socket) do
    {:noreply, assign(socket, fx_info_open: false)}
  end

  def handle_event("toggle_expand", %{"key" => key}, socket) do
    expanded = socket.assigns.expanded

    new_expanded =
      if MapSet.member?(expanded, key),
        do: MapSet.delete(expanded, key),
        else: MapSet.put(expanded, key)

    {:noreply, assign(socket, expanded: new_expanded)}
  end

  def handle_event("toggle_status_expand", %{"status" => status}, socket) do
    se = socket.assigns.status_expanded

    new_se =
      if MapSet.member?(se, status),
        do: MapSet.delete(se, status),
        else: MapSet.put(se, status)

    {:noreply, assign(socket, status_expanded: new_se)}
  end

  def handle_event("sort_grants", %{"field" => field}, socket) do
    field_atom = String.to_existing_atom(field)
    {current_field, current_dir} = socket.assigns.grant_sort

    new_sort =
      if current_field == field_atom do
        {field_atom, if(current_dir == :asc, do: :desc, else: :asc)}
      else
        {field_atom, :asc}
      end

    {:noreply, socket |> assign(grant_sort: new_sort) |> assign_filtered()}
  end

  # --- Computed assigns ---

  defp assign_filtered(socket) do
    flat = socket.assigns.flat_holdings
    prices = parsed_prices(socket.assigns.current_prices)

    filtered_flat = apply_filters(flat, socket.assigns.filters, prices)
    summary = compute_summary_multi(filtered_flat, prices)

    # Build filtered hierarchical for "By Type" view
    filtered_by_type =
      build_filtered_hierarchical(
        socket.assigns.hierarchical,
        filtered_flat,
        socket.assigns.grant_sort,
        prices
      )

    # Build status-grouped for "By Status" view
    by_status = %{
      "VESTED" =>
        Enum.filter(filtered_flat, &(&1.status == "VESTED")) |> Enum.sort_by(& &1.vest_date, Date),
      "UNVESTED" =>
        Enum.filter(filtered_flat, &(&1.status == "UNVESTED"))
        |> Enum.sort_by(& &1.vest_date, Date)
    }

    assign(socket,
      filtered_flat: filtered_flat,
      filtered_by_type: filtered_by_type,
      espp_origins: filtered_by_type["ESPP"] || [],
      rsu_origins: filtered_by_type["RSU"] || [],
      by_status: by_status,
      summary: summary
    )
  end

  defp apply_filters(holdings, filters, prices) do
    holdings
    |> Enum.filter(fn h ->
      status_ok =
        case h.status do
          "VESTED" -> filters.vested
          "UNVESTED" -> filters.unvested
          _ -> true
        end

      # Profit/Loss filters apply ONLY to vested rows
      pnl_ok =
        case filters.pnl do
          nil ->
            true

          :profit ->
            h.status != "VESTED" or
              (compute_pnl(h, prices) != nil and Decimal.positive?(compute_pnl(h, prices)))

          :loss ->
            h.status != "VESTED" or
              (compute_pnl(h, prices) != nil and Decimal.negative?(compute_pnl(h, prices)))
        end

      sym_ok = MapSet.member?(filters.symbols, h.symbol)

      status_ok and pnl_ok and sym_ok
    end)
  end

  defp build_filtered_hierarchical(hierarchical, filtered_flat, grant_sort, prices) do
    filtered_ids = MapSet.new(filtered_flat, & &1.tranche_id)

    hierarchical
    |> Enum.map(fn {plan_type, origins} ->
      filtered_origins =
        origins
        |> Enum.map(fn origin ->
          filtered_tranches =
            Enum.filter(origin.tranches, &MapSet.member?(filtered_ids, &1.tranche_id))

          vested = Enum.filter(filtered_tranches, &(&1.status == "VESTED"))
          unvested = Enum.filter(filtered_tranches, &(&1.status == "UNVESTED"))

          %{
            origin
            | tranches: filtered_tranches,
              total_qty: Portfolio.sum_qty_pub(filtered_tranches),
              vested_qty: Portfolio.sum_qty_pub(vested),
              unvested_qty: Portfolio.sum_qty_pub(unvested),
              vested_count: length(vested),
              unvested_count: length(unvested)
          }
        end)
        |> Enum.reject(fn o -> o.tranches == [] end)
        |> sort_origins(grant_sort, prices)

      {plan_type, filtered_origins}
    end)
    |> Map.new()
  end

  defp sort_origins(origins, {field, direction}, prices) do
    sorted =
      case field do
        :grant_date ->
          Enum.sort_by(origins, & &1.origin_date, Date)

        :total_quantity ->
          Enum.sort_by(origins, fn o -> o.total_quantity || Decimal.new(0) end, Decimal)

        :current_value ->
          Enum.sort_by(origins, fn o -> compute_origin_value(o, prices) end, Decimal)

        :pnl ->
          Enum.sort_by(origins, fn o -> compute_origin_pnl(o, prices) end, Decimal)

        _ ->
          Enum.sort_by(origins, & &1.origin_date, Date)
      end

    if direction == :desc, do: Enum.reverse(sorted), else: sorted
  end

  # --- Display helpers ---

  defp price_for(prices, symbol), do: Map.get(prices || %{}, symbol)

  defp compute_value(qty, price) do
    q = qty || Decimal.new(0)
    p = price || Decimal.new(0)
    Decimal.mult(q, p)
  end

  defp compute_pnl(h, prices) do
    if h.status == "VESTED" and h.cost_basis_per_share != nil do
      qty = h.quantity || Decimal.new(0)
      p = price_for(prices, h.symbol) || Decimal.new(0)
      value = Decimal.mult(qty, p)
      cost = Decimal.mult(qty, h.cost_basis_per_share)
      Decimal.sub(value, cost)
    else
      nil
    end
  end

  defp compute_origin_value(origin, prices) do
    p = price_for(prices, origin.symbol)

    origin.tranches
    |> Enum.filter(&(&1.status == "VESTED"))
    |> Enum.reduce(Decimal.new(0), fn t, acc ->
      Decimal.add(acc, compute_value(t.quantity, p))
    end)
  end

  defp compute_origin_potential(origin, prices) do
    p = price_for(prices, origin.symbol)

    origin.tranches
    |> Enum.filter(&(&1.status == "UNVESTED"))
    |> Enum.reduce(Decimal.new(0), fn t, acc ->
      Decimal.add(acc, compute_value(t.quantity, p))
    end)
  end

  defp compute_origin_pnl(origin, prices) do
    origin.tranches
    |> Enum.filter(&(&1.status == "VESTED"))
    |> Enum.reduce(Decimal.new(0), fn t, acc ->
      case compute_pnl(t, prices) do
        nil -> acc
        pnl -> Decimal.add(acc, pnl)
      end
    end)
  end

  defp parsed_prices(prices_map) do
    Map.new(prices_map || %{}, fn {sym, p} -> {sym, parse_decimal(p)} end)
  end

  defp compute_summary_multi(filtered_flat, prices) do
    vested = Enum.filter(filtered_flat, &(&1.status == "VESTED"))
    unvested = Enum.filter(filtered_flat, &(&1.status == "UNVESTED"))

    current_value =
      Enum.reduce(vested, Decimal.new(0), fn h, acc ->
        p = price_for(prices, h.symbol) || Decimal.new(0)
        Decimal.add(acc, Decimal.mult(h.quantity || Decimal.new(0), p))
      end)

    potential_value =
      Enum.reduce(unvested, Decimal.new(0), fn h, acc ->
        p = price_for(prices, h.symbol) || Decimal.new(0)
        Decimal.add(acc, Decimal.mult(h.quantity || Decimal.new(0), p))
      end)

    by_plan_type =
      filtered_flat
      |> Enum.group_by(& &1.plan_type)
      |> Enum.map(fn {pt, rows} ->
        v = Enum.filter(rows, &(&1.status == "VESTED"))
        u = Enum.filter(rows, &(&1.status == "UNVESTED"))

        vv =
          Enum.reduce(v, Decimal.new(0), fn h, acc ->
            p = price_for(prices, h.symbol) || Decimal.new(0)
            Decimal.add(acc, Decimal.mult(h.quantity || Decimal.new(0), p))
          end)

        pv =
          Enum.reduce(u, Decimal.new(0), fn h, acc ->
            p = price_for(prices, h.symbol) || Decimal.new(0)
            Decimal.add(acc, Decimal.mult(h.quantity || Decimal.new(0), p))
          end)

        {pt, %{current_value: vv, potential_value: pv}}
      end)
      |> Map.new()

    %{
      current_value: current_value,
      potential_value: potential_value,
      total_value: Decimal.add(current_value, potential_value),
      vested_shares: Portfolio.sum_qty_pub(vested),
      unvested_shares: Portfolio.sum_qty_pub(unvested),
      unvested_count: length(unvested),
      by_plan_type: by_plan_type
    }
  end

  defp compute_origin_sellable(origin) do
    origin.tranches
    |> Enum.filter(fn t -> t.status == "VESTED" and t.sellable_qty != nil end)
    |> Enum.reduce(Decimal.new(0), fn t, acc -> Decimal.add(acc, t.sellable_qty) end)
  end

  defp format_number(nil), do: "—"

  defp format_number(%Decimal{} = d) do
    rounded = Decimal.round(d, 2)
    str = Decimal.to_string(rounded)

    {sign, abs_str} =
      if String.starts_with?(str, "-"),
        do: {"-", String.trim_leading(str, "-")},
        else: {"", str}

    {int_part, dec_part} =
      case String.split(abs_str, ".") do
        [i, d] -> {i, String.pad_trailing(d, 2, "0") |> String.slice(0, 2)}
        [i] -> {i, "00"}
      end

    formatted_int =
      int_part
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.reverse/1)
      |> Enum.reverse()
      |> Enum.map(&Enum.join/1)
      |> Enum.join(",")

    "#{sign}#{formatted_int}.#{dec_part}"
  end

  defp format_number(v) when is_binary(v), do: v

  defp format_qty(nil), do: "TBD"
  defp format_qty(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()

  defp format_sellable(status, sellable_qty) do
    if status == "UNVESTED", do: "—", else: format_qty(sellable_qty)
  end

  defp format_currency(nil, _), do: "—"

  defp format_currency(%Decimal{} = d, currency) do
    symbol = if currency == "USD", do: "$", else: "₹"
    rounded = Decimal.round(d, 2)

    if Decimal.negative?(rounded) do
      "-#{symbol}#{format_number(Decimal.abs(rounded))}"
    else
      "#{symbol}#{format_number(rounded)}"
    end
  end

  defp to_inr(nil, _fx), do: nil
  defp to_inr(_val, nil), do: nil
  defp to_inr(%Decimal{} = val, %Decimal{} = fx), do: Decimal.mult(val, fx)

  defp maybe_inr(nil, _, _), do: nil
  defp maybe_inr(val, "USD", _fx), do: val
  defp maybe_inr(val, "INR", fx), do: to_inr(val, fx)

  defp pnl_class(nil), do: ""

  defp pnl_class(%Decimal{} = d) do
    cond do
      Decimal.positive?(d) -> "text-green-600"
      Decimal.negative?(d) -> "text-red-600"
      true -> ""
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(v) when is_binary(v), do: Decimal.new(v)
  defp parse_decimal(%Decimal{} = d), do: d

  defp fmv_indicator(:market_close), do: "*"
  defp fmv_indicator(_), do: ""

  defp expand_key(plan_type, origin_id), do: "#{plan_type}:#{origin_id}"

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%d-%b-%Y")

  defp sort_indicator(grant_sort, field) do
    {current_field, direction} = grant_sort
    if current_field == field, do: if(direction == :asc, do: " ↑", else: " ↓"), else: ""
  end

  @impl true
  def render(%{portfolio_state: :active} = assigns) do
    prices = parsed_prices(assigns.current_prices)
    fx = assigns.current_fx

    assigns =
      assigns
      |> Map.put(:prices, prices)
      |> Map.put(:fx, fx)

    ~H"""
    <.context_bar
      symbols={@symbols}
      prices={@prices}
      last_upload_at={@last_upload_at}
    />
    <div class="max-w-6xl mx-auto py-6 px-4">
      <StockPlanWeb.Layouts.schedule_fa_cta />

      <%!-- Header --%>
      <div class="flex justify-between items-center mb-4">
        <h1 class="text-2xl font-bold">Portfolio</h1>
        <div class="text-right">
          <div class="flex gap-1 justify-end">
            <button
              phx-click="toggle_currency"
              phx-value-currency="USD"
              class={"btn btn-xs " <> if(@currency == "USD", do: "btn-primary", else: "btn-outline")}
            >
              USD
            </button>
            <button
              phx-click="toggle_currency"
              phx-value-currency="INR"
              class={"btn btn-xs " <> if(@currency == "INR", do: "btn-primary", else: "btn-outline")}
            >
              INR
            </button>
          </div>
          <StockPlanWeb.Layouts.fx_rate_display
            info={@current_fx_info}
            open={@fx_info_open}
            format={:inline}
          />
        </div>
      </div>

      <%!-- Per-symbol tiles (when multiple symbols held) --%>
      <%= if length(@symbols) > 1 do %>
        <div class={"grid grid-cols-1 md:grid-cols-#{min(length(@symbol_summaries), 4)} gap-4 mb-4"}>
          <%= for s <- @symbol_summaries do %>
            <div class="stat bg-base-100 shadow rounded-lg">
              <div class="stat-title">{s.symbol}</div>
              <div class="stat-value text-lg">
                {format_currency(maybe_inr(s.current_value_usd, @currency, @fx), @currency)}
              </div>
              <div class="stat-desc">
                {format_qty(s.held_qty)} held ·
                <span class={pnl_class(s.pnl_usd)}>
                  {format_currency(maybe_inr(s.pnl_usd, @currency, @fx), @currency)} P&L
                </span>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Summary Cards --%>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div class="stat bg-base-100 shadow rounded-lg">
          <div class="stat-title">Total Account Value</div>
          <div class="stat-value text-lg">
            {format_currency(maybe_inr(@summary.total_value, @currency, @fx), @currency)}
          </div>
        </div>
        <div class="stat bg-base-100 shadow rounded-lg">
          <div class="stat-title">Current Value</div>
          <div class="stat-value text-lg text-success">
            {format_currency(maybe_inr(@summary.current_value, @currency, @fx), @currency)}
          </div>
          <div class="stat-desc">{format_qty(@summary.vested_shares)} vested shares</div>
        </div>
        <div class="stat bg-base-100 shadow rounded-lg">
          <div class="stat-title">Potential Value</div>
          <div class="stat-value text-lg text-info">
            {format_currency(maybe_inr(@summary.potential_value, @currency, @fx), @currency)}
          </div>
          <div class="stat-desc">
            {format_qty(@summary.unvested_shares)} shares ({@summary.unvested_count} vests)
          </div>
        </div>
      </div>

      <%!-- Tabs --%>
      <div class="tabs tabs-bordered mb-4">
        <a
          phx-click="switch_tab"
          phx-value-tab="status"
          class={"tab " <> if(@active_tab == "status", do: "tab-active", else: "")}
        >
          By Status
        </a>
        <a
          phx-click="switch_tab"
          phx-value-tab="type"
          class={"tab " <> if(@active_tab == "type", do: "tab-active", else: "")}
        >
          By Type
        </a>
      </div>

      <%!-- Filters --%>
      <div class="flex flex-wrap gap-2 mb-6 items-center">
        <span class="text-xs text-base-content/50 mr-1">Filter:</span>
        <button
          phx-click="toggle_filter"
          phx-value-filter="vested"
          class={"btn btn-xs " <> if(@filters.vested, do: "btn-success", else: "btn-outline")}
        >
          Vested
        </button>
        <button
          phx-click="toggle_filter"
          phx-value-filter="unvested"
          class={"btn btn-xs " <> if(@filters.unvested, do: "btn-info", else: "btn-outline")}
        >
          Unvested
        </button>
        <div class="divider divider-horizontal mx-1"></div>
        <button
          phx-click="toggle_filter"
          phx-value-filter="profit"
          class={"btn btn-xs " <> if(@filters.pnl == :profit, do: "btn-success", else: "btn-outline")}
        >
          Profit
        </button>
        <button
          phx-click="toggle_filter"
          phx-value-filter="loss"
          class={"btn btn-xs " <> if(@filters.pnl == :loss, do: "btn-error", else: "btn-outline")}
        >
          Loss
        </button>
        <%= if length(@symbols) > 1 do %>
          <div class="divider divider-horizontal mx-1"></div>
          <%= for sym <- @symbols do %>
            <button
              phx-click="toggle_symbol_filter"
              phx-value-symbol={sym}
              class={"btn btn-xs " <> if(MapSet.member?(@filters.symbols, sym), do: "btn-primary", else: "btn-outline")}
            >
              {sym}
            </button>
          <% end %>
        <% end %>
      </div>

      <%!-- Content --%>
      <%= if @active_tab == "type" do %>
        {render_by_type(assigns)}
      <% else %>
        {render_by_status(assigns)}
      <% end %>

      <%!-- Footer --%>
      <div class="text-xs text-base-content/40 mt-6">
        <p>* Market Adjusted Close (actual FMV unavailable)</p>
        <p>FX: SBI TT Buying Rate (2020+), RBI Reference Rate (earlier)</p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <.context_bar last_upload_at={@last_upload_at} />
    <div class="max-w-6xl mx-auto py-6 px-4">
      <h1 class="text-2xl font-bold mb-6">Portfolio</h1>
      <%= case @portfolio_state do %>
        <% :no_data -> %>
          <div class="alert alert-info">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="stroke-current shrink-0 w-6 h-6"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              >
              </path>
            </svg>
            <span>Upload a Benefit History file to get started.</span>
          </div>
        <% :all_sold -> %>
          <div class="alert alert-info">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="stroke-current shrink-0 w-6 h-6"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              >
              </path>
            </svg>
            <span>All positions appear to be sold — see History for your transaction record.</span>
          </div>
        <% :holdings_required -> %>
          <div class="alert alert-warning">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="stroke-current shrink-0 w-6 h-6"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              >
              </path>
            </svg>
            <span>Upload a Holdings (ByBenefitType) file to view your portfolio.</span>
          </div>
        <% _ -> %>
      <% end %>
    </div>
    """
  end

  # --- By Type View ---

  defp render_by_type(assigns) do
    ~H"""
    <%!-- ESPP Section --%>
    <div class="mb-6">
      <div class="bg-base-200 px-4 py-3 rounded-t-lg flex justify-between items-center">
        <h2 class="font-bold">Employee Stock Purchase Plan (ESPP)</h2>
        <%= if @espp_origins != [] do %>
          <div class="text-sm text-base-content/70 flex gap-4">
            <span>
              Qty: <span class="font-mono">{format_qty(espp_total_qty(@espp_origins))}</span>
            </span>
            <span>
              Value:
              <span class="font-mono">
                {format_currency(
                  maybe_inr(espp_total_value(@espp_origins, @prices), @currency, @fx),
                  @currency
                )}
              </span>
            </span>
            <span class={pnl_class(espp_total_pnl(@espp_origins, @prices))}>
              P&L:
              <span class="font-mono">
                {format_currency(
                  maybe_inr(espp_total_pnl(@espp_origins, @prices), @currency, @fx),
                  @currency
                )}
              </span>
            </span>
          </div>
        <% end %>
      </div>

      <%= if @espp_origins == [] do %>
        <div class="text-center py-8 text-base-content/40 border border-t-0 border-base-200 rounded-b-lg">
          No matching holdings
        </div>
      <% else %>
        <table class="table table-sm w-full border border-t-0 border-base-200 rounded-b-lg">
          <thead>
            <tr class="text-xs">
              <th class="w-6"></th>
              <th>Symbol</th>
              <th
                class="cursor-pointer select-none"
                phx-click="sort_grants"
                phx-value-field="grant_date"
              >
                Grant Date{sort_indicator(@grant_sort, :grant_date)}
              </th>
              <th class="text-right">Lock-In Price</th>
              <th class="text-right">Qty</th>
              <th
                class="text-right cursor-pointer select-none"
                phx-click="sort_grants"
                phx-value-field="current_value"
              >
                Current Value{sort_indicator(@grant_sort, :current_value)}
              </th>
              <th
                class="text-right cursor-pointer select-none"
                phx-click="sort_grants"
                phx-value-field="pnl"
              >
                P&L{sort_indicator(@grant_sort, :pnl)}
              </th>
            </tr>
          </thead>
          <tbody>
            <%= for origin <- @espp_origins do %>
              <% key = expand_key("ESPP", origin.origin_id) %>
              <% expanded = MapSet.member?(@expanded, key) %>
              <% o_value = compute_origin_value(origin, @prices) %>
              <% o_pnl = compute_origin_pnl(origin, @prices) %>
              <tr
                class="cursor-pointer hover:bg-base-200/50 font-medium"
                phx-click="toggle_expand"
                phx-value-key={key}
              >
                <td class="w-6">{if expanded, do: "▾", else: "▸"}</td>
                <td class="font-mono text-xs">{origin.symbol}</td>
                <td>{format_date(origin.origin_date)}</td>
                <td class="text-right font-mono text-sm">
                  {format_currency(maybe_inr(origin.origin_fmv, @currency, @fx), @currency)}
                </td>
                <td class="text-right font-mono">{format_qty(origin.total_qty)}</td>
                <td class="text-right font-mono">
                  {format_currency(maybe_inr(o_value, @currency, @fx), @currency)}
                </td>
                <td class={"text-right font-mono " <> pnl_class(o_pnl)}>
                  {format_currency(maybe_inr(o_pnl, @currency, @fx), @currency)}
                </td>
              </tr>
              <%= if expanded do %>
                <tr>
                  <td></td>
                  <td colspan="6">
                    <table class="table table-xs ml-6 bg-base-200/30 border border-base-300 rounded w-full">
                      <thead>
                        <tr class="text-xs font-semibold text-base-content/50">
                          <th>Purchase Date</th>
                          <th class="text-right">
                            <span class="tooltip" data-tip="Purchase Date FMV (ESPP)">
                              Cost Basis (FMV)
                            </span>
                          </th>
                          <th class="text-right">Qty</th>
                          <th class="text-right">Sellable</th>
                          <th class="text-right">Market Value</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for t <- origin.tranches do %>
                          <% t_value = compute_value(t.quantity, @prices[t.symbol]) %>
                          <tr class="text-sm">
                            <td class="text-xs">{format_date(t.vest_date)}</td>
                            <td class="text-right font-mono text-xs">
                              {format_currency(
                                maybe_inr(t.cost_basis_per_share, @currency, @fx),
                                @currency
                              )}<span class="text-warning">{fmv_indicator(t.cost_basis_source)}</span>
                            </td>
                            <td class="text-right font-mono text-xs">{format_qty(t.quantity)}</td>
                            <td class="text-right font-mono text-xs">
                              {format_sellable(t.status, t.sellable_qty)}
                            </td>
                            <td class="text-right font-mono text-xs">
                              {format_currency(maybe_inr(t_value, @currency, @fx), @currency)}
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </td>
                </tr>
              <% end %>
            <% end %>
            <tr class="font-bold bg-base-200">
              <td></td>
              <td></td>
              <td>Total</td>
              <td></td>
              <td class="text-right font-mono">{format_qty(espp_total_qty(@espp_origins))}</td>
              <td class="text-right font-mono">
                {format_currency(
                  maybe_inr(espp_total_value(@espp_origins, @prices), @currency, @fx),
                  @currency
                )}
              </td>
              <td class={"text-right font-mono " <> pnl_class(espp_total_pnl(@espp_origins, @prices))}>
                {format_currency(
                  maybe_inr(espp_total_pnl(@espp_origins, @prices), @currency, @fx),
                  @currency
                )}
              </td>
            </tr>
          </tbody>
        </table>
        <div class="text-xs text-base-content/50 mt-1 px-2">
          {length(@espp_origins)} grants, {Enum.reduce(@espp_origins, 0, fn o, acc ->
            acc + length(o.tranches)
          end)} tranches
        </div>
      <% end %>
    </div>

    <%!-- RSU Section --%>
    <div class="mb-6">
      <div class="bg-base-200 px-4 py-3 rounded-t-lg flex justify-between items-center">
        <h2 class="font-bold">Restricted Stock (RS)</h2>
        <%= if @rsu_origins != [] do %>
          <div class="text-sm text-base-content/70 flex gap-4">
            <span>
              Vested:
              <span class="font-mono">
                {format_qty(rsu_vested_shares(@rsu_origins))} shares
                ({format_qty(rsu_sellable_shares(@rsu_origins))} sellable)
              </span>
            </span>
            <span>
              Unvested:
              <span class="font-mono">
                {format_qty(rsu_unvested_shares(@rsu_origins))} shares
              </span>
            </span>
            <span>
              Value:
              <span class="font-mono">
                {format_currency(
                  maybe_inr(rsu_total_value(@rsu_origins, @prices), @currency, @fx),
                  @currency
                )}
              </span>
            </span>
            <span class="italic text-base-content/50">
              Potential:
              <span class="font-mono">
                {format_currency(
                  maybe_inr(rsu_total_potential(@rsu_origins, @prices), @currency, @fx),
                  @currency
                )}
              </span>
            </span>
          </div>
        <% end %>
      </div>

      <%= if @rsu_origins == [] do %>
        <div class="text-center py-8 text-base-content/40 border border-t-0 border-base-200 rounded-b-lg">
          No matching holdings
        </div>
      <% else %>
        <table class="table table-sm w-full border border-t-0 border-base-200 rounded-b-lg">
          <thead>
            <tr class="text-xs">
              <th class="w-6"></th>
              <th>Symbol</th>
              <th>Grant #</th>
              <th
                class="cursor-pointer select-none"
                phx-click="sort_grants"
                phx-value-field="grant_date"
              >
                Grant Date{sort_indicator(@grant_sort, :grant_date)}
              </th>
              <th
                class="text-right cursor-pointer select-none"
                phx-click="sort_grants"
                phx-value-field="total_quantity"
              >
                Granted{sort_indicator(@grant_sort, :total_quantity)}
              </th>
              <th class="text-right">Vested</th>
              <th class="text-right">Sellable</th>
              <th class="text-right">Unvested</th>
              <th
                class="text-right cursor-pointer select-none"
                phx-click="sort_grants"
                phx-value-field="current_value"
              >
                Current Value{sort_indicator(@grant_sort, :current_value)}
              </th>
              <th class="text-right italic text-base-content/60">Potential</th>
              <th
                class="text-right cursor-pointer select-none"
                phx-click="sort_grants"
                phx-value-field="pnl"
              >
                P&L{sort_indicator(@grant_sort, :pnl)}
              </th>
            </tr>
          </thead>
          <tbody>
            <%= for origin <- @rsu_origins do %>
              <% key = expand_key("RSU", origin.origin_id) %>
              <% expanded = MapSet.member?(@expanded, key) %>
              <% o_value = compute_origin_value(origin, @prices) %>
              <% o_potential = compute_origin_potential(origin, @prices) %>
              <% o_pnl = compute_origin_pnl(origin, @prices) %>
              <% o_sellable = compute_origin_sellable(origin) %>
              <tr
                class="cursor-pointer hover:bg-base-200/50 font-medium"
                phx-click="toggle_expand"
                phx-value-key={key}
              >
                <td class="w-6">{if expanded, do: "▾", else: "▸"}</td>
                <td class="font-mono text-xs">{origin.symbol}</td>
                <td class="font-mono text-xs">{origin.grant_number}</td>
                <td class="text-xs">{format_date(origin.origin_date)}</td>
                <td class="text-right font-mono">{format_qty(origin.total_quantity)}</td>
                <td class="text-right font-mono">{format_qty(origin.vested_qty)}</td>
                <td class="text-right font-mono">{format_qty(o_sellable)}</td>
                <td class="text-right font-mono">{format_qty(origin.unvested_qty)}</td>
                <td class="text-right font-mono">
                  {format_currency(maybe_inr(o_value, @currency, @fx), @currency)}
                </td>
                <td class="text-right font-mono italic text-base-content/50">
                  {if Decimal.gt?(o_potential, Decimal.new(0)),
                    do: format_currency(maybe_inr(o_potential, @currency, @fx), @currency),
                    else: "—"}
                </td>
                <td class={"text-right font-mono " <> pnl_class(o_pnl)}>
                  {format_currency(maybe_inr(o_pnl, @currency, @fx), @currency)}
                </td>
              </tr>
              <%= if expanded do %>
                <tr>
                  <td></td>
                  <td colspan="10">
                    <table class="table table-xs ml-6 bg-base-200/30 border border-base-300 rounded w-full">
                      <thead>
                        <tr class="text-xs font-semibold text-base-content/50">
                          <th>#</th>
                          <th>Vest Date</th>
                          <th class="text-right">Vest Qty</th>
                          <th class="text-right">Released</th>
                          <th class="text-right">Sellable</th>
                          <th class="text-right">
                            <span class="tooltip" data-tip="Vest Date FMV (RSU)">
                              Cost Basis
                            </span>
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for t <- origin.tranches do %>
                          <tr class={"text-sm " <> if(t.status == "UNVESTED", do: "italic text-base-content/50", else: "")}>
                            <td class="font-mono text-xs">{t.vest_period || "—"}</td>
                            <td class="text-xs">{format_date(t.vest_date)}</td>
                            <td class="text-right font-mono text-xs">
                              {format_qty(t.vested_qty_raw)}
                            </td>
                            <td class="text-right font-mono text-xs">
                              {format_qty(t.released_qty)}
                            </td>
                            <td class="text-right font-mono text-xs">
                              {format_sellable(t.status, t.sellable_qty)}
                            </td>
                            <td class="text-right font-mono text-xs">
                              <%= if t.cost_basis_per_share do %>
                                {format_currency(
                                  maybe_inr(t.cost_basis_per_share, @currency, @fx),
                                  @currency
                                )}<span class="text-warning">{fmv_indicator(t.cost_basis_source)}</span>
                              <% else %>
                                <span class="text-base-content/30">—</span>
                              <% end %>
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </td>
                </tr>
              <% end %>
            <% end %>
            <% rsu_total_granted =
              Enum.reduce(@rsu_origins, Decimal.new(0), fn o, acc ->
                Decimal.add(acc, o.total_quantity || Decimal.new(0))
              end)

            rsu_total_vested = rsu_vested_shares(@rsu_origins)
            rsu_total_sellable = rsu_sellable_shares(@rsu_origins)
            rsu_total_unvested = rsu_unvested_shares(@rsu_origins)
            rsu_total_val = rsu_total_value(@rsu_origins, @prices)
            rsu_total_pot = rsu_total_potential(@rsu_origins, @prices)

            rsu_total_pnl =
              Enum.reduce(@rsu_origins, Decimal.new(0), fn o, acc ->
                Decimal.add(acc, compute_origin_pnl(o, @prices))
              end) %>
            <tr class="font-bold bg-base-200">
              <td></td>
              <td></td>
              <td></td>
              <td>Total</td>
              <td class="text-right font-mono">{format_qty(rsu_total_granted)}</td>
              <td class="text-right font-mono">{format_qty(rsu_total_vested)}</td>
              <td class="text-right font-mono">{format_qty(rsu_total_sellable)}</td>
              <td class="text-right font-mono">{format_qty(rsu_total_unvested)}</td>
              <td class="text-right font-mono">
                {format_currency(maybe_inr(rsu_total_val, @currency, @fx), @currency)}
              </td>
              <td class="text-right font-mono italic text-base-content/50">
                {if Decimal.gt?(rsu_total_pot, Decimal.new(0)),
                  do: format_currency(maybe_inr(rsu_total_pot, @currency, @fx), @currency),
                  else: "—"}
              </td>
              <td class={"text-right font-mono " <> pnl_class(rsu_total_pnl)}>
                {format_currency(maybe_inr(rsu_total_pnl, @currency, @fx), @currency)}
              </td>
            </tr>
          </tbody>
        </table>
        <div class="text-xs text-base-content/50 mt-1 px-2">
          {length(@rsu_origins)} grants, {Enum.reduce(@rsu_origins, 0, fn o, acc ->
            acc + length(o.tranches)
          end)} tranches
        </div>
      <% end %>
    </div>
    """
  end

  # --- By Status View ---

  defp render_by_status(assigns) do
    ~H"""
    <%= for {status, label} <- [{"VESTED", "Vested"}, {"UNVESTED", "Unvested"}] do %>
      <% rows = @by_status[status] || [] %>
      <% expanded = MapSet.member?(@status_expanded, status) %>
      <div class="mb-6">
        <div
          class="bg-base-200 px-4 py-3 rounded-t-lg cursor-pointer flex justify-between items-center"
          phx-click="toggle_status_expand"
          phx-value-status={status}
        >
          <h2 class="font-bold">
            {if expanded, do: "▾", else: "▸"}
            <span class="ml-1">{label}</span>
            <span class="text-sm font-normal text-base-content/50 ml-2">({length(rows)})</span>
          </h2>
        </div>
        <%= if rows == [] do %>
          <div class="text-center py-8 text-base-content/40 border border-t-0 border-base-200 rounded-b-lg">
            No matching holdings
          </div>
        <% else %>
          <%= if expanded do %>
            <table class="table table-sm table-zebra w-full border border-t-0 border-base-200 rounded-b-lg">
              <thead>
                <tr class="text-xs">
                  <th>Type</th>
                  <th>Symbol</th>
                  <th>Grant #</th>
                  <th>Vest Date</th>
                  <th class="text-right">Qty</th>
                  <th class="text-right">Cost Basis</th>
                  <th class="text-right">Value</th>
                  <th class="text-right">P&L</th>
                </tr>
              </thead>
              <tbody>
                <%= for h <- rows do %>
                  <% value = compute_value(h.quantity, @prices[h.symbol]) %>
                  <% pnl = compute_pnl(h, @prices) %>
                  <% d_value = maybe_inr(value, @currency, @fx) %>
                  <% d_pnl = maybe_inr(pnl, @currency, @fx) %>
                  <tr class={if(h.status == "UNVESTED", do: "italic text-base-content/50", else: "")}>
                    <td>
                      <span class={"badge badge-xs " <> if(h.plan_type == "RSU", do: "badge-primary", else: "badge-secondary")}>
                        {h.plan_type}
                      </span>
                    </td>
                    <td class="font-mono text-xs">{h.symbol}</td>
                    <td class="font-mono text-xs">
                      {if h.plan_type == "ESPP", do: "—", else: h.grant_number}
                    </td>
                    <td class="text-xs">{format_date(h.vest_date)}</td>
                    <td class="text-right font-mono text-xs">{format_qty(h.quantity)}</td>
                    <td class="text-right text-xs">
                      <%= if h.cost_basis_per_share do %>
                        {format_currency(maybe_inr(h.cost_basis_per_share, @currency, @fx), @currency)}<span class="text-warning">{fmv_indicator(h.cost_basis_source)}</span>
                      <% else %>
                        <span class="text-base-content/30">—</span>
                      <% end %>
                    </td>
                    <td class="text-right font-mono text-xs">
                      {format_currency(d_value, @currency)}
                    </td>
                    <td class={"text-right font-mono text-xs " <> pnl_class(d_pnl)}>
                      {if d_pnl, do: format_currency(d_pnl, @currency), else: "—"}
                    </td>
                  </tr>
                <% end %>
                <% total_qty = status_total_qty(rows) %>
                <% total_value = status_total_value(rows, @prices) %>
                <%= if status == "VESTED" do %>
                  <% total_pnl = status_total_pnl(rows, @prices) %>
                  <tr class="font-bold bg-base-200">
                    <td></td>
                    <td></td>
                    <td></td>
                    <td>Total</td>
                    <td class="text-right font-mono">{format_qty(total_qty)}</td>
                    <td></td>
                    <td class="text-right font-mono">
                      {format_currency(maybe_inr(total_value, @currency, @fx), @currency)}
                    </td>
                    <td class={"text-right font-mono " <> pnl_class(maybe_inr(total_pnl, @currency, @fx))}>
                      {format_currency(maybe_inr(total_pnl, @currency, @fx), @currency)}
                    </td>
                  </tr>
                <% else %>
                  <tr class="font-bold bg-base-200">
                    <td></td>
                    <td></td>
                    <td></td>
                    <td>Total</td>
                    <td class="text-right font-mono">{format_qty(total_qty)}</td>
                    <td></td>
                    <td class="text-right font-mono">
                      {format_currency(maybe_inr(total_value, @currency, @fx), @currency)}
                    </td>
                    <td></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        <% end %>
      </div>
    <% end %>
    """
  end

  # --- Section summary helpers ---

  defp espp_total_qty(origins),
    do: Enum.reduce(origins, Decimal.new(0), fn o, acc -> Decimal.add(acc, o.total_qty) end)

  defp espp_total_value(origins, price),
    do:
      Enum.reduce(origins, Decimal.new(0), fn o, acc ->
        Decimal.add(acc, compute_origin_value(o, price))
      end)

  defp espp_total_pnl(origins, price),
    do:
      Enum.reduce(origins, Decimal.new(0), fn o, acc ->
        Decimal.add(acc, compute_origin_pnl(o, price))
      end)

  defp rsu_vested_shares(origins),
    do: Enum.reduce(origins, Decimal.new(0), fn o, acc -> Decimal.add(acc, o.vested_qty) end)

  defp rsu_unvested_shares(origins),
    do: Enum.reduce(origins, Decimal.new(0), fn o, acc -> Decimal.add(acc, o.unvested_qty) end)

  defp rsu_sellable_shares(origins),
    do:
      Enum.reduce(origins, Decimal.new(0), fn o, acc ->
        Decimal.add(acc, compute_origin_sellable(o))
      end)

  defp rsu_total_value(origins, price),
    do:
      Enum.reduce(origins, Decimal.new(0), fn o, acc ->
        Decimal.add(acc, compute_origin_value(o, price))
      end)

  defp rsu_total_potential(origins, price),
    do:
      Enum.reduce(origins, Decimal.new(0), fn o, acc ->
        Decimal.add(acc, compute_origin_potential(o, price))
      end)

  defp status_total_qty(rows),
    do:
      Enum.reduce(rows, Decimal.new(0), fn h, acc ->
        Decimal.add(acc, h.quantity || Decimal.new(0))
      end)

  defp status_total_value(rows, prices),
    do:
      Enum.reduce(rows, Decimal.new(0), fn h, acc ->
        Decimal.add(acc, compute_value(h.quantity, price_for(prices, h.symbol)))
      end)

  defp status_total_pnl(rows, prices),
    do:
      Enum.reduce(rows, Decimal.new(0), fn h, acc ->
        case compute_pnl(h, prices) do
          nil -> acc
          pnl -> Decimal.add(acc, pnl)
        end
      end)
end
