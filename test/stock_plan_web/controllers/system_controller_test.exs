defmodule StockPlanWeb.SystemControllerTest do
  use StockPlanWeb.ConnCase, async: false

  alias StockPlan.Profile

  setup do
    original_path = Application.get_env(:stock_plan, :profile_path)

    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "stock_plan_system_controller_test_#{System.unique_integer([:positive])}.json"
      )

    File.write!(tmp_path, "{}")
    Application.put_env(:stock_plan, :profile_path, tmp_path)

    on_exit(fn ->
      File.rm(tmp_path)
      Application.put_env(:stock_plan, :profile_path, original_path)
    end)

    %{tmp_path: tmp_path}
  end

  describe "POST /updates/dismiss" do
    test "persists the dismissed version via Profile.put/2 and redirects", %{conn: conn} do
      conn = post(conn, ~p"/updates/dismiss", %{"version" => "v1.6.0"})

      assert conn.status == 302
      assert redirected_to(conn) == "/"
      assert Profile.get("dismissed_update_version", nil) == "v1.6.0"
    end

    test "redirects back to the referring page's path only (no open redirect)", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("referer", "http://evil.example.com/portfolio?foo=bar")
        |> post(~p"/updates/dismiss", %{"version" => "v1.6.0"})

      assert redirected_to(conn) == "/portfolio?foo=bar"
    end

    test "falls back to / when there is no referer", %{conn: conn} do
      conn = post(conn, ~p"/updates/dismiss", %{"version" => "v1.6.0"})

      assert redirected_to(conn) == "/"
    end
  end

  describe "POST /updates/check" do
    test "re-invokes the update check and redirects without crashing", %{conn: conn} do
      conn = post(conn, ~p"/updates/check")

      assert conn.status == 302
      assert redirected_to(conn) == "/"
    end

    test "sets a neutral couldn't-check info flash when the check fails/404s (D1/D2)", %{
      conn: conn
    } do
      # The live repo's releases/latest 404s today (no release published
      # yet), so this exercises the real :unavailable path end-to-end.
      # It must NEVER claim "up to date" here.
      conn = post(conn, ~p"/updates/check")

      flash_info = Phoenix.Flash.get(conn.assigns.flash, :info)
      assert flash_info =~ "Couldn't check for updates"
      refute flash_info =~ "up to date"
      refute flash_info =~ "up-to-date"
    end
  end
end
