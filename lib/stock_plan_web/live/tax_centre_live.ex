defmodule StockPlanWeb.TaxCentreLive do
  use StockPlanWeb, :live_view

  alias StockPlan.Tax.{ScheduleFA, CapitalGains, ScheduleFSI}
  alias StockPlan.Ingestions
  alias StockPlan.Profile

  @account_id "default"

  @impl true
  def mount(_params, _session, socket) do
    current_year = Date.utc_today().year
    current_fy = if Date.utc_today().month >= 4, do: current_year, else: current_year - 1

    # Generate year ranges — only completed CYs (current year not yet ended)
    fa_years = Enum.to_list((current_year - 1)..2018)
    fy_years = Enum.to_list(current_fy..2018)

    {:ok,
     socket
     |> assign(:page_title, "Tax Centre")
     |> assign(:last_upload_at, Ingestions.latest_upload_at(@account_id))
     |> assign(:active_tab, "schedule_fa")
     |> assign(:fa_year, current_year - 1)
     |> assign(:cg_fy, current_fy)
     |> assign(:fa_years, fa_years)
     |> assign(:fy_years, fy_years)
     |> assign(:fa_data, nil)
     |> assign(:fa_error, nil)
     |> assign(:fa_warnings, [])
     |> assign(:cg_data, nil)
     |> assign(:cg_grouped, [])
     |> assign(:cg_expanded_dates, MapSet.new())
     |> assign(:cg_summary, nil)
     |> assign(:cg_view, "grouped")
     |> assign(:fsi_fy, current_fy)
     |> assign(:fsi_data, nil)
     |> assign(:currency, "INR")
     |> assign(:loading, false)
     |> assign(:fa_disclaimer_accepted, Profile.get("schedule_fa_disclaimer_accepted", false))
     |> assign(:show_fa_disclaimer, false)
     |> load_fa_data()}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    socket = assign(socket, active_tab: tab)

    socket =
      case tab do
        "schedule_fa" ->
          if socket.assigns.fa_data == nil do
            load_fa_data(socket)
          else
            socket
          end

        "capital_gains" ->
          if socket.assigns.cg_data == nil do
            load_cg_data(socket)
          else
            socket
          end

        "schedule_fsi" ->
          if socket.assigns.fsi_data == nil do
            load_fsi_data(socket)
          else
            socket
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("select_fa_year", %{"year" => year_str}, socket) do
    year = String.to_integer(year_str)
    {:noreply, socket |> assign(:fa_year, year) |> load_fa_data()}
  end

  def handle_event("select_cg_fy", %{"fy" => fy_str}, socket) do
    fy = String.to_integer(fy_str)
    {:noreply, socket |> assign(:cg_fy, fy) |> load_cg_data()}
  end

  def handle_event("select_fsi_fy", %{"fy" => fy_str}, socket) do
    fy = String.to_integer(fy_str)
    {:noreply, socket |> assign(:fsi_fy, fy) |> load_fsi_data()}
  end

  def handle_event("toggle_cg_date", %{"key" => key_str}, socket) do
    expanded = socket.assigns.cg_expanded_dates

    updated =
      if MapSet.member?(expanded, key_str),
        do: MapSet.delete(expanded, key_str),
        else: MapSet.put(expanded, key_str)

    {:noreply, assign(socket, cg_expanded_dates: updated)}
  end

  def handle_event("toggle_cg_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, cg_view: view)}
  end

  def handle_event("toggle_currency", %{"currency" => currency}, socket) do
    {:noreply, assign(socket, currency: currency)}
  end

  def handle_event("download_fa_csv", _params, socket) do
    {:noreply, push_fa_download(socket)}
  end

  def handle_event("request_fa_download", _params, socket) do
    if socket.assigns.fa_disclaimer_accepted do
      {:noreply, push_fa_download(socket)}
    else
      {:noreply, assign(socket, show_fa_disclaimer: true)}
    end
  end

  def handle_event("accept_fa_disclaimer", _params, socket) do
    Profile.put("schedule_fa_disclaimer_accepted", true)

    socket =
      socket
      |> assign(fa_disclaimer_accepted: true, show_fa_disclaimer: false)
      |> push_fa_download()

    {:noreply, socket}
  end

  def handle_event("cancel_fa_disclaimer", _params, socket) do
    {:noreply, assign(socket, show_fa_disclaimer: false)}
  end

  defp push_fa_download(socket) do
    case socket.assigns.fa_data do
      nil ->
        socket

      [] ->
        socket

      rows ->
        csv = ScheduleFA.to_csv(rows)
        filename = "Schedule_FA_CY#{socket.assigns.fa_year}.csv"

        push_event(socket, "download", %{
          content: Base.encode64(csv),
          filename: filename,
          content_type: "text/csv"
        })
    end
  end

  # ============================================================
  # Data loading
  # ============================================================

  defp load_fa_data(socket) do
    case ScheduleFA.build(@account_id, socket.assigns.fa_year) do
      {:ok, rows, warnings} ->
        assign(socket, fa_data: rows, fa_error: nil, fa_warnings: warnings)

      {:error, {:missing_meta, syms}} ->
        msg =
          "Missing metadata for #{Enum.join(syms, ", ")}. " <>
            "Add entries to priv/stock_meta.json and rebuild before generating Schedule FA."

        assign(socket, fa_data: nil, fa_error: msg, fa_warnings: [])

      {:error, message} when is_binary(message) ->
        assign(socket, fa_data: nil, fa_error: message, fa_warnings: [])
    end
  end

  defp load_cg_data(socket) do
    {rows, summary} = CapitalGains.build(@account_id, socket.assigns.cg_fy)

    rows =
      Enum.sort_by(rows, fn r ->
        {r.sale_date && Date.to_iso8601(r.sale_date), r.vest_date && Date.to_iso8601(r.vest_date)}
      end)

    # Group by {sale_date, order_number} for per-order grouping
    cg_grouped =
      rows
      |> Enum.group_by(fn r -> {r.sale_date, r.order_number} end)
      |> Enum.sort_by(fn {{date, order}, _} ->
        {date && Date.to_iso8601(date), order || ""}
      end)

    assign(socket,
      cg_data: rows,
      cg_grouped: cg_grouped,
      cg_summary: summary,
      cg_expanded_dates: MapSet.new()
    )
  end

  defp load_fsi_data(socket) do
    fsi_data = ScheduleFSI.build(@account_id, socket.assigns.fsi_fy)
    assign(socket, fsi_data: fsi_data)
  end

  # ============================================================
  # Render
  # ============================================================

  @impl true
  def render(assigns) do
    ~H"""
    <.context_bar last_upload_at={@last_upload_at} />
    <div class="max-w-6xl mx-auto py-6 px-4" id="tax-centre" phx-hook="Download">
      <div class="flex justify-between items-center mb-4">
        <h1 class="text-2xl font-bold">Tax Centre</h1>
      </div>

      <%!-- Tabs --%>
      <div class="tabs tabs-bordered mb-6">
        <a
          phx-click="switch_tab"
          phx-value-tab="schedule_fa"
          class={"tab " <> if(@active_tab == "schedule_fa", do: "tab-active", else: "")}
        >
          Schedule FA
        </a>
        <a
          phx-click="switch_tab"
          phx-value-tab="capital_gains"
          class={"tab " <> if(@active_tab == "capital_gains", do: "tab-active", else: "")}
        >
          Capital Gains
        </a>
        <a
          phx-click="switch_tab"
          phx-value-tab="schedule_fsi"
          class={"tab " <> if(@active_tab == "schedule_fsi", do: "tab-active", else: "")}
        >
          Schedule FSI
        </a>
      </div>

      <%!-- Tab Content --%>
      <%= case @active_tab do %>
        <% "schedule_fa" -> %>
          {render_schedule_fa(assigns)}
        <% "capital_gains" -> %>
          {render_capital_gains(assigns)}
        <% "schedule_fsi" -> %>
          {render_schedule_fsi(assigns)}
        <% _ -> %>
          {render_schedule_fa(assigns)}
      <% end %>

      <%!-- Schedule FA download disclaimer modal (accept-once) --%>
      <%= if @show_fa_disclaimer do %>
        <div class="modal modal-open">
          <div class="modal-box max-w-2xl">
            <h3 class="font-bold text-lg mb-1">Before you download — Schedule FA</h3>
            <div class="text-sm space-y-2">
              <p class="font-semibold">Disclaimer</p>
              <ul class="list-disc list-inside space-y-1 ml-2">
                <li>
                  This report is prepared from the trades and information you have uploaded, as available at the time of generation.
                </li>
                <li>
                  We recommend you consult your tax, legal, or accounting advisor while filing your tax returns.
                </li>
                <li>
                  The initial value of an investment is taken as the acquisition cost of the shares held (their grant/purchase cost basis).
                </li>
                <li>
                  <strong>Dividend income is not included</strong>
                  — dividend tracking isn't enabled yet, so the "gross amount paid/credited" column is 0. Report any dividends separately.
                </li>
                <li>
                  USD→INR conversion uses <strong>SBI TT buying rates</strong>
                  (month-end), falling back to RBI reference rates where a TT rate isn't available.
                </li>
                <li>
                  Schedule FA is prepared on a <strong>calendar-year</strong>
                  basis, so figures here may not match statements prepared on the Indian fiscal-year basis.
                </li>
                <li>
                  Stock Plan Manager makes no warranty, express or implied, and assumes no legal or consequential liability for the authenticity or completeness of the data in this report.
                </li>
                <li>
                  Any tax position implied here is based on current tax law, including judicial and administrative interpretation. Tax law changes, at times retroactively, and may result in additional tax, interest, or penalties. If the underlying data is incorrect or incomplete, or the law or its interpretation changes, this report may be inappropriate.
                </li>
                <li>
                  This information is provided for informational purposes only — it is not tax or financial advice.
                </li>
                <li>
                  Investors whose total income exceeds <strong>₹50 lakh</strong>
                  must also complete <strong>Schedule AL</strong>
                  (Assets & Liabilities) in addition to Schedule FA; the same securities must be reported in both. Consult your tax advisor if Schedule AL applies to you.
                </li>
              </ul>
              <p class="italic">By downloading, you accept this.</p>
            </div>
            <div class="modal-action gap-3">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_fa_disclaimer">
                Cancel
              </button>
              <button
                type="button"
                class="btn btn-primary btn-sm"
                phx-click="accept_fa_disclaimer"
              >
                I understand & accept
              </button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="cancel_fa_disclaimer"></div>
        </div>
      <% end %>
    </div>
    """
  end

  # ============================================================
  # Schedule FA Tab
  # ============================================================

  defp render_schedule_fa(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center mb-4">
        <div class="flex items-center gap-3">
          <label class="font-semibold text-sm">Calendar Year:</label>
          <form phx-change="select_fa_year">
            <select class="select select-sm select-bordered" name="year">
              <%= for y <- @fa_years do %>
                <option value={y} selected={y == @fa_year}>{y}</option>
              <% end %>
            </select>
          </form>
        </div>
        <%= if @fa_data != nil and @fa_data != [] do %>
          <button type="button" phx-click="request_fa_download" class="btn btn-sm btn-outline">
            Download CSV
          </button>
        <% end %>
      </div>

      <%= if @fa_data != nil and @fa_data != [] do %>
        <div class="alert alert-warning mb-4 text-sm">
          <span>
            <strong>Dividends not included.</strong>
            Dividend tracking isn't enabled yet, so the "gross amount paid/credited during the period" column shows <strong>0</strong>. Add any dividend income manually before filing.
          </span>
        </div>
      <% end %>

      <%= if @fa_error do %>
        <div class="alert alert-error mb-4">
          <span>{@fa_error}</span>
          <a href="/upload" class="btn btn-sm btn-outline ml-2">Upload G&L</a>
        </div>
      <% end %>
      <%= cond do %>
        <% @fa_error != nil -> %>
          <div class="text-center py-12 text-base-content/50">
            <p>Schedule FA cannot be generated. Resolve the error above.</p>
          </div>
        <% @fa_data == nil -> %>
          <div class="text-center py-12 text-base-content/50">
            <p>Loading Schedule FA data...</p>
          </div>
        <% @fa_data == [] and @fa_warnings != [] -> %>
          <%!-- Warnings already rendered above; don't also show the contradictory empty-state copy --%>
        <% @fa_data == [] -> %>
          <div class="text-center py-12 text-base-content/50">
            <p>No foreign assets held during CY {@fa_year}.</p>
          </div>
        <% true -> %>
          <% sorted_fa =
            Enum.sort_by(@fa_data, fn r ->
              {r.symbol || "", r.date_acquired && Date.to_iso8601(r.date_acquired)}
            end) %>
          <div class="overflow-x-auto">
            <table class="table table-sm table-zebra w-full">
              <thead>
                <tr class="text-xs">
                  <th>#</th>
                  <th>Symbol</th>
                  <th>Type</th>
                  <th>Date Acquired</th>
                  <th class="text-right">Qty</th>
                  <th class="text-right">Initial Value</th>
                  <th class="text-right">Peak Value</th>
                  <th class="text-right">Peak Price (USD)</th>
                  <th>Peak Date</th>
                  <th class="text-right">Peak FX</th>
                  <th class="text-right">Closing Value</th>
                  <th class="text-right">Sale Proceeds</th>
                </tr>
              </thead>
              <tbody>
                <%= for {row, idx} <- Enum.with_index(sorted_fa, 1) do %>
                  <tr>
                    <td class="text-xs">{idx}</td>
                    <td class="font-mono text-xs">{row.symbol}</td>
                    <td>
                      <span class={"badge badge-xs " <> plan_badge(row.plan_type)}>
                        {row.plan_type}
                      </span>
                    </td>
                    <td class="text-xs">{format_date(row.date_acquired)}</td>
                    <td class="text-right font-mono text-xs">{format_qty(row.quantity_start)}</td>
                    <td class="text-right font-mono text-xs">{format_inr(row.initial_value_inr)}</td>
                    <td class="text-right font-mono text-xs">{format_inr(row.peak_value_inr)}</td>
                    <td class="text-right font-mono text-xs">{format_usd(row.peak_price_usd)}</td>
                    <td class="text-xs">{format_date(row.peak_date)}</td>
                    <td class="text-right font-mono text-xs">{format_fx_rate(row.peak_fx_rate)}</td>
                    <td class="text-right font-mono text-xs">{format_inr(row.closing_value_inr)}</td>
                    <td class="text-right font-mono text-xs">{format_inr(row.sale_proceeds_inr)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
          <div class="text-xs text-base-content/40 mt-4">
            <p>Schedule FA reports foreign assets held during Calendar Year {assigns.fa_year}.</p>
            <p>FX: SBI TT Buying Rate (Rule 115 — previous month end rate).</p>
          </div>
      <% end %>
    </div>
    """
  end

  # ============================================================
  # Capital Gains Tab
  # ============================================================

  defp render_capital_gains(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center mb-4">
        <div class="flex items-center gap-3">
          <label class="font-semibold text-sm">Financial Year:</label>
          <form phx-change="select_cg_fy">
            <select class="select select-sm select-bordered" name="fy">
              <%= for y <- @fy_years do %>
                <option value={y} selected={y == @cg_fy}>
                  FY {y}-{rem(y + 1, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}
                </option>
              <% end %>
            </select>
          </form>
        </div>
      </div>

      <%= cond do %>
        <% @cg_data == nil -> %>
          <div class="text-center py-12 text-base-content/50">
            <p>Loading capital gains data...</p>
          </div>
        <% @cg_data == [] -> %>
          <%= if @cg_summary != nil and @cg_summary.warning != nil do %>
            <div class="alert alert-warning mb-4">
              <span>{@cg_summary.warning}</span>
              <a href="/upload" class="btn btn-sm btn-outline ml-2">Upload G&L</a>
            </div>
          <% end %>
          <div class="text-center py-12 text-base-content/50">
            <p>
              No sale transactions in FY {@cg_fy}-{rem(@cg_fy + 1, 100)
              |> Integer.to_string()
              |> String.pad_leading(2, "0")}.
            </p>
          </div>
        <% true -> %>
          <%!-- Warning Banner for missing G&L coverage --%>
          <%= if @cg_summary.warning != nil do %>
            <div class="alert alert-warning mb-4">
              <span>{@cg_summary.warning}</span>
              <a href="/upload" class="btn btn-sm btn-outline ml-2">Upload G&L</a>
            </div>
          <% end %>
          <%!-- Summary Cards --%>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
            <div class="stat bg-base-100 shadow rounded-lg">
              <div class="stat-title">Short Term (STCG/STCL)</div>
              <div class={"stat-value text-lg " <> gain_class(@cg_summary.stcg_inr)}>
                ₹{format_inr(@cg_summary.stcg_inr)}
              </div>
              <div class="stat-desc">
                Sale: ₹{format_inr(@cg_summary.st_proceeds_inr)} | Cost: ₹{format_inr(
                  @cg_summary.st_cost_inr
                )}
              </div>
            </div>
            <div class="stat bg-base-100 shadow rounded-lg">
              <div class="stat-title">Long Term (LTCG/LTCL)</div>
              <div class={"stat-value text-lg " <> gain_class(@cg_summary.ltcg_inr)}>
                ₹{format_inr(@cg_summary.ltcg_inr)}
              </div>
              <div class="stat-desc">
                Sale: ₹{format_inr(@cg_summary.lt_proceeds_inr)} | Cost: ₹{format_inr(
                  @cg_summary.lt_cost_inr
                )}
              </div>
            </div>
            <div class="stat bg-base-100 shadow rounded-lg">
              <div class="stat-title">Net Gain/Loss</div>
              <div class={"stat-value text-lg " <> gain_class(@cg_summary.net_gain_inr)}>
                ₹{format_inr(@cg_summary.net_gain_inr)}
              </div>
              <div class="stat-desc">
                Sale: ₹{format_inr(@cg_summary.total_proceeds_inr)} | Cost: ₹{format_inr(
                  @cg_summary.total_cost_inr
                )}
              </div>
            </div>
          </div>

          <%!-- View Toggle --%>
          <div class="flex justify-end mb-3">
            <div class="join">
              <button
                phx-click="toggle_cg_view"
                phx-value-view="grouped"
                class={"join-item btn btn-xs " <> if(@cg_view == "grouped", do: "btn-active", else: "")}
              >
                Grouped
              </button>
              <button
                phx-click="toggle_cg_view"
                phx-value-view="flat"
                class={"join-item btn btn-xs " <> if(@cg_view == "flat", do: "btn-active", else: "")}
              >
                Flat
              </button>
            </div>
          </div>

          <%!-- Detail Table --%>
          <div class="overflow-x-auto">
            <%= if @cg_view == "grouped" do %>
              <table class="table table-sm table-zebra w-full">
                <thead>
                  <tr class="text-xs">
                    <th class="w-6"></th>
                    <th>Order #</th>
                    <th>Symbol</th>
                    <th>Type</th>
                    <th>Sell Date</th>
                    <th class="text-right">Qty</th>
                    <th class="text-right">Sell Price</th>
                    <th class="text-right">Acquisition Value</th>
                    <th class="text-right">Sell Value</th>
                    <th class="text-right">Gain/Loss</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {{date, order}, rows} <- @cg_grouped do %>
                    <% date_str = if(date, do: Date.to_iso8601(date), else: "unknown") %>
                    <% group_key = "#{date_str}:#{order || ""}" %>
                    <% expanded = MapSet.member?(@cg_expanded_dates, group_key) %>
                    <% total_qty = sum_decimal(rows, :quantity) %>
                    <% total_cost = sum_decimal(rows, :cost_basis_inr) %>
                    <% total_proceeds = sum_decimal(rows, :proceeds_inr) %>
                    <% net_gain = sum_decimal(rows, :gain_loss_inr) %>
                    <% first_row = List.first(rows) %>
                    <tr
                      class="cursor-pointer hover:bg-base-200/50 font-medium"
                      phx-click="toggle_cg_date"
                      phx-value-key={group_key}
                    >
                      <td class="text-xs">
                        <span class={"inline-block transition-transform " <> if(expanded, do: "rotate-90", else: "")}>
                          &#9654;
                        </span>
                      </td>
                      <td class="font-mono text-xs">{order || "—"}</td>
                      <td class="font-mono text-xs">{first_row && first_row.symbol}</td>
                      <td>
                        <span class={"badge badge-xs " <> plan_badge(first_row && first_row.plan_type)}>
                          {first_row && first_row.plan_type}
                        </span>
                      </td>
                      <td class="text-xs">{format_date(date)}</td>
                      <td class="text-right font-mono text-xs">{format_qty(total_qty)}</td>
                      <td class="text-right font-mono text-xs">
                        <div>{format_usd(first_row && first_row.sale_price)}</div>
                        <div class="text-[10px] text-base-content/50">
                          ₹{format_inr(sale_price_inr(first_row))}
                        </div>
                      </td>
                      <td class="text-right font-mono text-xs">₹{format_inr(total_cost)}</td>
                      <td class="text-right font-mono text-xs">₹{format_inr(total_proceeds)}</td>
                      <td class={"text-right font-mono text-xs " <> gain_class(net_gain)}>
                        ₹{format_inr(net_gain)}
                      </td>
                    </tr>
                    <%= if expanded do %>
                      <tr class="text-[10px] text-base-content/40 uppercase">
                        <td></td>
                        <td colspan="3">Grant #</td>
                        <td>Vest Date</td>
                        <td class="text-right">Qty</td>
                        <td class="text-right">Vest FMV</td>
                        <td class="text-right">Acquisition Value</td>
                        <td class="text-right">Sell Value</td>
                        <td class="text-right">Gain/Loss</td>
                        <td>ST/LT</td>
                      </tr>
                      <%= for row <- Enum.sort_by(rows, & &1.vest_date, Date) do %>
                        <tr class={"bg-base-200/30 " <> if(row.gain_type == :unknown, do: "opacity-60", else: "")}>
                          <td></td>
                          <td colspan="3" class="font-mono text-xs">
                            {if row.plan_type == "ESPP", do: "—", else: row.grant_number || "—"}
                          </td>
                          <td class="text-xs">{format_date(row.vest_date)}</td>
                          <td class="text-right font-mono text-xs">{format_qty(row.quantity)}</td>
                          <td class="text-right font-mono text-xs">
                            <div>{format_usd(row.cost_basis_per_share)}</div>
                            <div class="text-[10px] text-base-content/50">
                              ₹{format_inr(cost_basis_per_share_inr(row))}
                            </div>
                          </td>
                          <td class="text-right font-mono text-xs">
                            ₹{format_inr(row.cost_basis_inr)}
                          </td>
                          <td class="text-right font-mono text-xs">
                            ₹{format_inr(row.proceeds_inr)}
                          </td>
                          <td class={"text-right font-mono text-xs " <> gain_class(row.gain_loss_inr)}>
                            ₹{format_inr(row.gain_loss_inr)}
                          </td>
                          <td>
                            <span class={gain_type_badge(row.gain_type)}>
                              {format_gain_type(row.gain_type)}
                            </span>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  <% end %>
                  <%!-- Totals row --%>
                  <tr class="font-bold bg-base-200">
                    <td></td>
                    <td colspan="4" class="text-xs">TOTAL</td>
                    <td class="text-right font-mono text-xs">
                      {format_qty(sum_decimal(@cg_data, :quantity))}
                    </td>
                    <td></td>
                    <td class="text-right font-mono text-xs">
                      ₹{format_inr(sum_decimal(@cg_data, :cost_basis_inr))}
                    </td>
                    <td class="text-right font-mono text-xs">
                      ₹{format_inr(sum_decimal(@cg_data, :proceeds_inr))}
                    </td>
                    <td class={"text-right font-mono text-xs " <> gain_class(sum_decimal(@cg_data, :gain_loss_inr))}>
                      ₹{format_inr(sum_decimal(@cg_data, :gain_loss_inr))}
                    </td>
                  </tr>
                </tbody>
              </table>
            <% else %>
              <%!-- Flat view --%>
              <table class="table table-sm table-zebra w-full">
                <thead>
                  <tr class="text-xs">
                    <th>Order #</th>
                    <th>Symbol</th>
                    <th>Sell Date</th>
                    <th class="text-right">Qty</th>
                    <th class="text-right">Sell Price</th>
                    <th class="text-right">Sell Value</th>
                    <th>Type</th>
                    <th>Grant #</th>
                    <th>Vest Date</th>
                    <th class="text-right">Vest FMV</th>
                    <th class="text-right">Acquisition Value</th>
                    <th class="text-right">Gain/Loss</th>
                    <th>ST/LT</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for row <- @cg_data do %>
                    <tr class={if(row.gain_type == :unknown, do: "opacity-60", else: "")}>
                      <td class="font-mono text-xs">{row.order_number || "—"}</td>
                      <td class="font-mono text-xs">{row.symbol}</td>
                      <td class="text-xs">{format_date(row.sale_date)}</td>
                      <td class="text-right font-mono text-xs">{format_qty(row.quantity)}</td>
                      <td class="text-right font-mono text-xs">
                        <div>{format_usd(row.sale_price)}</div>
                        <div class="text-[10px] text-base-content/50">
                          ₹{format_inr(sale_price_inr(row))}
                        </div>
                      </td>
                      <td class="text-right font-mono text-xs">₹{format_inr(row.proceeds_inr)}</td>
                      <td>
                        <span class={"badge badge-xs " <> plan_badge(row.plan_type)}>
                          {row.plan_type}
                        </span>
                      </td>
                      <td class="font-mono text-xs">
                        {if row.plan_type == "ESPP", do: "—", else: row.grant_number || "—"}
                      </td>
                      <td class="text-xs">{format_date(row.vest_date)}</td>
                      <td class="text-right font-mono text-xs">
                        <div>{format_usd(row.cost_basis_per_share)}</div>
                        <div class="text-[10px] text-base-content/50">
                          ₹{format_inr(cost_basis_per_share_inr(row))}
                        </div>
                      </td>
                      <td class="text-right font-mono text-xs">₹{format_inr(row.cost_basis_inr)}</td>
                      <td class={"text-right font-mono text-xs " <> gain_class(row.gain_loss_inr)}>
                        ₹{format_inr(row.gain_loss_inr)}
                      </td>
                      <td>
                        <span class={gain_type_badge(row.gain_type)}>
                          {format_gain_type(row.gain_type)}
                        </span>
                      </td>
                    </tr>
                  <% end %>
                  <%!-- Totals row --%>
                  <tr class="font-bold bg-base-200">
                    <td colspan="3" class="text-xs">TOTAL</td>
                    <td class="text-right font-mono text-xs">
                      {format_qty(sum_decimal(@cg_data, :quantity))}
                    </td>
                    <td colspan="2"></td>
                    <td colspan="2"></td>
                    <td class="text-right font-mono text-xs">{format_date(nil)}</td>
                    <td></td>
                    <td class="text-right font-mono text-xs">
                      ₹{format_inr(sum_decimal(@cg_data, :cost_basis_inr))}
                    </td>
                    <td class={"text-right font-mono text-xs " <> gain_class(sum_decimal(@cg_data, :gain_loss_inr))}>
                      ₹{format_inr(sum_decimal(@cg_data, :gain_loss_inr))}
                    </td>
                    <td></td>
                  </tr>
                </tbody>
              </table>
            <% end %>
          </div>

          <div class="text-xs text-base-content/40 mt-4">
            <p>STCG: Holding period of 24 months or less. LTCG: More than 24 months.</p>
            <p>Foreign company shares treated as unlisted under Indian tax law.</p>
            <p>FX: SBI TT Buying Rate (Rule 115).</p>
          </div>
      <% end %>
    </div>
    """
  end

  # ============================================================
  # Schedule FSI Tab
  # ============================================================

  defp render_schedule_fsi(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center mb-4">
        <div class="flex items-center gap-3">
          <label class="font-semibold text-sm">Financial Year:</label>
          <form phx-change="select_fsi_fy">
            <select class="select select-sm select-bordered" name="fy">
              <%= for y <- @fy_years do %>
                <option value={y} selected={y == @fsi_fy}>
                  FY {y}-{rem(y + 1, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}
                </option>
              <% end %>
            </select>
          </form>
        </div>
      </div>

      <%= if @fsi_data == nil do %>
        <div class="text-center py-12 text-base-content/50">
          <p>Loading Schedule FSI data...</p>
        </div>
      <% else %>
        <div class="mb-6">
          <p class="text-sm text-base-content/60 mb-4">
            Schedule FSI is filled manually in the ITR form. Follow the steps below with the values provided.
          </p>
        </div>

        <%!-- Step 1: Country --%>
        <div class="card bg-base-100 shadow mb-4">
          <div class="card-body py-4">
            <h3 class="card-title text-sm">Step 1: Country Details</h3>
            <div class="grid grid-cols-2 gap-4 text-sm mt-2">
              <div>
                <span class="text-base-content/50">Country Code:</span>
                <span class="font-mono font-semibold ml-2">{@fsi_data.country_code}</span>
              </div>
              <div>
                <span class="text-base-content/50">Country:</span>
                <span class="font-semibold ml-2">{@fsi_data.country}</span>
              </div>
              <div class="col-span-2">
                <span class="text-base-content/50">TIN:</span>
                <span class="italic text-base-content/60 ml-2">
                  Enter your US TIN (SSN/ITIN) or Passport Number
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Step 2: Income Heads --%>
        <div class="card bg-base-100 shadow mb-4">
          <div class="card-body py-4">
            <h3 class="card-title text-sm">Step 2: Income from Outside India</h3>
            <p class="text-xs text-base-content/50 mb-3">
              Enter the following values under each head of income:
            </p>

            <div class="space-y-3">
              <%!-- Salary --%>
              <div class="flex items-center gap-4 py-2 px-3 bg-base-200/30 rounded opacity-50">
                <span class="badge badge-sm badge-ghost">i</span>
                <span class="text-sm flex-1">Salary</span>
                <span class="text-xs text-base-content/40">
                  Not applicable — RSU/ESPP perquisite is Indian salary income (Form 16)
                </span>
              </div>

              <%!-- House Property --%>
              <div class="flex items-center gap-4 py-2 px-3 bg-base-200/30 rounded opacity-50">
                <span class="badge badge-sm badge-ghost">ii</span>
                <span class="text-sm flex-1">House Property</span>
                <span class="text-xs text-base-content/40">Not applicable</span>
              </div>

              <%!-- Capital Gains --%>
              <% cg_head = Enum.find(@fsi_data.heads, &(&1.sl_no == "iii")) %>
              <div class="py-3 px-3 bg-base-200/50 rounded border border-base-300">
                <div class="flex items-center gap-4">
                  <span class="badge badge-sm badge-primary">iii</span>
                  <span class="text-sm font-semibold flex-1">Capital Gains</span>
                </div>
                <div class="mt-3 ml-8 space-y-2">
                  <div class="grid grid-cols-2 gap-x-8 gap-y-1 text-sm">
                    <div>
                      <span class="text-base-content/50">Income:</span>
                      <span class="font-mono font-semibold ml-2">
                        {format_inr(cg_head.income_inr)}
                      </span>
                    </div>
                    <div>
                      <span class="text-base-content/50">Tax paid outside India:</span>
                      <span class="font-mono ml-2">0</span>
                      <span class="text-xs text-base-content/40 ml-1">(no US withholding on CG)</span>
                    </div>
                  </div>
                  <%= if cg_head[:income_detail] do %>
                    <div class="text-xs text-base-content/60 mt-1">
                      <span>
                        Breakdown — STCG: {format_fsi_dual(
                          cg_head.income_detail.stcg_usd,
                          cg_head.income_detail.stcg_inr
                        )}
                      </span>
                      <span class="ml-4">
                        LTCG: {format_fsi_dual(
                          cg_head.income_detail.ltcg_usd,
                          cg_head.income_detail.ltcg_inr
                        )}
                      </span>
                    </div>
                    <%= if Decimal.negative?(Decimal.add(cg_head.income_detail.stcg_inr, cg_head.income_detail.ltcg_inr)) do %>
                      <div class="text-xs text-red-600 mt-1">
                        Net capital loss — enter 0 in FSI. Report loss in Schedule CG for carry-forward.
                      </div>
                    <% end %>
                  <% end %>
                  <div class="text-xs text-base-content/50 mt-1">
                    <span class="font-semibold">Tax relief:</span>
                    Not applicable for CG (no US withholding)
                  </div>
                  <div class="text-xs text-base-content/50">
                    <span class="font-semibold">DTAA article:</span> Nil
                  </div>
                </div>
              </div>

              <%!-- Other Sources --%>
              <div class="py-3 px-3 bg-base-200/30 rounded">
                <div class="flex items-center gap-4">
                  <span class="badge badge-sm badge-ghost">iv</span>
                  <span class="text-sm flex-1">Other Sources (Dividends, Interest)</span>
                </div>
                <div class="mt-2 ml-8 text-xs text-base-content/50">
                  Dividend income: not tracked in this app. Enter from broker's 1042-S if applicable.
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Step 3: Tax Payable --%>
        <div class="card bg-base-100 shadow mb-4">
          <div class="card-body py-4">
            <h3 class="card-title text-sm">Step 3: Tax Payable in India</h3>
            <p class="text-xs text-base-content/50">
              This is calculated based on your effective income tax slab rate applied to the capital gains income above.
              Consult your tax advisor or CA for the exact amount.
            </p>
            <div class="mt-2 text-xs text-base-content/50">
              <p>Reference rates (AY 2025-26+): STCG at slab rates (up to 30%), LTCG at 12.5%</p>
            </div>
          </div>
        </div>

        <div class="text-xs text-base-content/40 mt-4">
          <p>No US withholding tax applies on capital gains from share sales for Indian residents.</p>
          <p>
            RSU vest perquisite and ESPP discount are Indian salary income (Form 16) — not reported in Schedule FSI.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  # ============================================================
  # Helpers
  # ============================================================

  defp sum_decimal(rows, field) do
    rows
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp sale_price_inr(nil), do: nil

  defp sale_price_inr(row) do
    if row.proceeds_inr != nil and row.quantity != nil and
         not Decimal.equal?(row.quantity, Decimal.new(0)) do
      Decimal.div(row.proceeds_inr, row.quantity)
    else
      nil
    end
  end

  defp cost_basis_per_share_inr(row) do
    if row.cost_basis_inr != nil and row.quantity != nil and
         not Decimal.equal?(row.quantity, Decimal.new(0)) do
      Decimal.div(row.cost_basis_inr, row.quantity)
    else
      nil
    end
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%d-%b-%Y")

  defp format_qty(nil), do: "—"
  defp format_qty(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()

  defp format_inr(nil), do: "—"

  defp format_inr(%Decimal{} = d) do
    rounded = Decimal.round(d, 0)

    if Decimal.compare(rounded, Decimal.new(0)) == :eq do
      "0"
    else
      formatted = format_indian_number(Decimal.to_string(rounded))
      "#{formatted}"
    end
  end

  defp format_usd(nil), do: "—"
  defp format_usd(%Decimal{} = d), do: "$#{Decimal.round(d, 2) |> Decimal.to_string()}"

  defp format_fx_rate(nil), do: "—"
  defp format_fx_rate(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()

  defp gain_class(nil), do: ""

  defp gain_class(%Decimal{} = d) do
    cond do
      Decimal.positive?(d) -> "text-green-600"
      Decimal.negative?(d) -> "text-red-600"
      true -> ""
    end
  end

  defp format_gain_type(:STCG), do: "STCG"
  defp format_gain_type(:STCL), do: "STCL"
  defp format_gain_type(:LTCG), do: "LTCG"
  defp format_gain_type(:LTCL), do: "LTCL"
  defp format_gain_type(:unknown), do: "Unknown"

  defp gain_type_badge(:STCG), do: "badge badge-xs badge-warning"
  defp gain_type_badge(:STCL), do: "badge badge-xs badge-error"
  defp gain_type_badge(:LTCG), do: "badge badge-xs badge-success"
  defp gain_type_badge(:LTCL), do: "badge badge-xs badge-info"
  defp gain_type_badge(:unknown), do: "badge badge-xs badge-ghost"

  defp plan_badge("RSU"), do: "badge-primary"
  defp plan_badge("ESPP"), do: "badge-secondary"
  defp plan_badge(_), do: "badge-ghost"

  defp format_fsi_amount(%Decimal{} = d) do
    if Decimal.compare(d, Decimal.new(0)) == :eq do
      "0"
    else
      format_indian_number(Decimal.round(d, 0) |> Decimal.to_string())
    end
  end

  defp format_fsi_dual(%Decimal{} = usd, %Decimal{} = inr) do
    "$#{Decimal.round(usd, 2) |> Decimal.to_string()} / #{format_fsi_amount(inr)}"
  end

  defp format_indian_number(str) do
    {sign, abs_str} =
      if String.starts_with?(str, "-"),
        do: {"-", String.trim_leading(str, "-")},
        else: {"", str}

    # Remove any decimal part for INR display
    int_part =
      case String.split(abs_str, ".") do
        [i | _] -> i
      end

    # Indian numbering: last 3 digits, then groups of 2
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
end
