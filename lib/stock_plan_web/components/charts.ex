defmodule StockPlanWeb.Components.Charts do
  @moduledoc "Lightweight SVG chart components. No JS dependency."
  use Phoenix.Component

  @w 600
  @h 200
  @ml 70
  @mr 10
  @mt 10
  @mb 40
  @iw @w - @ml - @mr
  @ih @h - @mt - @mb
  @tick_count 4

  # ----------------------------------------------------------------
  # Bar chart — single series
  # ----------------------------------------------------------------

  attr :labels, :list, required: true
  attr :values, :list, required: true
  attr :currency, :string, default: "INR"
  attr :color, :string, default: "#3B82F6"

  def bar_chart(assigns) do
    chart = build_bars(assigns.labels, assigns.values, assigns.currency)
    assigns = Map.put(assigns, :chart, chart)

    ~H"""
    <%= if @chart.empty? do %>
      <div class="flex items-center justify-center h-16 text-base-content/40 text-sm">No data</div>
    <% else %>
      <svg viewBox="0 0 600 200" class="w-full" aria-hidden="true">
        <%= for tick <- @chart.ticks do %>
          <line x1={70} y1={tick.y} x2={590} y2={tick.y} stroke="#F3F4F6" stroke-width="1" />
          <text x="64" y={tick.y + 4} text-anchor="end" font-size="10" fill="#9CA3AF">
            {tick.label}
          </text>
        <% end %>
        <line x1="70" y1="10" x2="70" y2={160} stroke="#E5E7EB" stroke-width="1" />
        <%= for bar <- @chart.bars do %>
          <rect x={bar.x} y={bar.y} width={bar.bw} height={bar.bh} fill={@color} opacity="0.9" rx="3" />
          <text x={bar.cx} y={174} text-anchor="middle" font-size="10" fill="#9CA3AF">
            {bar.label}
          </text>
        <% end %>
      </svg>
    <% end %>
    """
  end

  # ----------------------------------------------------------------
  # Line chart — RSU income / grant value by year (categories + series, area fill)
  # ----------------------------------------------------------------

  attr :categories, :list, required: true
  attr :series, :list, required: true
  attr :fill, :boolean, default: true
  attr :currency, :string, default: "USD"

  def area_line_chart(assigns) do
    chart = build_area_line(assigns.categories, assigns.series, assigns.currency)
    assigns = Map.put(assigns, :chart, chart)

    ~H"""
    <%= if @chart.empty? do %>
      <div class="flex items-center justify-center h-16 text-base-content/40 text-sm">No data</div>
    <% else %>
      <svg viewBox={"0 0 #{@chart.svg_width} 200"} class="w-full" aria-hidden="true">
        <%= for tick <- @chart.y_ticks do %>
          <line
            x1={70}
            y1={tick.y}
            x2={@chart.svg_width - 10}
            y2={tick.y}
            stroke="#F3F4F6"
            stroke-width="1"
          />
          <text x="64" y={tick.y + 4} text-anchor="end" font-size="10" fill="#9CA3AF">
            {tick.label}
          </text>
        <% end %>
        <%!-- Solid Y-axis and X-axis --%>
        <line x1="70" y1="10" x2="70" y2="160" stroke="#E5E7EB" stroke-width="1" />
        <line x1="70" y1="160" x2={@chart.svg_width - 10} y2="160" stroke="#E5E7EB" stroke-width="1" />
        <%= for s <- @chart.series do %>
          <%= if @fill and length(s.points) > 1 do %>
            <path d={s.area_path} fill={s.color} opacity="0.15" />
          <% end %>
          <%= if length(s.points) > 1 do %>
            <polyline points={points_str(s.points)} fill="none" stroke={s.color} stroke-width="2" />
          <% end %>
          <%= for pt <- s.points do %>
            <g class="group cursor-pointer">
              <circle cx={pt.x} cy={pt.y} r="16" fill="transparent" />
              <circle cx={pt.x} cy={pt.y} r="4" fill={s.color} stroke="white" stroke-width="1.5" />
              <g class="invisible group-hover:visible pointer-events-none">
                <rect
                  x={pt.tt_x}
                  y={pt.tt_y}
                  width="96"
                  height="20"
                  rx="3"
                  fill="#1F2937"
                  opacity="0.92"
                />
                <text
                  x={pt.tt_x + 48}
                  y={pt.tt_y + 14}
                  text-anchor="middle"
                  font-size="9"
                  fill="white"
                >
                  {pt.label}: {pt.value_label}
                </text>
              </g>
            </g>
          <% end %>
        <% end %>
        <%= for cat <- @chart.x_labels do %>
          <%= if @chart.rotate_x do %>
            <text
              x={cat.x}
              y={168}
              text-anchor="end"
              font-size="10"
              fill="#9CA3AF"
              transform={"rotate(-30 #{cat.x} 168)"}
            >
              {cat.label}
            </text>
          <% else %>
            <text x={cat.x} y={174} text-anchor="middle" font-size="10" fill="#9CA3AF">
              {cat.label}
            </text>
          <% end %>
        <% end %>
      </svg>
    <% end %>
    """
  end

  # ----------------------------------------------------------------
  # Signed P&L bar chart — ESPP sold lots return % per purchase lot
  # ----------------------------------------------------------------

  attr :lots, :list, required: true
  attr :currency, :string, default: "USD"

  def pnl_bar_chart(assigns) do
    chart = build_pnl_bars(assigns.lots, assigns.currency)
    assigns = Map.put(assigns, :chart, chart)

    ~H"""
    <%= if @chart.empty? do %>
      <div class="flex items-center justify-center h-16 text-base-content/40 text-sm">
        No sold lots
      </div>
    <% else %>
      <div style="overflow-x: auto">
        <svg
          viewBox={"0 0 #{@chart.svg_width} 200"}
          width={@chart.svg_width}
          style="min-width: 600px"
          aria-hidden="true"
        >
          <%= for tick <- @chart.ticks do %>
            <line
              x1={70}
              y1={tick.y}
              x2={@chart.svg_width - 10}
              y2={tick.y}
              stroke="#F3F4F6"
              stroke-width="1"
            />
            <text x="64" y={tick.y + 4} text-anchor="end" font-size="10" fill="#9CA3AF">
              {tick.label}
            </text>
          <% end %>
          <%!-- Solid Y-axis and X-axis --%>
          <line x1="70" y1="10" x2="70" y2="160" stroke="#E5E7EB" stroke-width="1" />
          <line
            x1="70"
            y1="160"
            x2={@chart.svg_width - 10}
            y2="160"
            stroke="#E5E7EB"
            stroke-width="1"
          />
          <%!-- Dashed 0% baseline --%>
          <line
            x1={70}
            y1={@chart.zero_y}
            x2={@chart.svg_width - 10}
            y2={@chart.zero_y}
            stroke="#D1D5DB"
            stroke-width="1"
            stroke-dasharray="4,2"
          />
          <%= for bar <- @chart.bars do %>
            <g class="group cursor-pointer">
              <rect
                x={bar.x}
                y={bar.y}
                width={bar.bw}
                height={bar.bh}
                fill={if bar.positive, do: "#10B981", else: "#F43F5E"}
                opacity="0.9"
                rx="3"
              />
              <%= if bar.pct_label do %>
                <text
                  x={bar.cx}
                  y={bar.pct_y}
                  text-anchor="middle"
                  font-size="9"
                  font-weight="600"
                  fill={if bar.positive, do: "#059669", else: "#E11D48"}
                >
                  {bar.pct_label}
                </text>
              <% end %>
              <g class="invisible group-hover:visible pointer-events-none">
                <rect
                  x={bar.tt_x}
                  y={bar.tt_y}
                  width="165"
                  height="64"
                  rx="4"
                  fill="#1F2937"
                  opacity="0.92"
                />
                <%= for {line, j} <- Enum.with_index(bar.hover) do %>
                  <text x={bar.tt_x + 8} y={bar.tt_y + 14 + j * 14} font-size="9" fill="white">
                    {line}
                  </text>
                <% end %>
              </g>
            </g>
            <text x={bar.cx} y={174} text-anchor="middle" font-size="9" fill="#9CA3AF">
              {bar.label}
            </text>
          <% end %>
        </svg>
      </div>
    <% end %>
    """
  end

  # ----------------------------------------------------------------
  # Open lots scatter chart — dots at net_buy_price, no polyline
  # ----------------------------------------------------------------

  attr :lots, :list, required: true
  attr :current_price, :any, default: nil
  attr :currency, :string, default: "USD"

  def cost_basis_chart(assigns) do
    chart = build_cost_basis(assigns.lots, assigns.current_price, assigns.currency)
    assigns = Map.put(assigns, :chart, chart)

    ~H"""
    <%= if @chart.empty? do %>
      <div class="flex items-center justify-center h-16 text-base-content/40 text-sm">
        No unsold lots
      </div>
    <% else %>
      <div style="overflow-x: auto">
        <svg
          viewBox={"0 0 #{@chart.svg_width} 200"}
          width={@chart.svg_width}
          style="min-width: 600px"
          aria-hidden="true"
        >
          <%= for tick <- @chart.ticks do %>
            <line
              x1={70}
              y1={tick.y}
              x2={@chart.svg_width - 10}
              y2={tick.y}
              stroke="#F3F4F6"
              stroke-width="1"
            />
            <text x="64" y={tick.y + 4} text-anchor="end" font-size="10" fill="#9CA3AF">
              {tick.label}
            </text>
          <% end %>
          <%!-- Solid Y-axis and X-axis --%>
          <line x1="70" y1="10" x2="70" y2="160" stroke="#E5E7EB" stroke-width="1" />
          <line
            x1="70"
            y1="160"
            x2={@chart.svg_width - 10}
            y2="160"
            stroke="#E5E7EB"
            stroke-width="1"
          />
          <%!-- Dashed current price reference line --%>
          <%= if @chart.current_price_y do %>
            <line
              x1={70}
              y1={@chart.current_price_y}
              x2={@chart.svg_width - 10}
              y2={@chart.current_price_y}
              stroke="#6366F1"
              stroke-width="1.5"
              stroke-dasharray="6,3"
            />
            <text
              x={@chart.svg_width - 12}
              y={@chart.current_price_y - 4}
              font-size="9"
              fill="#6366F1"
              text-anchor="end"
            >
              Current
            </text>
          <% end %>
          <%!-- Scatter dots only — no connecting polyline --%>
          <%= for pt <- @chart.points do %>
            <g class="group cursor-pointer">
              <circle
                cx={pt.x}
                cy={pt.y}
                r={@chart.dot_r}
                fill={if pt.profitable, do: "#10B981", else: "#F43F5E"}
                stroke="white"
                stroke-width="2"
              />
              <g class="invisible group-hover:visible pointer-events-none">
                <rect
                  x={pt.tt_x}
                  y={pt.tt_y}
                  width="165"
                  height="64"
                  rx="4"
                  fill="#1F2937"
                  opacity="0.92"
                />
                <%= for {line, j} <- Enum.with_index(pt.hover) do %>
                  <text x={pt.tt_x + 8} y={pt.tt_y + 14 + j * 14} font-size="9" fill="white">
                    {line}
                  </text>
                <% end %>
              </g>
            </g>
            <text x={pt.x} y={174} text-anchor="middle" font-size="9" fill="#9CA3AF">{pt.label}</text>
          <% end %>
        </svg>
      </div>
    <% end %>
    """
  end

  # ----------------------------------------------------------------
  # Chart data builders
  # ----------------------------------------------------------------

  # Shared layout helper for density-aware sizing.
  # Returns %{svg_width, slot, label_indices, bar_bw, dot_r}
  defp chart_layout(n, kind) do
    plot_width = @iw
    natural_width = n * 36
    svg_width = if natural_width > plot_width, do: @ml + natural_width + @mr, else: @w
    iw = svg_width - @ml - @mr
    slot = iw / max(n, 1)

    label_indices =
      cond do
        n <= 12 -> Enum.to_list(0..(n - 1))
        n <= 24 -> Enum.take_every(0..(n - 1), 2) |> Enum.to_list()
        true -> Enum.take_every(0..(n - 1), 4) |> Enum.to_list()
      end

    dot_r =
      cond do
        n <= 12 -> 6
        n <= 24 -> 5
        true -> 4
      end

    bar_bw =
      cond do
        n <= 12 -> slot * 0.5
        n <= 24 -> slot * 0.4
        true -> slot * 0.35
      end

    %{
      svg_width: svg_width,
      iw: iw,
      slot: slot,
      label_indices: label_indices,
      dot_r: if(kind == :scatter, do: dot_r, else: 6),
      bar_bw: if(kind == :bar, do: bar_bw, else: slot * 0.5)
    }
  end

  defp build_pnl_bars(lots, currency) do
    filtered = Enum.reject(lots, &is_nil(&1.pnl_pct))
    n = length(filtered)

    if n == 0 do
      %{empty?: true}
    else
      layout = chart_layout(n, :bar)
      pcts = Enum.map(filtered, &to_f(&1.pnl_pct))

      max_pos = pcts |> Enum.filter(&(&1 >= 0)) |> Enum.max(fn -> 0.0 end)
      max_neg = pcts |> Enum.filter(&(&1 < 0)) |> Enum.map(&abs/1) |> Enum.max(fn -> 0.0 end)

      # Y domain: always includes 0; mixed → symmetric ±max
      {y_min_pct, y_max_pct} =
        cond do
          max_pos > 0 and max_neg > 0 ->
            m = max(max_pos, max_neg) * 1.12
            {-m, m}

          max_pos > 0 ->
            span = max(max_pos * 1.12, 8.0)
            {0.0, span}

          true ->
            span = max(max_neg * 1.12, 8.0)
            {-span, 0.0}
        end

      range = y_max_pct - y_min_pct
      range = if range <= 0.0, do: 1.0, else: range

      pct_to_y = fn v -> @mt + @ih - (v - y_min_pct) / range * @ih end
      zero_y = pct_to_y.(0.0)

      bars =
        Enum.with_index(filtered, fn lot, i ->
          pct = to_f(lot.pnl_pct)
          positive = pct >= 0.0
          bh = max(abs(pct) / range * @ih, 2.0)
          x = @ml + i * layout.slot + (layout.slot - layout.bar_bw) / 2
          y = if positive, do: pct_to_y.(pct), else: zero_y
          cx = x + layout.bar_bw / 2

          label =
            if lot.purchase_date, do: Calendar.strftime(lot.purchase_date, "%b '%y"), else: "?"

          pct_label =
            if lot.pnl_pct do
              sign = if pct >= 0, do: "+", else: ""
              "#{sign}#{Float.round(pct, 1)}%"
            end

          pct_y = if positive, do: y - 4, else: y + bh + 11

          hover = build_pnl_hover(lot, currency)

          # Position tooltip above bar; flip below if bar top is within 70px of chart top.
          # Then clamp fully inside the 200-tall viewBox so a 64px box never clips.
          anchor_y = if positive, do: y, else: zero_y
          bar_bottom = if positive, do: y + bh, else: zero_y + bh
          tt_y_above = anchor_y - 68
          tt_y_pref = if tt_y_above >= @mt, do: tt_y_above, else: bar_bottom + 4
          tt_y = tt_y_pref |> max(@mt * 1.0) |> min((@h - 64 - 2) * 1.0)
          tt_x = min(max(cx - 82.5, @ml * 1.0), (layout.svg_width - @mr - 165) * 1.0)

          %{
            x: x,
            y: y,
            bw: layout.bar_bw,
            bh: bh,
            cx: cx,
            positive: positive,
            label: label,
            pct_label: pct_label,
            pct_y: pct_y,
            hover: hover,
            tt_x: tt_x,
            tt_y: tt_y
          }
        end)

      ticks = build_pct_ticks(y_min_pct, y_max_pct, range)
      %{empty?: false, bars: bars, zero_y: zero_y, ticks: ticks, svg_width: layout.svg_width}
    end
  end

  defp build_pnl_hover(lot, currency) do
    date = if lot.purchase_date, do: Calendar.strftime(lot.purchase_date, "%b %-d, %Y"), else: "?"
    sold = fmt_qty_hover(lot.sold_qty)

    held =
      if lot.held_qty && Decimal.gt?(lot.held_qty, Decimal.new(0)),
        do: " (#{fmt_qty_hover(lot.held_qty)} held)",
        else: ""

    nbp = if lot.net_buy_price, do: fmt_price_hover(lot.net_buy_price), else: "—"
    sp = if lot.sale_price, do: fmt_price_hover(lot.sale_price), else: "—"
    pnl_str = if lot.realized_pnl, do: fmt_signed_hover(lot.realized_pnl, currency), else: "—"
    pct_str = if lot.pnl_pct, do: "#{Float.round(to_f(lot.pnl_pct), 1)}%", else: "—"

    [
      date,
      "Sold: #{sold}#{held}",
      "Net buy: #{nbp} · Sale: #{sp}",
      "P&L: #{pnl_str} (#{pct_str})"
    ]
  end

  defp build_cost_basis(lots, current_price, currency) do
    if lots == [] do
      %{empty?: true}
    else
      n = length(lots)
      layout = chart_layout(n, :scatter)
      cp = to_f(current_price)

      net_buy_prices = Enum.map(lots, &to_f(&1.net_buy_price || &1.buy_price))
      all_prices = if cp > 0.0, do: [cp | net_buy_prices], else: net_buy_prices
      max_val = Enum.max(all_prices, fn -> 1.0 end)
      min_val = Enum.min(all_prices, fn -> 0.0 end) * 0.9
      range = max_val - min_val
      range = if range <= 0.0, do: 1.0, else: range

      val_to_y = fn v -> @mt + @ih - (to_f(v) - min_val) / range * @ih end
      current_price_y = if cp > 0.0, do: val_to_y.(cp)

      points =
        Enum.with_index(lots, fn lot, i ->
          nbp = lot.net_buy_price || lot.buy_price
          x = @ml + i * layout.slot + layout.slot / 2
          y = val_to_y.(nbp)
          nbp_f = to_f(nbp)
          profitable = cp > 0.0 and nbp_f <= cp

          label =
            if lot.purchase_date, do: Calendar.strftime(lot.purchase_date, "%b '%y"), else: "?"

          hover = build_cost_basis_hover(lot, cp, currency)

          tt_y_above = y - 68
          tt_y_pref = if tt_y_above >= @mt, do: tt_y_above, else: y + layout.dot_r + 4
          tt_y = tt_y_pref |> max(@mt * 1.0) |> min((@h - 64 - 2) * 1.0)
          tt_x = min(max(x - 82.5, @ml * 1.0), (layout.svg_width - @mr - 165) * 1.0)

          %{
            x: x,
            y: y,
            profitable: profitable,
            label: label,
            hover: hover,
            tt_x: tt_x,
            tt_y: tt_y
          }
        end)

      ticks =
        Enum.map(0..@tick_count, fn i ->
          v = min_val + i * (range / @tick_count)
          %{y: val_to_y.(v), label: format_axis(max(v, 0.0), "USD")}
        end)

      %{
        empty?: false,
        points: points,
        current_price_y: current_price_y,
        ticks: ticks,
        dot_r: layout.dot_r,
        svg_width: layout.svg_width
      }
    end
  end

  defp build_cost_basis_hover(lot, cp, currency) do
    date = if lot.purchase_date, do: Calendar.strftime(lot.purchase_date, "%b %-d, %Y"), else: "?"
    held = fmt_qty_hover(lot.held_qty)
    nbp = if lot.net_buy_price, do: fmt_price_hover(lot.net_buy_price), else: "—"
    cur = if cp > 0.0, do: "$#{Float.round(cp, 2)}", else: "—"

    unreal_str =
      if lot.unrealized_pnl do
        signed = fmt_signed_hover(lot.unrealized_pnl, currency)
        nbp_f = to_f(lot.net_buy_price || lot.buy_price)
        pct = if nbp_f > 0.0, do: " (#{Float.round((cp - nbp_f) / nbp_f * 100, 1)}%)", else: ""
        "#{signed}#{pct}"
      else
        "—"
      end

    [date, "Held: #{held}", "Net buy: #{nbp} · Current: #{cur}", "Unrealized: #{unreal_str}"]
  end

  defp build_area_line(categories, series_data, currency) do
    n = length(categories)

    if n == 0 or series_data == [] do
      %{empty?: true}
    else
      layout = chart_layout(n, :line)
      iw = layout.iw
      slot = iw / max(n - 1, 1)

      all_values =
        Enum.flat_map(series_data, fn s ->
          Enum.map(s.values, &to_f/1)
        end)

      max_val = Enum.max(all_values, fn -> 1.0 end)
      max_val = if max_val <= 0.0, do: 1.0, else: max_val

      val_to_y = fn v -> @mt + @ih - to_f(v) / max_val * @ih end

      series =
        Enum.map(series_data, fn s ->
          color = s[:color] || "#6366F1"

          points =
            Enum.with_index(categories, fn cat, i ->
              v = Enum.at(s.values, i)
              x = @ml + i * slot
              y = val_to_y.(v)
              value_label = format_axis(to_f(v), currency)
              tt_x = min(max(x - 48.0, 4.0), (layout.svg_width - @mr - 96) * 1.0)
              tt_y_pref = if y - 34 >= @mt, do: y - 34, else: y + 16
              # Clamp inside the 200-tall viewBox so the 20px box never clips top/bottom.
              tt_y = tt_y_pref |> max(@mt * 1.0) |> min((@h - 20 - 2) * 1.0)

              %{
                x: x,
                y: y,
                label: to_string(cat),
                value_label: value_label,
                tt_x: tt_x,
                tt_y: tt_y
              }
            end)

          area_path =
            if length(points) > 1 do
              first_x = hd(points).x
              last_x = List.last(points).x
              bottom_y = @mt + @ih

              pts_str =
                Enum.map_join(points, " ", fn p ->
                  "#{Float.round(p.x, 1)},#{Float.round(p.y, 1)}"
                end)

              "M #{first_x} #{bottom_y} L #{pts_str} L #{last_x} #{bottom_y} Z"
            else
              ""
            end

          %{points: points, color: color, area_path: area_path, name: s[:name] || ""}
        end)

      y_ticks =
        Enum.map(0..@tick_count, fn i ->
          v = max_val * i / @tick_count
          %{y: val_to_y.(v), label: format_axis(v, currency)}
        end)

      x_labels =
        Enum.with_index(categories, fn cat, i ->
          %{x: @ml + i * slot, label: to_string(cat), show: i in layout.label_indices}
        end)
        |> Enum.filter(& &1.show)

      # Rotate the x-axis labels when the widest one (~6px/char at font-size 10)
      # would collide with its neighbor at the current point spacing. Long FY
      # labels ("FY 2015-16") across many years overlap horizontally otherwise;
      # short labels ("2024") stay flat.
      max_label_px =
        categories
        |> Enum.map(&(String.length(to_string(&1)) * 6))
        |> Enum.max(fn -> 0 end)

      rotate_x = max_label_px > slot

      %{
        empty?: false,
        series: series,
        y_ticks: y_ticks,
        x_labels: x_labels,
        rotate_x: rotate_x,
        svg_width: layout.svg_width
      }
    end
  end

  defp build_pct_ticks(y_min_pct, _y_max_pct, range) do
    step = range / @tick_count
    pct_to_y = fn v -> @mt + @ih - (v - y_min_pct) / range * @ih end

    Enum.map(0..@tick_count, fn i ->
      v = y_min_pct + i * step
      label = "#{Float.round(v, 0) |> trunc()}%"
      %{y: pct_to_y.(v), label: label}
    end)
  end

  defp build_bars(labels, values, currency) do
    n = length(labels)
    floats = Enum.map(values, &to_f/1)
    max_val = Enum.max(floats, fn -> 0.0 end)
    max_val = if max_val <= 0.0, do: 1.0, else: max_val

    if n == 0 do
      %{empty?: true}
    else
      slot = @iw / n
      bw = slot * 0.65

      bars =
        Enum.with_index(labels, fn label, i ->
          val = Enum.at(floats, i, 0.0)
          bh = val / max_val * @ih
          x = @ml + i * slot + (slot - bw) / 2
          y = @mt + @ih - bh
          %{label: label, x: x, y: y, bw: bw, bh: bh, cx: x + bw / 2}
        end)

      %{empty?: false, bars: bars, ticks: build_ticks(max_val, currency)}
    end
  end

  defp build_ticks(max_val, currency) do
    Enum.map(0..@tick_count, fn i ->
      val = max_val * i / @tick_count
      y = @mt + @ih - val / max_val * @ih
      %{val: val, y: y, label: format_axis(val, currency)}
    end)
  end

  defp points_str(pts) do
    Enum.map_join(pts, " ", fn p -> "#{Float.round(p.x, 1)},#{Float.round(p.y, 1)}" end)
  end

  defp format_axis(val, "INR") when val >= 10_000_000, do: "₹#{Float.round(val / 10_000_000, 2)}Cr"
  defp format_axis(val, "INR") when val >= 100_000, do: "₹#{Float.round(val / 100_000, 1)}L"
  defp format_axis(val, "INR") when val >= 1_000, do: "₹#{round(val / 1_000)}K"
  defp format_axis(val, "INR"), do: "₹#{round(val)}"
  defp format_axis(val, _) when val >= 1_000_000, do: "$#{Float.round(val / 1_000_000, 2)}M"
  defp format_axis(val, _) when val >= 1_000, do: "$#{round(val / 1_000)}K"
  defp format_axis(val, _), do: "$#{round(val)}"

  defp fmt_qty_hover(nil), do: "—"
  defp fmt_qty_hover(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()
  defp fmt_qty_hover(n) when is_number(n), do: "#{Float.round(n * 1.0, 2)}"

  defp fmt_price_hover(nil), do: "—"
  defp fmt_price_hover(%Decimal{} = d), do: "$#{Decimal.round(d, 2) |> Decimal.to_string()}"
  defp fmt_price_hover(s) when is_binary(s), do: "$#{s}"

  defp fmt_signed_hover(nil, _), do: "—"

  defp fmt_signed_hover(%Decimal{} = d, _currency) do
    cond do
      Decimal.gt?(d, Decimal.new(0)) ->
        "+$#{Decimal.round(d, 0) |> Decimal.to_string()}"

      Decimal.lt?(d, Decimal.new(0)) ->
        "-$#{Decimal.abs(d) |> Decimal.round(0) |> Decimal.to_string()}"

      true ->
        "$0"
    end
  end

  defp to_f(nil), do: 0.0
  defp to_f(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_f(n) when is_float(n), do: n
  defp to_f(n) when is_integer(n), do: n * 1.0

  defp to_f(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
