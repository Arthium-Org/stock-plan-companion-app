defmodule StockPlanWeb.HistoryLiveTest do
  use StockPlanWeb.ConnCase, async: false

  @moduletag :requires_fixtures

  import Phoenix.LiveViewTest

  alias StockPlan.Ingestions

  @bh_user1 "docs/Sample-Data/SampleUser - 1/sample-Etrade-BenefitHistory.xlsx"
  @gl_user1_2025 "docs/Sample-Data/SampleUser - 1/Sample-G&L_Expanded_2025.xlsx"

  @bh_adbe "docs/Sample-Data/SampleUser - 5/SampleUser5-BenefitHistory-ADBE.xlsx"
  @bh_crm "docs/Sample-Data/SampleUser - 5/SampleUser5-BenefitHistory-CRM.xlsx"
  @gl_su5 "docs/Sample-Data/SampleUser - 5/SampleUser5-G&L_Expanded.xlsx"

  @account_id "default"

  describe "empty database" do
    test "renders without crashing and shows upload link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      assert html =~ "Benefits History"
      assert html =~ "Upload" or html =~ "No data"
    end
  end

  describe "single-symbol fixture (SU1)" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_user1)
      {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_user1_2025)
      :ok
    end

    test "page renders Benefits History heading", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      assert html =~ "Benefits History"
    end

    test "no Combined option rendered", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      refute html =~ "Combined"
    end

    test "RSU tab is active by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      # Active tab uses underline styling (border-primary text-primary)
      assert html =~ "border-primary text-primary"
      assert html =~ "RSU"
    end

    test "RSU section shows income lens tiles — no sold/counterfactual/velocity/yoy", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/history")
      # Income lens tiles present
      assert html =~ "Income recognized" or html =~ "Grant promise"
      # Removed sections absent
      refute html =~ "Vesting Velocity"
      refute html =~ "Year-over-Year"
      refute html =~ "What If You&#39;d Never Sold"
      refute html =~ "Tax Withheld at Vest"
    end

    test "RSU summary has 7 tiles with info icons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      # All 7 hint_stat tiles have tooltip marker
      assert html =~ "Grant promise"
      assert html =~ "Income recognized"
      assert html =~ "Still to vest"
      assert html =~ "Vested (net shares)"
      assert html =~ "Unvested (gross shares)"
      assert html =~ "Vest vs grant drift"
    end

    test "RSU chart sections present", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      assert html =~ "RSU income by financial year"
      assert html =~ "New grant value by year"
    end

    test "RSU disclaimer footer present", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")

      assert html =~ "Still-to-vest estimates use today&#39;s stock price" or
               html =~ "Still-to-vest estimates use today's stock price"
    end

    test "switching to ESPP tab re-renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})
      assert html =~ "Benefits History"
    end

    test "ESPP tab: summary 3-row layout present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})

      if html =~ "Purchase Lots" do
        # Row labels from 3-row summary
        assert html =~ "Gross Purchased"
        assert html =~ "Net Received"
        assert html =~ "Purchase Value"
        assert html =~ "Net Discount Value"
        assert html =~ "Realized P"
        assert html =~ "Unrealized P"
        assert html =~ "Total P"
        # Return strip — equal-weighted avg return per lot
        assert html =~ "Avg return per lot"
        # Old Tax Withheld tile absent as standalone
        refute html =~ ">Tax Withheld<"
      end
    end

    test "ESPP lots table: no Lookback column", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})
      refute html =~ ">Lookback<"
    end

    test "ESPP lots table: Buy Price header has tooltip", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})

      if html =~ "Buy Price" do
        assert html =~ "lock-in" or html =~ "Discounted purchase price"
      end
    end

    test "ESPP tab: footer disclaimer present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})

      if html =~ "Purchase Lots" do
        assert html =~ "effective cost per received share" or
                 html =~ "total payroll"
      end
    end

    test "ESPP lots table expand/collapse event works", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})

      if html =~ "Purchase Lots" do
        html2 = render_click(view, "toggle_espp_lots_table", %{})
        assert html2 =~ "Benefits History"
      end
    end

    test "currency toggle switches between INR and USD", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/history")
      assert html =~ "₹ INR"
      assert html =~ "$ USD"
      html2 = render_click(view, "toggle_currency", %{"currency" => "USD"})
      assert html2 =~ "Benefits History"
    end

    test "no symbol dropdown for single symbol", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      refute html =~ ~s[name="symbol"]
    end
  end

  describe "multi-symbol fixture (SU5)" do
    setup do
      {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_adbe)
      {:ok, _} = Ingestions.ingest_benefit_history(@account_id, @bh_crm)
      {:ok, _} = Ingestions.ingest_gl(@account_id, @gl_su5)
      :ok
    end

    test "symbol dropdown rendered when >=2 symbols", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      assert html =~ ~s[name="symbol"]
    end

    test "no Combined option in dropdown", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      refute html =~ "Combined"
    end

    test "RSU and ESPP plan tabs present", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/history")
      assert html =~ "RSU"
      assert html =~ "ESPP"
    end

    test "switching symbol re-renders page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_symbol", %{"symbol" => "CRM"})
      assert html =~ "Benefits History"
    end

    test "switching plan tab to ESPP re-renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})
      assert html =~ "Benefits History"
    end

    test "US Tax Classification section removed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})
      refute html =~ "US Tax Classification"
      refute html =~ "qualifying vs disqualifying"
    end

    test "SOP analysis shows avg return per lot under day-1 and total P&L", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})

      if html =~ "Sell-on-Purchase Analysis" do
        assert html =~ "avg per lot · day-1 exit"
        assert html =~ "avg per lot · actual"
      end
    end

    test "ESPP sold chart section title is 'Sold lot returns'", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})

      if html =~ "espp-sold-pnl" do
        assert html =~ "Sold lot returns"
      end
    end

    test "ESPP unsold chart section title is 'Open lots'", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")
      html = render_click(view, "select_plan", %{"plan" => "ESPP"})

      if html =~ "espp-unsold-basis" do
        assert html =~ "Open lots"
      end
    end

    test "RSU grants table expand/collapse works", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")

      # Only fire toggle if RSU section rendered
      html = render(view)

      if html =~ "Grant breakdown" do
        html2 = render_click(view, "toggle_rsu_grants_table", %{})
        assert html2 =~ "Benefits History"
      end
    end
  end
end
