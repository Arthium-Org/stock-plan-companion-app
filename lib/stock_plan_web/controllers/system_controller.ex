defmodule StockPlanWeb.SystemController do
  use StockPlanWeb, :controller

  def quit(conn, _params) do
    spawn(fn ->
      Process.sleep(500)
      System.stop(0)
    end)

    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <title>Stock Plan Manager — Stopped</title>
      <style>
        body { font-family: -apple-system, system-ui, sans-serif; padding: 4rem 2rem; text-align: center; color: #333; background: #fafafa; }
        h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
        p { color: #666; }
      </style>
    </head>
    <body>
      <h1>Stock Plan Manager has stopped</h1>
      <p>You can close this browser tab.</p>
      <p style="margin-top: 2rem; font-size: 0.875rem;">To start it again, open <strong>StockPlan</strong> from Applications.</p>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  @doc """
  Persists the dismissed update version so the passive banner (D-07)
  doesn't re-nag for the same tag, then redirects back to the referring
  page. Never used for the critical variant (no dismiss control there,
  D-07b — it reappears every boot until upgraded).
  """
  def dismiss_update(conn, %{"version" => version}) do
    StockPlan.Profile.put("dismissed_update_version", version)

    redirect(conn, to: referrer_path(conn))
  end

  @doc """
  Re-runs the update check on demand (manual "Check for updates" action,
  D1/D2). Always produces a truthful, visible result before redirecting
  back:
    - `{:up_to_date, v}` -> info flash "You're on the latest version".
    - `:unavailable` -> neutral info flash "Couldn't check for updates
      right now" (never claims up to date on a failed/404 check).
    - `{:update, _}` / `{:critical, _}` -> no flash; the banner state was
      already stored by `check_now/1` and speaks for itself once the
      redirect target's page (via the `:browser` pipeline's
      `assign_update_banner` plug) re-renders (no double-notify).
  """
  def check_updates(conn, _params) do
    conn =
      case StockPlan.Updates.check_now(Application.get_env(:stock_plan, :update_check_repo_slug)) do
        {:up_to_date, version} ->
          put_flash(conn, :info, "You're on the latest version (v#{version}) ✓")

        :unavailable ->
          put_flash(conn, :info, "Couldn't check for updates right now — please try again later.")

        {:update, _tag} ->
          conn

        {:critical, _tag} ->
          conn
      end

    redirect(conn, to: referrer_path(conn))
  end

  # Redirect to the path portion only of the Referer header (never the
  # full attacker-suppliable URL) to avoid an open-redirect; falls back
  # to "/" when absent or unparseable.
  defp referrer_path(conn) do
    conn
    |> get_req_header("referer")
    |> List.first()
    |> case do
      nil ->
        "/"

      referer ->
        case URI.parse(referer) do
          %URI{path: path, query: query} when is_binary(path) and path != "" ->
            if query, do: path <> "?" <> query, else: path

          _ ->
            "/"
        end
    end
  end
end
