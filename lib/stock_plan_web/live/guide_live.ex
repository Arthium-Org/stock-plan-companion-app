defmodule StockPlanWeb.GuideLive do
  use StockPlanWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Download Guide")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold">Download Guide</h1>
          <p class="text-base-content/60 mt-1">
            How to download fresh data from E*Trade.
          </p>
        </div>
        <a href="/upload" class="btn btn-primary">Back to Upload</a>
      </div>

      <StockPlanWeb.Layouts.download_steps />

      <div class="text-center py-6">
        <a href="/upload" class="btn btn-primary btn-lg">Back to Upload</a>
      </div>
    </div>
    """
  end
end
