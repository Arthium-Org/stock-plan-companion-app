defmodule StockPlanWeb.UpdateBannerTest do
  use StockPlanWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StockPlanWeb.Layouts

  @releases_url "https://github.com/Arthium-Org/stock-plan-companion-app/releases/latest"

  describe "update_banner/1" do
    test "renders nothing for :none" do
      html = render_component(&Layouts.update_banner/1, state: :none, releases_url: @releases_url)

      assert String.trim(html) == ""
    end

    test "renders a dismissable banner for {:update, tag, notes}" do
      html =
        render_component(&Layouts.update_banner/1,
          state: {:update, "v1.6.0", "notes body"},
          releases_url: @releases_url
        )

      assert html =~ "v1.6.0"
      assert html =~ "is available"
      assert html =~ ~s(action="/updates/dismiss")
      assert html =~ ~s(name="version")
      assert html =~ ~s(value="v1.6.0")
      assert html =~ "View release"
      assert html =~ "Dismiss"
      assert html =~ "notes body"
    end

    test "renders a non-dismissable banner for {:critical, tag, notes}" do
      html =
        render_component(&Layouts.update_banner/1,
          state: {:critical, "v2.0.0", "..."},
          releases_url: @releases_url
        )

      assert html =~ "v2.0.0"
      assert html =~ "Important update"
      assert html =~ "bg-error"
      refute html =~ "/updates/dismiss"
      refute html =~ "Dismiss"
    end

    test "escapes release-derived tag text via HEEx auto-escaping (no raw HTML injection)" do
      malicious_tag = "<script>alert(1)</script>"

      html =
        render_component(&Layouts.update_banner/1,
          state: {:update, malicious_tag, "notes"},
          releases_url: @releases_url
        )

      refute html =~ "<script>alert(1)</script>"
      assert html =~ "&lt;script&gt;"
    end

    test "escapes release-derived tag text for the critical variant too" do
      malicious_tag = "<script>alert(1)</script>"

      html =
        render_component(&Layouts.update_banner/1,
          state: {:critical, malicious_tag, "notes"},
          releases_url: @releases_url
        )

      refute html =~ "<script>alert(1)</script>"
      assert html =~ "&lt;script&gt;"
    end

    test "renders a truncated preview with an ellipsis for a long release body" do
      long_body =
        Enum.map_join(1..20, "\n", fn i -> "Line #{i}: some release note content here" end)

      html =
        render_component(&Layouts.update_banner/1,
          state: {:update, "v1.6.0", long_body},
          releases_url: @releases_url
        )

      assert html =~ "Line 1: some release note content here"
      refute html =~ "Line 20: some release note content here"
      assert html =~ "…"
    end

    test "escapes an HTML/script-laden release body (no raw/1, no markdown interpretation)" do
      malicious_body = "before <script>alert(1)</script> after"

      html =
        render_component(&Layouts.update_banner/1,
          state: {:update, "v1.6.0", malicious_body},
          releases_url: @releases_url
        )

      refute html =~ "<script>alert(1)</script>"
      assert html =~ "&lt;script&gt;"
    end

    test "renders nothing extra when notes are empty" do
      html =
        render_component(&Layouts.update_banner/1,
          state: {:update, "v1.6.0", ""},
          releases_url: @releases_url
        )

      refute html =~ "Release notes"
    end
  end
end
