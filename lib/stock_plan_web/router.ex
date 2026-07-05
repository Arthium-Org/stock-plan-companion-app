defmodule StockPlanWeb.Router do
  use StockPlanWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StockPlanWeb.Layouts, :root}
    plug :assign_update_banner
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", StockPlanWeb do
    pipe_through [:browser, :check_profile]

    live "/", HomeLive
    live "/upload", UploadLive
    live "/guide", GuideLive
    live "/portfolio", PortfolioLive
    live "/tax", TaxCentreLive
    live "/history", HistoryLive
    live "/sell", SellAdvisorLive
    post "/quit", SystemController, :quit
    post "/updates/dismiss", SystemController, :dismiss_update
    post "/updates/check", SystemController, :check_updates
  end

  # Populates conn.assigns[:update_banner] from StockPlan.Updates.current/0
  # (REL-02, D-07/D-07b), filtered by the user's dismissed-version choice
  # (StockPlan.Profile, D-07: "doesn't re-nag for the same version"). This
  # is the REAL wiring mechanism for the root layout's banner — unlike the
  # pre-existing `assigns[:upload_banner]`, which is referenced in
  # root.html.heex but never populated anywhere (dead wiring left as-is).
  # Runs on every full page load (root layout is only rendered on the
  # initial dead-render / static request, not on LiveView patches), so a
  # dismiss or manual "Check for updates" redirect always re-evaluates
  # the current state.
  defp assign_update_banner(conn, _opts) do
    banner =
      case StockPlan.Updates.current() do
        {:critical, _tag, _notes} = critical ->
          critical

        {:update, tag, _notes} = update ->
          if StockPlan.Profile.get("dismissed_update_version") == tag do
            :none
          else
            update
          end

        :none ->
          :none
      end

    assign(conn, :update_banner, banner)
  end

  defp check_profile(conn, _opts) do
    profile_path = StockPlan.Profile.path()

    if conn.request_path != "/" and not File.exists?(profile_path) do
      conn
      |> Phoenix.Controller.redirect(to: "/")
      |> halt()
    else
      conn
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", StockPlanWeb do
  #   pipe_through :api
  # end
end
