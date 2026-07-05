defmodule StockPlanWeb.HomeLiveTest do
  use StockPlanWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Stock Plan Manager"
  end

  test "GET /upload", %{conn: conn} do
    conn = get(conn, ~p"/upload")
    assert html_response(conn, 200) =~ "Upload Files"
  end

  test "GET /portfolio", %{conn: conn} do
    conn = get(conn, ~p"/portfolio")
    assert html_response(conn, 200) =~ "Portfolio"
  end

  test "nav links present", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    assert body =~ "/upload"
    assert body =~ "/portfolio"
  end
end
