defmodule StockPlanWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use StockPlanWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Inline FX rate display with hover tooltip + (?) info modal.
  Renders nothing if `info` is nil. The parent LiveView owns `@fx_info_open`
  and the show/hide events.
  """
  attr :info, :map, default: nil, doc: "%{rate, year_month, source} from FX.current_rate_info/0"
  attr :open, :boolean, default: false
  attr :format, :atom, default: :inline, doc: "inline (default) or compact"

  def fx_rate_display(assigns) do
    ~H"""
    <%= if @info do %>
      <span class="inline-flex items-center gap-1">
        <span class="tooltip" data-tip={"SBI TT Buy — #{format_year_month(@info.year_month)}"}>
          <span class={fx_text_class(@format)}>
            1 USD = ₹{fx_value(@info.rate)}
          </span>
        </span>
        <button
          type="button"
          phx-click="show_fx_info"
          class="btn btn-ghost btn-xs btn-circle"
          aria-label="About this FX rate"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-4 opacity-60"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="2"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </button>
      </span>

      <.fx_info_modal open={@open} info={@info} />
    <% end %>
    """
  end

  defp fx_text_class(:inline), do: "text-xs text-base-content/50"
  defp fx_text_class(:compact), do: "text-base-content/60"

  defp fx_value(%Decimal{} = d) do
    d |> Decimal.round(2) |> Decimal.to_string()
  end

  defp fx_value(other), do: to_string(other)

  defp format_year_month(ym) do
    [year, month] = String.split(ym, "-")

    Date.new!(String.to_integer(year), String.to_integer(month), 1)
    |> Calendar.strftime("%b %Y")
  end

  @doc """
  Modal explaining why the app uses a "stale-looking" rate per India's
  Rule 115. Triggered by the (?) icon next to the FX rate display.
  """
  attr :open, :boolean, default: false
  attr :info, :map, default: nil

  def fx_info_modal(assigns) do
    ~H"""
    <dialog id="fx_info_modal" class={"modal " <> if(@open, do: "modal-open", else: "")}>
      <div class="modal-box max-w-2xl">
        <h3 class="font-bold text-lg mb-3">About the USD → INR rate</h3>

        <div class="space-y-4 text-sm">
          <p>
            India's <strong>Income Tax Rule 115</strong>
            sets exactly which exchange rate is used to convert your foreign-currency RSU / ESPP transactions to INR for tax filing:
          </p>

          <ul class="list-disc list-inside space-y-1 ml-2">
            <li>
              <strong>Rate:</strong> SBI's TT (Telegraphic Transfer) <strong>Buying</strong> Rate
            </li>
            <li><strong>Date:</strong> The last day of the month <em>before</em> your transaction</li>
            <li>
              <strong>Why:</strong>
              A fixed published bank rate keeps the conversion auditable and prevents picking favourable market moments
            </li>
          </ul>

          <%= if @info do %>
            <div class="alert alert-info text-sm">
              The app is currently using <strong>1 USD = ₹{fx_value(@info.rate)}</strong>
              from {format_year_month(@info.year_month)}. That's the rate Rule 115 mandates for any transaction this month — even if today's market rate is meaningfully higher or lower.
            </div>
          <% end %>

          <div class="bg-base-200 p-3 rounded-lg">
            <p class="font-semibold mb-2">References (open in a new tab):</p>
            <ul class="space-y-1">
              <li>
                <a
                  href="https://retail.onlinesbi.sbi/retail/forex/rates.htm"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="link link-primary"
                >
                  SBI Forex Rates ↗
                </a>
              </li>
              <li>
                <a
                  href="https://incometaxindia.gov.in/Pages/rules/income-tax-rules-1962.aspx"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="link link-primary"
                >
                  Income Tax Act, Rule 115 (Income Tax India) ↗
                </a>
              </li>
              <li>
                <a
                  href="https://www.rbi.org.in/Scripts/ReferenceRateArchive.aspx"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="link link-primary"
                >
                  RBI Reference Rate Archive ↗
                </a>
              </li>
            </ul>
          </div>
        </div>

        <div class="modal-action">
          <button type="button" phx-click="hide_fx_info" class="btn">Close</button>
        </div>
      </div>
      <button
        type="button"
        phx-click="hide_fx_info"
        class="modal-backdrop"
        aria-label="Close FX info"
      >
        close
      </button>
    </dialog>
    """
  end

  @doc """
  Sticky banner above page content that shows the age of the most recent
  upload and a link to /upload. Rendered conditionally in root.html.heex
  when the assigns include `:upload_banner`.
  """
  attr :last_upload_at, :any, default: nil

  def upload_banner(assigns) do
    ~H"""
    <div class="bg-base-200 border-b border-base-300 px-4 py-1.5 text-sm flex items-center justify-between">
      <span class="text-base-content/70">
        <%= if @last_upload_at do %>
          Data last updated {age_phrase(@last_upload_at)}
        <% else %>
          No files uploaded yet
        <% end %>
      </span>
      <a href="/upload" class="link link-primary text-xs">Upload new files →</a>
    </div>
    """
  end

  @doc """
  Global update-availability banner (REL-02, D-07/D-07b). Rendered
  conditionally in root.html.heex from the `:update_banner` assign, which
  is populated by the `:browser` pipeline's `assign_update_banner` plug
  from `StockPlan.Updates.current/0` (filtered by the dismissed-version
  profile setting).

  Renders nothing for `:none`. Renders a passive, dismissable variant for
  `{:update, tag, notes}` — a message + escaped truncated release-notes
  preview + link to the Releases page + a dismiss form (POST
  `/updates/dismiss`) that persists the dismissed version via
  `StockPlan.Profile.put/2` so it doesn't re-nag for the same tag (D-07).
  Renders a stronger, non-dismissable variant for `{:critical, tag,
  notes}` — no dismiss control, reappears every boot until the user
  upgrades (D-07b).

  All release-derived text (`tag`, `notes`) is interpolated via normal
  HEEx `{...}` auto-escaping — never `raw/1`, no markdown/HTML
  interpretation — since it originates from an untrusted remote source
  (the GitHub Releases API `tag_name`/`body` fields, T-04-04).
  """
  attr :state, :any,
    default: :none,
    doc: ":none | {:update, tag, notes} | {:critical, tag, notes}"

  attr :releases_url, :string, default: nil

  def update_banner(assigns) do
    ~H"""
    <%= case @state do %>
      <% :none -> %>
      <% {:update, tag, notes} -> %>
        <div class="bg-base-200 border-b border-base-300 px-4 py-1.5 text-sm flex items-center justify-between">
          <span class="text-base-content/70">
            A newer version ({tag}) is available.
            <a
              href={@releases_url}
              target="_blank"
              rel="noopener noreferrer"
              class="link link-primary text-xs ml-1"
            >
              View release →
            </a>
            <.update_notes_preview notes={notes} />
          </span>
          <form action="/updates/dismiss" method="post" class="ml-2">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="version" value={tag} />
            <button type="submit" class="btn btn-ghost btn-xs">Dismiss</button>
          </form>
        </div>
      <% {:critical, tag, notes} -> %>
        <div class="bg-error text-error-content px-4 py-1.5 text-sm flex items-center justify-between">
          <span class="font-semibold">
            Important update — please upgrade to {tag}.
            <a href={@releases_url} target="_blank" rel="noopener noreferrer" class="link ml-1">
              View release →
            </a>
            <.update_notes_preview notes={notes} />
          </span>
        </div>
    <% end %>
    """
  end

  # Renders an escaped, truncated inline preview of the release notes
  # (D3). Only rendered when the prepared preview is non-empty. `{...}`
  # interpolation only — never `raw/1` — the release body is untrusted
  # remote input (T-04-04).
  attr :notes, :string, required: true

  defp update_notes_preview(assigns) do
    {text, truncated?} = notes_preview(assigns.notes)
    assigns = assign(assigns, text: text, truncated?: truncated?)

    ~H"""
    <%= if @text != "" do %>
      <details class="mt-1 inline-block align-top">
        <summary class="cursor-pointer text-xs text-base-content/60 inline">
          Release notes
        </summary>
        <div class="mt-1 max-h-32 overflow-y-auto whitespace-pre-wrap text-xs text-base-content/70 bg-base-100 border border-base-300 rounded p-2">
          {@text}
          <%= if @truncated? do %>
            …
          <% end %>
        </div>
      </details>
    <% end %>
    """
  end

  # Trims the release body and takes the first ~8 lines / ~500 chars,
  # whichever is shorter, so the inline preview stays compact. Returns
  # {text, truncated?} — truncated? is true if either the line or char
  # cap was hit.
  @notes_preview_max_lines 8
  @notes_preview_max_chars 500

  defp notes_preview(notes) when is_binary(notes) do
    trimmed = String.trim(notes)
    lines = String.split(trimmed, "\n")
    {kept_lines, remaining_lines} = Enum.split(lines, @notes_preview_max_lines)
    lines_truncated? = remaining_lines != []
    by_lines = Enum.join(kept_lines, "\n")

    if String.length(by_lines) > @notes_preview_max_chars do
      {String.slice(by_lines, 0, @notes_preview_max_chars), true}
    else
      {by_lines, lines_truncated?}
    end
  end

  defp notes_preview(_), do: {"", false}

  defp age_phrase(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :day)

    cond do
      diff <= 0 -> "today"
      diff == 1 -> "yesterday"
      diff < 7 -> "#{diff} days ago"
      diff < 14 -> "1 week ago"
      diff < 31 -> "#{div(diff, 7)} weeks ago"
      diff < 60 -> "1 month ago"
      diff < 365 -> "#{div(diff, 30)} months ago"
      diff < 730 -> "1 year ago"
      true -> "#{div(diff, 365)} years ago"
    end
  end

  @doc """
  The three E*Trade download steps (Holdings → BH → G&L) shared between
  HomeLive's first-time guide and the standalone /guide page.
  """
  def download_steps(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Step 1: Holdings --%>
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex items-center gap-3 mb-3">
            <span class="badge badge-lg badge-primary">1</span>
            <h2 class="card-title">Download Holdings (ByBenefitType)</h2>
          </div>
          <p class="text-sm text-base-content/60 mb-3">
            Current portfolio snapshot — what you own right now. Primary data source for the Portfolio page.
          </p>
          <div class="text-sm space-y-1 mb-4">
            <p>1. Log in to <strong>E*Trade Stock Plan</strong> (etrade.com → At Work)</p>
            <p>2. Click <strong>"Holdings"</strong> tab</p>
            <p>3. Click <strong>"Download"</strong> → <strong>"Download Expanded"</strong></p>
            <p>4. Save the <code>.xlsx</code> file</p>
          </div>
          <div class="rounded-lg border border-base-300 overflow-hidden">
            <img src="/images/guide-holdings.png" alt="Holdings download" class="w-full" />
          </div>
        </div>
      </div>

      <%!-- Step 2: Benefit History --%>
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex items-center gap-3 mb-3">
            <span class="badge badge-lg badge-primary">2</span>
            <h2 class="card-title">Download Benefit History</h2>
          </div>
          <p class="text-sm text-base-content/60 mb-3">
            Complete history of grants, vests, and sales. Used for tax documents and historical analysis.
          </p>
          <div class="text-sm space-y-1 mb-4">
            <p>1. Go to <strong>"My Account"</strong> → <strong>"Benefit History"</strong></p>
            <p>2. Click <strong>"Download"</strong> → <strong>"Download Expanded"</strong></p>
            <p>3. Save the <code>.xlsx</code> file</p>
          </div>
          <div class="rounded-lg border border-base-300 overflow-hidden">
            <img src="/images/guide-bh.png" alt="Benefit History download" class="w-full" />
          </div>
        </div>
      </div>

      <%!-- Step 3: G&L --%>
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex items-center gap-3 mb-3">
            <span class="badge badge-lg badge-primary">3</span>
            <h2 class="card-title">Download Gains & Losses</h2>
          </div>
          <p class="text-sm text-base-content/60 mb-3">
            Lot-level sell details for capital gains tax computation. Required for Tax Centre.
          </p>
          <div class="bg-info/10 border border-info/30 rounded-lg p-3 mb-4">
            <p class="text-sm font-semibold text-info">
              Download at least the last 2 years. More years = more accurate tax history.
            </p>
            <p class="text-xs text-base-content/50 mt-1">
              Download one file per tax year (select year from dropdown, then download).
            </p>
          </div>
          <div class="text-sm space-y-1 mb-4">
            <p>1. Go to <strong>"My Account"</strong> → <strong>"Gains & Losses"</strong></p>
            <p>2. Select <strong>Tax Year</strong> from the dropdown (e.g., 2025, 2024)</p>
            <p>3. Click <strong>"Apply"</strong> to load the data</p>
          </div>
          <div class="rounded-lg border border-base-300 overflow-hidden mb-4">
            <img src="/images/guide-gl-year.png" alt="G&L year selection" class="w-full" />
          </div>
          <div class="text-sm space-y-1 mb-4">
            <p>
              4. Once data loads, click <strong>"Download"</strong>
              → <strong>"Download Expanded"</strong>
            </p>
            <p>5. <strong>Repeat steps 2-4</strong> for each tax year</p>
          </div>
          <div class="rounded-lg border border-base-300 overflow-hidden">
            <img src="/images/guide-gl-download.png" alt="G&L download" class="w-full" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Shared "Generate Schedule FA" CTA card, rendered on both HomeLive (:guide
  step, discoverability for new users) and PortfolioLive (:active view, the
  standing landing page for users who actually have data). Navigates to
  `/tax` (TaxCentreLive), where Schedule FA is already the default active
  tab — no CSV download is triggered here, keeping Tax Centre the single
  generation path.
  """
  def schedule_fa_cta(assigns) do
    ~H"""
    <div class="card bg-primary/10 mb-6">
      <div class="card-body">
        <h2 class="card-title">Generate your Schedule FA report</h2>
        <p class="text-sm text-base-content/60">
          The India ITR foreign-assets report, built from your uploaded RSU/ESPP data.
        </p>
        <div class="card-actions">
          <.link navigate={~p"/tax"} class="btn btn-primary">Generate Schedule FA</.link>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
