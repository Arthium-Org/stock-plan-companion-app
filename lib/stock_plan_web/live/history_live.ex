defmodule StockPlanWeb.HistoryLive do
  use StockPlanWeb, :live_view

  import StockPlanWeb.Components.Charts

  alias StockPlan.{History, Ingestions}

  @account_id "default"

  @impl true
  def mount(_params, _session, socket) do
    analysis = History.build(@account_id)
    symbols = analysis.symbols
    active_symbol = List.first(symbols)
    active_plan = default_plan(analysis, active_symbol)

    {:ok,
     socket
     |> assign(:page_title, "Benefits History")
     |> assign(:last_upload_at, Ingestions.latest_upload_at(@account_id))
     |> assign(:symbols, symbols)
     |> assign(:active_symbol, active_symbol)
     |> assign(:active_plan, active_plan)
     |> assign(:analysis, analysis)
     |> assign(:prices, analysis.prices)
     |> assign(:prices_fetched_at, analysis.prices_fetched_at)
     |> assign(:currency, "INR")
     |> assign(:espp_lots_expanded, false)
     |> assign(:rsu_grants_expanded, false)}
  end

  @impl true
  def handle_event("select_symbol", %{"symbol" => sym}, socket) do
    plan =
      if has_plan?(socket.assigns.analysis, sym, socket.assigns.active_plan),
        do: socket.assigns.active_plan,
        else: default_plan(socket.assigns.analysis, sym)

    {:noreply,
     socket
     |> assign(:active_symbol, sym)
     |> assign(:active_plan, plan)
     |> assign(:espp_lots_expanded, false)
     |> assign(:rsu_grants_expanded, false)}
  end

  @impl true
  def handle_event("select_plan", %{"plan" => plan}, socket) do
    {:noreply, assign(socket, :active_plan, plan)}
  end

  @impl true
  def handle_event("toggle_currency", %{"currency" => currency}, socket) do
    {:noreply, assign(socket, :currency, currency)}
  end

  @impl true
  def handle_event("toggle_espp_lots_table", _, socket) do
    {:noreply, assign(socket, :espp_lots_expanded, not socket.assigns.espp_lots_expanded)}
  end

  @impl true
  def handle_event("toggle_rsu_grants_table", _, socket) do
    {:noreply, assign(socket, :rsu_grants_expanded, not socket.assigns.rsu_grants_expanded)}
  end

  # ----------------------------------------------------------------
  # Render
  # ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <.context_bar
      symbols={@symbols}
      active_symbol={@active_symbol}
      prices={@prices}
      prices_fetched_at={@prices_fetched_at}
      last_upload_at={@last_upload_at}
    />
    <div class="max-w-6xl mx-auto py-8 px-4 space-y-6">
      <%= if @active_symbol == nil do %>
        <h1 class="text-2xl font-bold">Benefits History</h1>
        <div class="alert alert-warning text-sm">
          No data uploaded yet. <.link href={~p"/upload"}>Upload your Benefit History</.link>
          to see analyses.
        </div>
      <% else %>
        <%!-- Page header --%>
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Benefits History</h1>
          <div class="flex items-center gap-1">
            <button
              phx-click="toggle_currency"
              phx-value-currency="INR"
              class={"btn btn-xs #{if @currency == "INR", do: "btn-primary", else: "btn-outline"}"}
            >
              ₹ INR
            </button>
            <button
              phx-click="toggle_currency"
              phx-value-currency="USD"
              class={"btn btn-xs #{if @currency == "USD", do: "btn-primary", else: "btn-outline"}"}
            >
              $ USD
            </button>
          </div>
        </div>

        <%!-- Plan tabs --%>
        <div class="flex border-b border-base-300">
          <button
            class={"px-6 py-2 text-sm font-medium border-b-2 -mb-px transition-colors #{if @active_plan == "RSU", do: "border-primary text-primary", else: "border-transparent text-base-content/50 hover:text-base-content hover:border-base-300"}"}
            phx-click="select_plan"
            phx-value-plan="RSU"
          >
            RSU
          </button>
          <button
            class={"px-6 py-2 text-sm font-medium border-b-2 -mb-px transition-colors #{if @active_plan == "ESPP", do: "border-primary text-primary", else: "border-transparent text-base-content/50 hover:text-base-content hover:border-base-300"}"}
            phx-click="select_plan"
            phx-value-plan="ESPP"
          >
            ESPP
          </button>
        </div>

        <%!-- RSU tab --%>
        <%= if @active_plan == "RSU" do %>
          <% rsu = @analysis.rsu[@active_symbol] %>
          <%= if rsu == nil or rsu.grants == [] do %>
            <p class="text-base-content/50 py-8">No RSU data for {@active_symbol}.</p>
          <% else %>
            <%!-- RSU summary — 2 rows, 7 tiles --%>
            <section>
              <%!-- Row 1: Income snapshot --%>
              <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-3">
                <.hint_stat
                  label="Grants"
                  value={Integer.to_string(rsu.summary.grant_count)}
                  tip="Count of RSU grant records"
                />
                <.hint_stat
                  label="Grant promise"
                  value={fmt_money(pick(rsu.summary, :grant_promise, @currency), @currency)}
                  tip="Σ(granted qty × grant-date FMV) — equity compensation at award-day prices"
                />
                <.hint_stat
                  label="Income recognized"
                  value={fmt_money(pick(rsu.summary, :income_recognized, @currency), @currency)}
                  tip="Σ(vest qty × vest-date FMV) on vested tranches — what was taxed as salary"
                />
                <.hint_stat
                  label="Still to vest (est.)"
                  value={fmt_money(pick(rsu.summary, :still_to_vest, @currency), @currency)}
                  tip="Unvested gross shares × today's stock price — estimate only, not received income"
                />
              </div>
              <%!-- Row 2: Shares + drift --%>
              <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
                <.hint_stat
                  label="Vested (net shares)"
                  value={fmt_qty(rsu.summary.vested_net_shares)}
                  tip="Net shares delivered after tax withholding across all vested tranches"
                />
                <.hint_stat
                  label="Unvested (gross shares)"
                  value={fmt_qty(rsu.summary.unvested_gross_shares)}
                  tip="Scheduled gross shares not yet delivered"
                />
                <.hint_stat
                  label="Vest vs grant drift"
                  value={fmt_drift(rsu.summary.vest_vs_grant_drift_pct)}
                  tip="Vest FMV vs grant FMV on vested shares — positive means stock appreciated since grant"
                  pnl={rsu.summary.vest_vs_grant_drift_pct}
                />
              </div>
            </section>

            <%!-- Chart A: RSU income by financial year --%>
            <section id="rsu-income-chart">
              <h2 class="text-lg font-semibold mb-1">RSU income by financial year</h2>
              <p class="text-xs text-base-content/50 mb-2">
                Total compensation that vested each completed financial year (Apr–Mar)
              </p>
              <.area_line_chart
                categories={Enum.map(rsu.income_by_year, & &1.year)}
                series={[
                  %{
                    values: Enum.map(rsu.income_by_year, &pick_year_val(&1, @currency)),
                    color: "#6366F1"
                  }
                ]}
                currency={@currency}
              />
              <p class="text-xs text-base-content/40 mt-1">
                Source: VESTED tranches · values in {if @currency == "INR", do: "₹", else: "$"}
              </p>
            </section>

            <%!-- Grant breakdown table --%>
            <section id="rsu-grants">
              <h2 class="text-lg font-semibold mb-3">Grant breakdown</h2>
              <div class={
                if not @rsu_grants_expanded and length(rsu.grants) > 5,
                  do: "max-h-52 overflow-y-auto",
                  else: ""
              }>
                <div class="overflow-x-auto">
                  <table class="table table-sm table-zebra w-full text-xs">
                    <thead class="sticky top-0 bg-base-100">
                      <tr>
                        <th>Grant #</th>
                        <th>Grant date</th>
                        <th class="text-right">Granted</th>
                        <th class="text-right">Grant value</th>
                        <th class="text-right">Income earned</th>
                        <th class="text-right">Still to vest</th>
                        <th class="text-right">% Vested</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for g <- rsu.grants do %>
                        <tr>
                          <td class="font-mono">{g.grant_number || "—"}</td>
                          <td>{fmt_date(g.grant_date)}</td>
                          <td class="text-right font-mono">{fmt_qty(g.granted_qty)}</td>
                          <td class="text-right font-mono">{fmt_money_usd(g.grant_promise_usd)}</td>
                          <td class="text-right font-mono">{fmt_money_usd(g.recognized_usd)}</td>
                          <td class="text-right font-mono">
                            {fmt_money_usd_nil(g.still_to_vest_usd)}
                          </td>
                          <td class="text-right font-mono">
                            {fmt_pct(g.vested_pct)}
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
              <%= if length(rsu.grants) > 5 do %>
                <div class="flex items-center justify-between mt-2 text-xs text-base-content/50">
                  <%= if not @rsu_grants_expanded do %>
                    <span>Showing 5 of {length(rsu.grants)} grants — scroll or expand</span>
                    <button
                      phx-click="toggle_rsu_grants_table"
                      class="btn btn-xs btn-ghost"
                    >
                      Show all {length(rsu.grants)} grants
                    </button>
                  <% else %>
                    <span></span>
                    <button
                      phx-click="toggle_rsu_grants_table"
                      class="btn btn-xs btn-ghost"
                    >
                      Collapse table
                    </button>
                  <% end %>
                </div>
              <% end %>
            </section>

            <%!-- Chart B: New grant value by year --%>
            <section id="rsu-grants-chart">
              <h2 class="text-lg font-semibold mb-1">New grant value by year</h2>
              <p class="text-xs text-base-content/50 mb-2">
                When fresh equity comp was awarded — separate from when it vests
              </p>
              <.area_line_chart
                categories={Enum.map(rsu.grants_by_year, & &1.year)}
                series={[
                  %{
                    values: Enum.map(rsu.grants_by_year, &pick_year_val(&1, @currency)),
                    color: "#10B981"
                  }
                ]}
                currency={@currency}
              />
            </section>

            <%!-- Disclaimer --%>
            <div class="text-xs text-base-content/40 border-t border-base-300/40 pt-3">
              Still-to-vest estimates use today's stock price — not income you have received.
              Income recognized uses vest-date FMV from your Benefit History upload.
            </div>
          <% end %>
        <% end %>

        <%!-- ESPP tab --%>
        <%= if @active_plan == "ESPP" do %>
          <% espp = @analysis.espp[@active_symbol] %>
          <%= if espp == nil or espp.lots == [] do %>
            <p class="text-base-content/50 py-8">No ESPP data for {@active_symbol}.</p>
          <% else %>
            <%!-- §A Summary v2: 3 rows + return strip --%>
            <section>
              <%!-- Row 1: Share counts --%>
              <div class="grid grid-cols-3 gap-3 mb-3">
                <.hint_stat
                  label="Gross Purchased"
                  value={fmt_qty(espp.summary.gross_purchased)}
                  tip="Total shares purchased (gross) across all ESPP lots"
                />
                <div class="stat bg-base-200 rounded-lg px-4 py-3">
                  <div class="flex items-center gap-1 stat-title text-xs">
                    Net Received
                    <div
                      class="tooltip tooltip-bottom"
                      data-tip={"#{fmt_qty(espp.summary.tax_withheld)} shares withheld for tax (gross − net)"}
                    >
                      <span class="text-base-content/30 cursor-help text-xs">ℹ</span>
                    </div>
                  </div>
                  <div class="stat-value text-base font-mono">
                    {fmt_qty(espp.summary.net_received)}
                  </div>
                </div>
                <.hint_stat
                  label="Currently Held"
                  value={fmt_qty(espp.summary.currently_held)}
                  tip="Net shares not yet sold"
                />
              </div>
              <%!-- Row 2: Money flow --%>
              <div class="grid grid-cols-3 gap-3 mb-3">
                <.hint_stat
                  label="Purchase Value"
                  value={fmt_money(pick(espp.summary, :purchase_value, @currency), @currency)}
                  tip="Σ(gross shares × buy price) — total payroll contributed"
                />
                <.hint_stat
                  label="Net Discount Value"
                  value={fmt_money(pick(espp.summary, :net_discount, @currency), @currency)}
                  tip="Σ((vest FMV − buy price) × net shares) — discount on shares actually received"
                />
                <.hint_stat
                  label="Realized Proceeds"
                  value={fmt_money(pick(espp.summary, :realized_proceeds, @currency), @currency)}
                  tip="Σ(sale price × sold qty) — cash received from sales; — if no G&L uploaded"
                />
              </div>
              <%!-- Row 3: Performance --%>
              <div class="grid grid-cols-3 gap-3 mb-3">
                <.hint_stat
                  label="Realized P&L"
                  value={fmt_money(pick(espp.summary, :realized_pnl, @currency), @currency)}
                  tip="Σ(sale price − net buy price) × sold qty — net_buy_price basis"
                  pnl={espp.summary.realized_pnl_usd}
                />
                <.hint_stat
                  label="Unrealized P&L"
                  value={fmt_money(pick(espp.summary, :unrealized_pnl, @currency), @currency)}
                  tip="Σ(current price − net buy price) × held qty — net_buy_price basis; — if no price"
                  pnl={espp.summary.unrealized_pnl_usd}
                />
                <.hint_stat
                  label="Total P&L"
                  value={fmt_money(pick(espp.summary, :total_pnl, @currency), @currency)}
                  tip="Realized + unrealized P&L combined"
                  pnl={espp.summary.total_pnl_usd}
                />
              </div>
              <%!-- Return strip --%>
              <div class="flex items-center gap-4 bg-base-200/60 border border-base-300/40 rounded-lg px-4 py-2 text-sm">
                <span class="text-base-content/50">Avg return per lot:</span>
                <span class={"font-mono font-semibold #{pnl_class(espp.summary.avg_return_pct)}"}>
                  {fmt_pct_signed(espp.summary.avg_return_pct)}
                </span>
                <span class="text-base-content/30">·</span>
                <span class="text-base-content/50">on net cost basis</span>
              </div>
            </section>

            <%!-- §B Purchase lots table --%>
            <section id="espp-lots">
              <h2 class="text-lg font-semibold mb-3">Purchase Lots ({length(espp.lots)})</h2>
              <div class={
                if not @espp_lots_expanded and length(espp.lots) > 5,
                  do: "max-h-52 overflow-y-auto",
                  else: ""
              }>
                <div class="overflow-x-auto">
                  <table class="table table-sm table-zebra w-full text-xs">
                    <thead class="sticky top-0 bg-base-100">
                      <tr>
                        <th>Purchase Date</th>
                        <th class="text-right">Gross</th>
                        <th class="text-right">Net</th>
                        <th class="text-right">
                          <div class="inline-flex items-center gap-1">
                            Buy Price
                            <div
                              class="tooltip tooltip-bottom"
                              data-tip="Discounted purchase price per share — typically 15% below the lock-in (grant-date) price for the ESPP offering. Payroll deducted at this price, not purchase-day market price (see FMV)."
                            >
                              <span class="text-base-content/30 cursor-help">ℹ</span>
                            </div>
                          </div>
                        </th>
                        <th class="text-right">FMV</th>
                        <th class="text-right">Disc %</th>
                        <th class="text-right">Sold</th>
                        <th class="text-right">Held</th>
                        <th class="text-right">Real. P&L</th>
                        <th class="text-right">Unreal. P&L</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for lot <- espp.lots do %>
                        <tr>
                          <td>{fmt_date(lot.purchase_date)}</td>
                          <td class="text-right font-mono">{fmt_qty(lot.gross_shares)}</td>
                          <td class="text-right font-mono">{fmt_qty(lot.net_shares)}</td>
                          <td class="text-right font-mono">{fmt_money_usd_nil(lot.buy_price)}</td>
                          <td class="text-right font-mono">{fmt_money_usd_nil(lot.purchase_fmv)}</td>
                          <td class="text-right font-mono text-success">
                            {fmt_pct(lot.discount_pct)}
                          </td>
                          <td class="text-right font-mono">{fmt_qty(lot.sold_qty)}</td>
                          <td class="text-right font-mono">{fmt_qty(lot.held_qty)}</td>
                          <td class={"text-right font-mono #{pnl_class(lot.realized_pnl)}"}>
                            {fmt_money_usd_nil(lot.realized_pnl)}
                          </td>
                          <td class={"text-right font-mono #{pnl_class(lot.unrealized_pnl)}"}>
                            {fmt_money_usd_nil(lot.unrealized_pnl)}
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
              <%= if length(espp.lots) > 5 do %>
                <div class="flex items-center justify-between mt-2 text-xs text-base-content/50">
                  <%= if not @espp_lots_expanded do %>
                    <span>Showing 5 of {length(espp.lots)} lots — scroll or expand</span>
                    <button
                      phx-click="toggle_espp_lots_table"
                      class="btn btn-xs btn-ghost"
                    >
                      Show all {length(espp.lots)} lots
                    </button>
                  <% else %>
                    <span></span>
                    <button
                      phx-click="toggle_espp_lots_table"
                      class="btn btn-xs btn-ghost"
                    >
                      Collapse table
                    </button>
                  <% end %>
                </div>
              <% end %>
            </section>

            <%!-- §C Sold lot returns --%>
            <%= if espp.sold_lots != [] do %>
              <section id="espp-sold-pnl">
                <h2 class="text-lg font-semibold mb-1">Sold lot returns</h2>
                <p class="text-xs text-base-content/50 mb-2">
                  Return rate on sold portion — net buy price basis. Hover a bar for details.
                </p>
                <.pnl_bar_chart lots={espp.sold_lots} currency={@currency} />
              </section>
            <% end %>

            <%!-- §D Open lots — cost vs current --%>
            <%= if espp.unsold_lots != [] do %>
              <section id="espp-unsold-basis">
                <h2 class="text-lg font-semibold mb-1">Open lots — cost vs current</h2>
                <p class="text-xs text-base-content/50 mb-2">
                  Each dot is your effective cost per received share. Dashed line = current market price. Hover for unrealized P&amp;L.
                </p>
                <.cost_basis_chart
                  lots={espp.unsold_lots}
                  current_price={espp.current_price}
                  currency={@currency}
                />
              </section>
            <% end %>

            <%!-- §F Sell-on-Purchase analysis --%>
            <%= if sop = espp_sop_analysis(espp.summary, @currency) do %>
              <section id="espp-sop">
                <h2 class="text-lg font-semibold mb-1">
                  Sell-on-Purchase Analysis
                  <div
                    class="tooltip tooltip-bottom inline-block ml-1"
                    data-tip="Compares your current P&L (realized + unrealized at today's price) against a hypothetical where every net share was sold at purchase-date FMV on the next trading day. Excess tax paid in cash is not included (see page disclaimer)."
                  >
                    <span class="text-base-content/30 cursor-help text-sm">(?)</span>
                  </div>
                </h2>
                <p class="text-xs text-base-content/50 mb-4">
                  Historical hypothetical: was holding better than exiting every lot at purchase-day FMV?
                </p>
                <div class="grid grid-cols-3 gap-4 mb-4">
                  <div class="bg-base-200 rounded-xl p-4 text-center">
                    <div class="text-xs text-base-content/50 mb-1">Day-1 exit</div>
                    <div class="text-xl font-mono font-bold text-success">
                      {fmt_money(sop.day1_gain, @currency)}
                    </div>
                    <div class="text-xs font-mono font-semibold mt-1 text-success">
                      {fmt_pct_signed(sop.day1_return_pct)}
                    </div>
                    <div class="text-xs text-base-content/40 mt-0.5">
                      avg per lot · locked in at buy
                    </div>
                  </div>
                  <div class="bg-base-200 rounded-xl p-4 text-center">
                    <div class="text-xs text-base-content/50 mb-1">Current P&L</div>
                    <div class={"text-xl font-mono font-bold #{pnl_class(sop.total_pnl)}"}>
                      {fmt_signed(sop.total_pnl, @currency)}
                    </div>
                    <div class={"text-xs font-mono font-semibold mt-1 #{pnl_class(sop.total_pnl)}"}>
                      {fmt_pct_signed(sop.actual_return_pct)}
                    </div>
                    <div class="text-xs text-base-content/40 mt-0.5">realized + unrealized</div>
                  </div>
                  <div class="bg-base-200 rounded-xl p-4 text-center">
                    <div class="text-xs text-base-content/50 mb-1">Reward for holding</div>
                    <div class={"text-xl font-mono font-bold #{pnl_class(sop.extra_from_holding)}"}>
                      {fmt_signed(sop.extra_from_holding, @currency)}
                    </div>
                    <div class="text-xs text-base-content/40 mt-1">current P&L − day-1 exit</div>
                  </div>
                </div>
                <%!-- Verdict banner --%>
                <div class={"flex items-start gap-3 px-5 py-4 rounded-xl text-base font-semibold mb-3 #{case sop.verdict do
                  :holding_better -> "bg-success/15 text-success"
                  :holding_worse  -> "bg-warning/15 text-warning"
                  :equally_close  -> "bg-base-300/60 text-base-content/70"
                end}"}>
                  <span>
                    {case sop.verdict do
                      :holding_better -> "▲"
                      :holding_worse -> "▼"
                      :equally_close -> "≈"
                    end}
                  </span>
                  <%= case sop.verdict do %>
                    <% :holding_better -> %>
                      <span>
                        <strong>Holding added value</strong>
                        — you are <strong>{fmt_money(sop.extra_from_holding, @currency)}</strong>
                        ahead of a day-1 exit,
                        on top of the <strong>{fmt_money(sop.day1_gain, @currency)}</strong>
                        discount locked in at purchase.
                      </span>
                    <% :holding_worse -> %>
                      <span>
                        <strong>Day-1 exit would have been better</strong>
                        — your total P&L is
                        <strong>{fmt_money(Decimal.abs(sop.extra_from_holding), @currency)}</strong>
                        less than
                        the guaranteed day-1 discount of <strong>{fmt_money(sop.day1_gain, @currency)}</strong>.
                      </span>
                    <% :equally_close -> %>
                      <span>
                        <strong>Effectively the same</strong>
                        — holding vs a day-1 exit made less than 2% difference
                        on average per lot. The
                        <strong>{fmt_money(Decimal.abs(sop.extra_from_holding), @currency)}</strong>
                        gap
                        is within noise given stock price variability at sale time.
                      </span>
                  <% end %>
                </div>
                <%!-- Hindsight disclaimer --%>
                <div class="border border-base-300/60 bg-base-200/40 rounded-xl py-4 px-5 text-sm text-base-content/60">
                  <p class="font-medium text-base-content/70 mb-1">
                    Retrospective only — hindsight bias applies
                  </p>
                  <p class="mb-1.5">
                    This comparison is only clear in hindsight. Stock performance can go either way — holding could just as easily beat a day-1 exit in a rising market as it underperforms in a decline.
                  </p>
                  <p>
                    The better approach: at each purchase event, track your company's fundamentals, market sentiment, and your own tax situation — then decide. Past outcomes from one cycle don't predict the next.
                    This also does not compare against selling current holdings today; for that, see the return strip and Open lots chart above.
                  </p>
                </div>
              </section>
            <% end %>

            <%!-- §3.8 Footer disclaimer --%>
            <div class="text-xs text-base-content/40 border-t border-base-300/40 pt-3">
              Returns and P&amp;L on this page use effective cost per received share (total payroll ÷ net shares per purchase).
              <strong>
                Additional tax paid in cash outside the plan is not reflected in these calculations.
              </strong>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ----------------------------------------------------------------
  # Internal components
  # ----------------------------------------------------------------

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tip, :string, default: nil
  attr :pnl, :any, default: nil

  def hint_stat(assigns) do
    ~H"""
    <div class="stat bg-base-200 rounded-lg px-4 py-3">
      <div class="flex items-center gap-1 stat-title text-xs">
        {@label}
        <%= if @tip do %>
          <div class="tooltip tooltip-bottom" data-tip={@tip}>
            <span class="text-base-content/30 cursor-help text-xs">ℹ</span>
          </div>
        <% end %>
      </div>
      <div class={"stat-value text-base font-mono #{if @pnl, do: pnl_class(@pnl), else: ""}"}>
        {@value}
      </div>
    </div>
    """
  end

  # ----------------------------------------------------------------
  # SOP helper
  # ----------------------------------------------------------------

  defp espp_sop_analysis(summary, currency) do
    {sop, cost, realized, unrealized} =
      if currency == "INR" do
        {summary.sell_on_purchase_inr, summary.purchase_value_inr, summary.realized_pnl_inr,
         summary.unrealized_pnl_inr}
      else
        {summary.sell_on_purchase_usd, summary.purchase_value_usd, summary.realized_pnl_usd,
         summary.unrealized_pnl_usd}
      end

    d0 = Decimal.new(0)

    with %Decimal{} <- sop,
         %Decimal{} <- cost,
         true <- Decimal.gt?(sop, d0) do
      realized = realized || d0
      unrealized = unrealized || d0
      day1_gain = Decimal.sub(sop, cost)
      total_pnl = Decimal.add(realized, unrealized)
      extra_from_holding = Decimal.sub(total_pnl, day1_gain)

      verdict =
        case {summary.avg_day1_return_pct, summary.avg_return_pct} do
          {%Decimal{} = d1, %Decimal{} = act} ->
            diff = Decimal.abs(Decimal.sub(d1, act))

            cond do
              Decimal.lte?(diff, Decimal.new(2)) -> :equally_close
              Decimal.gt?(extra_from_holding, d0) -> :holding_better
              true -> :holding_worse
            end

          _ ->
            if Decimal.gt?(extra_from_holding, d0), do: :holding_better, else: :holding_worse
        end

      %{
        day1_gain: day1_gain,
        extra_from_holding: extra_from_holding,
        total_pnl: total_pnl,
        verdict: verdict,
        day1_return_pct: summary.avg_day1_return_pct,
        actual_return_pct: summary.avg_return_pct
      }
    else
      _ -> nil
    end
  end

  # ----------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------

  defp default_plan(_analysis, nil), do: "RSU"

  defp default_plan(analysis, symbol) do
    rsu = analysis.rsu[symbol]
    if rsu && rsu.grants != [], do: "RSU", else: "ESPP"
  end

  defp has_plan?(analysis, symbol, "RSU") do
    rsu = analysis.rsu[symbol]
    rsu && rsu.grants != []
  end

  defp has_plan?(analysis, symbol, "ESPP") do
    espp = analysis.espp[symbol]
    espp && espp.lots != []
  end

  defp has_plan?(_analysis, _symbol, _), do: false

  # Pick the right currency variant from summary or lot field
  defp pick(map, :grant_promise, "INR"), do: map.grant_promise_inr
  defp pick(map, :grant_promise, _), do: map.grant_promise_usd
  defp pick(map, :income_recognized, "INR"), do: map.income_recognized_inr
  defp pick(map, :income_recognized, _), do: map.income_recognized_usd
  defp pick(map, :still_to_vest, "INR"), do: map.still_to_vest_inr
  defp pick(map, :still_to_vest, _), do: map.still_to_vest_usd
  defp pick(map, :purchase_value, "INR"), do: map.purchase_value_inr
  defp pick(map, :purchase_value, _), do: map.purchase_value_usd
  defp pick(map, :net_discount, "INR"), do: map.net_discount_inr
  defp pick(map, :net_discount, _), do: map.net_discount_usd
  defp pick(map, :realized_proceeds, "INR"), do: map.realized_proceeds_inr
  defp pick(map, :realized_proceeds, _), do: map.realized_proceeds_usd
  defp pick(map, :realized_pnl, "INR"), do: map.realized_pnl_inr
  defp pick(map, :realized_pnl, _), do: map.realized_pnl_usd
  defp pick(map, :unrealized_pnl, "INR"), do: map.unrealized_pnl_inr
  defp pick(map, :unrealized_pnl, _), do: map.unrealized_pnl_usd
  defp pick(map, :total_pnl, "INR"), do: map.total_pnl_inr
  defp pick(map, :total_pnl, _), do: map.total_pnl_usd

  defp pick_year_val(row, "INR"), do: row.value_inr
  defp pick_year_val(row, _), do: row.value_usd

  # ----------------------------------------------------------------
  # Formatters
  # ----------------------------------------------------------------

  defp fmt_qty(nil), do: "—"
  defp fmt_qty(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()

  defp fmt_money(nil, _), do: "—"
  defp fmt_money(%Decimal{} = d, "INR"), do: "₹#{fmt_inr_num(d)}"
  defp fmt_money(%Decimal{} = d, _), do: fmt_usd_num(d)

  defp fmt_money_usd(nil), do: "—"
  defp fmt_money_usd(%Decimal{} = d), do: fmt_usd_num(d)

  defp fmt_money_usd_nil(nil), do: "—"
  defp fmt_money_usd_nil(%Decimal{} = d), do: fmt_usd_num(d)

  defp fmt_usd_num(%Decimal{} = d) do
    val = Decimal.to_float(d)

    cond do
      val >= 1_000_000 -> "$#{Float.round(val / 1_000_000, 2)}M"
      val >= 1_000 -> "$#{Float.round(val / 1_000, 1)}K"
      true -> "$#{Decimal.round(d, 2) |> Decimal.to_string()}"
    end
  end

  defp fmt_inr_num(%Decimal{} = d) do
    rounded = Decimal.round(d, 0)

    if Decimal.compare(rounded, Decimal.new(0)) == :eq do
      "0"
    else
      fmt_indian_number(Decimal.to_string(rounded))
    end
  end

  defp fmt_indian_number(str) do
    {sign, digits} =
      case str do
        "-" <> rest -> {"-", rest}
        rest -> {"", rest}
      end

    {int_part, dec_part} =
      case String.split(digits, ".") do
        [i, d] -> {i, "." <> d}
        [i] -> {i, ""}
      end

    len = String.length(int_part)

    formatted =
      cond do
        len <= 3 ->
          int_part

        len <= 5 ->
          "#{String.slice(int_part, 0, len - 3)},#{String.slice(int_part, len - 3, 3)}"

        true ->
          last3 = String.slice(int_part, len - 3, 3)
          rest_str = String.slice(int_part, 0, len - 3)

          rest_formatted =
            rest_str
            |> String.graphemes()
            |> Enum.reverse()
            |> Enum.chunk_every(2)
            |> Enum.map(&Enum.join(Enum.reverse(&1)))
            |> Enum.reverse()
            |> Enum.join(",")

          "#{rest_formatted},#{last3}"
      end

    "#{sign}#{formatted}#{dec_part}"
  end

  defp fmt_pct(nil), do: "—"
  defp fmt_pct(%Decimal{} = d), do: "#{Decimal.round(d, 1) |> Decimal.to_string()}%"
  defp fmt_pct(f) when is_float(f), do: "#{Float.round(f * 100, 1)}%"

  defp fmt_pct_signed(nil), do: "—"

  defp fmt_pct_signed(%Decimal{} = d) do
    rounded = Decimal.round(d, 1)

    cond do
      Decimal.gt?(d, Decimal.new(0)) -> "+#{Decimal.to_string(rounded)}%"
      Decimal.lt?(d, Decimal.new(0)) -> "#{Decimal.to_string(rounded)}%"
      true -> "0.0%"
    end
  end

  defp fmt_drift(nil), do: "—"

  defp fmt_drift(%Decimal{} = d) do
    sign = if Decimal.gt?(d, Decimal.new(0)), do: "+", else: ""
    "#{sign}#{Decimal.round(d, 1) |> Decimal.to_string()}%"
  end

  defp fmt_date(nil), do: "—"
  defp fmt_date(%Date{} = d), do: Calendar.strftime(d, "%d-%b-%Y")

  defp fmt_signed(nil, _), do: "—"

  defp fmt_signed(%Decimal{} = d, "INR") do
    rounded = Decimal.round(d, 0)

    cond do
      Decimal.gt?(d, Decimal.new(0)) -> "+₹#{fmt_inr_num(rounded)}"
      Decimal.lt?(d, Decimal.new(0)) -> "-₹#{fmt_inr_num(Decimal.abs(rounded))}"
      true -> "₹0"
    end
  end

  defp fmt_signed(%Decimal{} = d, _) do
    rounded = Decimal.round(d, 0)

    cond do
      Decimal.gt?(d, Decimal.new(0)) -> "+$#{Decimal.to_string(rounded)}"
      Decimal.lt?(d, Decimal.new(0)) -> "-$#{Decimal.to_string(Decimal.abs(rounded))}"
      true -> "$0"
    end
  end

  defp pnl_class(nil), do: ""

  defp pnl_class(%Decimal{} = d),
    do: if(Decimal.gt?(d, Decimal.new(0)), do: "text-success", else: "text-error")
end
