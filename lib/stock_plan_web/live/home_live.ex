defmodule StockPlanWeb.HomeLive do
  use StockPlanWeb, :live_view

  alias StockPlan.Ingestions

  @account_id "default"

  @impl true
  def mount(_params, _session, socket) do
    profile = load_profile()

    cond do
      is_nil(profile) ->
        {:ok,
         socket
         |> assign(:page_title, "Stock Plan Manager")
         |> assign(:profile, nil)
         |> assign(:step, :welcome)
         |> assign(:name_input, "")}

      Ingestions.any_active?(@account_id) ->
        {:ok, push_navigate(socket, to: "/portfolio")}

      true ->
        {:ok,
         socket
         |> assign(:page_title, "Stock Plan Manager")
         |> assign(:profile, profile)
         |> assign(:step, :guide)
         |> assign(:name_input, "")}
    end
  end

  @impl true
  def handle_event("save_name", %{"name" => name}, socket) do
    name = String.trim(name)

    if name != "" do
      save_profile(%{"name" => name})
      {:noreply, socket |> assign(profile: %{"name" => name}, step: :guide)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, name_input: name)}
  end

  def handle_event("go_to_upload", _params, socket) do
    {:noreply, push_navigate(socket, to: "/upload")}
  end

  # --- Profile helpers ---

  defp profile_dir, do: StockPlan.Profile.dir()
  defp profile_path, do: StockPlan.Profile.path()

  defp load_profile do
    path = profile_path()

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} -> Jason.decode!(content)
        _ -> nil
      end
    else
      nil
    end
  rescue
    _ -> nil
  end

  defp save_profile(data) do
    File.mkdir_p!(profile_dir())
    File.write!(profile_path(), Jason.encode!(data))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <%= case @step do %>
        <% :welcome -> %>
          {render_welcome(assigns)}
        <% :guide -> %>
          {render_guide(assigns)}
      <% end %>
    </div>
    """
  end

  defp render_welcome(assigns) do
    ~H"""
    <div class="text-center py-16">
      <h1 class="text-4xl font-bold mb-4">Welcome to Stock Plan Manager</h1>
      <p class="text-lg text-base-content/60 mb-8">
        Manage your RSU, ESPP & Stock Option portfolio with tax insights.
      </p>

      <div class="max-w-sm mx-auto">
        <form phx-submit="save_name" phx-change="update_name">
          <label class="label">
            <span class="label-text font-semibold">What's your name?</span>
          </label>
          <input
            type="text"
            name="name"
            value={@name_input}
            placeholder="Enter your name"
            class="input input-bordered w-full mb-4"
            autofocus
          />
          <button
            type="submit"
            class="btn btn-primary w-full"
            disabled={String.trim(@name_input) == ""}
          >
            Get Started
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp render_guide(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-2xl font-bold">
            Welcome, {@profile["name"]}!
          </h1>
          <p class="text-base-content/60 mt-1">
            Follow these steps to download your data from E*Trade, then upload here.
          </p>
        </div>
        <button phx-click="go_to_upload" class="btn btn-primary">
          Go to Upload
        </button>
      </div>

      <StockPlanWeb.Layouts.schedule_fa_cta />

      <StockPlanWeb.Layouts.download_steps />

      <div class="text-center py-6">
        <p class="text-base-content/60 mb-4">
          Once you have all the files, upload them to get started.
        </p>
        <button phx-click="go_to_upload" class="btn btn-primary btn-lg">
          Upload Files
        </button>
      </div>
    </div>
    """
  end
end
