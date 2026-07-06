defmodule StockPlanWeb.PortfolioLiveTest do
  use StockPlanWeb.ConnCase, async: false

  @moduletag :requires_fixtures

  import Phoenix.LiveViewTest

  alias StockPlan.Ingestions

  @bh_file "test/fixtures/sample-data/su2/Sample2-BenefitHistory.xlsx"
  @holdings_file "test/fixtures/sample-data/su2/Sample2-ByBenefitType_expanded.xlsx"

  @account_id "default"

  setup do
    {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_file)
    {:ok, _} = Ingestions.ingest_holdings(@account_id, @holdings_file)
    :ok
  end

  test "GET /portfolio renders By Type tables with Symbol column", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/portfolio")

    # By Type tab always renders table headers when origins exist
    html = render_click(view, "switch_tab", %{"tab" => "type"})

    assert html =~ "Portfolio"
    # New Symbol column header (added in M22)
    assert html =~ "Symbol"
    # Underlying data must reach the row templates without crashing
    assert html =~ "ADBE"
  end
end
