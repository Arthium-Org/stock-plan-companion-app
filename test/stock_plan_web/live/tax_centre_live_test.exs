defmodule StockPlanWeb.TaxCentreLiveTest do
  use StockPlanWeb.ConnCase, async: false

  @moduletag :requires_fixtures

  import Phoenix.LiveViewTest

  alias StockPlan.Ingestions

  @bh_file "test/fixtures/sample-data/su1/sample-Etrade-BenefitHistory.xlsx"
  @gl_2023 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2023.xlsx"
  @gl_2024 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2024.xlsx"
  @gl_2025 "test/fixtures/sample-data/su1/Sample-G&L_Expanded_2025.xlsx"

  @account_id "default"

  setup do
    {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_file)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2023)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2024)
    {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_2025)
    :ok
  end

  test "GET /tax mounts on default FY without crashing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/tax")

    assert html =~ "Tax Centre"
    # Default FY likely has no sales — empty-state path
    assert html =~ "Capital Gains" or html =~ "No sale transactions"
  end

  test "selecting FY 2024-25 renders Capital Gains rows with Symbol column", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tax")

    # Tax Centre now defaults to the Schedule FA tab (STATE Quick Task #3,
    # 2026-07-04) -- switch to Capital Gains before asserting its content.
    render_click(view, "switch_tab", %{"tab" => "capital_gains"})
    html = render_change(view, "select_cg_fy", %{"fy" => "2024"})

    # Symbol column header (added in M22) — and an actual ticker reaches the row template
    assert html =~ "Symbol"
    assert html =~ "ADBE"
    # No KeyError-style crash: the table renders the gain/loss column
    assert html =~ "Gain/Loss"
  end

  test "Schedule FA tab renders Symbol column", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tax")

    html = render_click(view, "switch_tab", %{"tab" => "schedule_fa"})

    assert html =~ "Schedule FA"
    assert html =~ "Symbol"
  end
end
