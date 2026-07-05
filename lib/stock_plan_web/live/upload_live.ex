defmodule StockPlanWeb.UploadLive do
  use StockPlanWeb, :live_view

  alias StockPlan.Ingestion.{FileDetector, UploadChecks}
  alias StockPlan.Ingestions
  alias StockPlan.Repo
  alias StockPlan.Schema.Ingestion
  import Ecto.Query

  @account_id "default"
  @max_file_size 10_000_000

  @slot_order [:holdings, :benefit_history, :gl_expanded]

  defp slot_label(:holdings), do: "Holdings"
  defp slot_label(:benefit_history), do: "Benefit History"
  defp slot_label(:gl_expanded), do: "G&L Expanded"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Upload")
     |> assign(:processing, false)
     |> assign(:file_statuses, [])
     |> assign(:show_clear_confirm, false)
     |> assign(:ingestions, load_ingestions())
     |> assign_checks()
     |> allow_upload(:holdings,
       accept: ~w(.xlsx),
       max_entries: 5,
       max_file_size: @max_file_size
     )
     |> allow_upload(:benefit_history,
       accept: ~w(.xlsx),
       max_entries: 5,
       max_file_size: @max_file_size
     )
     |> allow_upload(:gl_expanded,
       accept: ~w(.xlsx),
       max_entries: 10,
       max_file_size: @max_file_size
     )}
  end

  @impl true
  def handle_event("show_clear_confirm", _params, socket),
    do: {:noreply, assign(socket, :show_clear_confirm, true)}

  def handle_event("hide_clear_confirm", _params, socket),
    do: {:noreply, assign(socket, :show_clear_confirm, false)}

  def handle_event("clear_all_data", _params, socket) do
    case Ingestions.clear_all_data(@account_id) do
      :ok ->
        {:noreply,
         socket
         |> assign(show_clear_confirm: false, ingestions: [], file_statuses: [])
         |> assign_checks()}

      {:error, _} ->
        {:noreply, assign(socket, :show_clear_confirm, false)}
    end
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_entry", %{"slot" => slot, "ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(slot), ref)}
  end

  def handle_event("upload_all", _params, %{assigns: %{processing: true}} = socket),
    do: {:noreply, socket}

  def handle_event("upload_all", _params, socket) do
    files = collect_files(socket)

    if files == [] do
      {:noreply, socket}
    else
      statuses =
        Enum.map(files, fn f ->
          %{name: f.name, slot: f.slot, state: :queued, detail: nil}
        end)

      pid = self()
      Task.start_link(fn -> process_sequentially(pid, files) end)

      {:noreply, assign(socket, processing: true, file_statuses: statuses)}
    end
  end

  @impl true
  def handle_info({:file_progress, name, new_state, detail}, socket) do
    statuses =
      Enum.map(socket.assigns.file_statuses, fn s ->
        if s.name == name, do: %{s | state: new_state, detail: detail}, else: s
      end)

    {:noreply, assign(socket, file_statuses: statuses)}
  end

  def handle_info(:all_done, socket) do
    {:noreply,
     socket
     |> assign(processing: false, ingestions: load_ingestions())
     |> assign_checks()}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, processing: false)}
  end

  # --- File pipeline ---

  defp collect_files(socket) do
    Enum.flat_map(@slot_order, fn slot ->
      saved = save_uploaded_files(socket, slot)
      Enum.map(saved, fn {name, path} -> %{slot: slot, name: name, path: path} end)
    end)
  end

  defp save_uploaded_files(socket, slot) do
    consume_uploaded_entries(socket, slot, fn %{path: path}, entry ->
      dest = Path.join(System.tmp_dir!(), "#{entry.uuid}_#{entry.client_name}")
      File.cp!(path, dest)
      {:ok, {entry.client_name, dest}}
    end)
  end

  defp process_sequentially(pid, files) do
    Enum.each(files, fn f ->
      send(pid, {:file_progress, f.name, :detecting, nil})

      case FileDetector.detect(f.path) do
        {:ok, detected} when detected == f.slot ->
          run_ingest_step(pid, f)

        {:ok, detected} ->
          File.rm(f.path)

          send(
            pid,
            {:file_progress, f.name, :failed,
             "Wrong slot — this is a #{slot_label(detected)} file"}
          )

        {:error, :unknown} ->
          File.rm(f.path)
          send(pid, {:file_progress, f.name, :failed, "Could not identify file type"})
      end
    end)

    send(pid, :all_done)
  end

  defp run_ingest_step(pid, f) do
    send(pid, {:file_progress, f.name, :parsing, nil})

    result =
      try do
        ingest_fun(f.slot).(@account_id, f.path)
      rescue
        _ -> {:error, :internal_error}
      after
        File.rm(f.path)
      end

    case result do
      {:ok, summary} ->
        send(pid, {:file_progress, f.name, :done, summary_line(f.slot, summary)})

      error ->
        send(pid, {:file_progress, f.name, :failed, error_message(error)})
    end
  end

  defp ingest_fun(:holdings), do: &Ingestions.ingest_holdings/2
  defp ingest_fun(:benefit_history), do: &Ingestions.ingest_benefit_history/2
  defp ingest_fun(:gl_expanded), do: &Ingestions.ingest_gl/2

  defp summary_line(:holdings, %{holdings: h} = summary),
    do: prefix_symbol(summary, "#{h.rsu_rows} RSU + #{h.espp_rows} ESPP rows")

  defp summary_line(:benefit_history, %{silver: s} = summary),
    do:
      prefix_symbol(
        summary,
        "#{s.origins} origins · #{s.tranches} tranches · #{s.sales} sales"
      )

  defp summary_line(:gl_expanded, summary) do
    case summary do
      %{silver: %{sales: n}} -> "#{n} sales matched"
      _ -> "parsed"
    end
  end

  defp summary_line(_, _), do: nil

  defp prefix_symbol(%{dominant_symbol: sym}, line) when is_binary(sym), do: "#{sym} — #{line}"
  defp prefix_symbol(_, line), do: line

  defp assign_checks(socket) do
    %{nudges: nudges, readiness: readiness} = UploadChecks.check(@account_id)
    assign(socket, nudges: nudges, readiness: readiness)
  end

  defp load_ingestions do
    Repo.all(
      from i in Ingestion,
        where: i.account_id == "default",
        order_by: [desc: i.inserted_at]
    )
  end

  # --- Error messages ---

  defp error_message({:error, :file_not_found}), do: "File not found"
  defp error_message({:error, :duplicate_file, _id}), do: "Already uploaded"

  defp error_message({:error, :no_benefit_history}),
    do: "Upload Benefit History first"

  defp error_message({:error, :invalid_format}), do: "Invalid file format"
  defp error_message({:error, :internal_error}), do: "Internal error"
  defp error_message({:error, reason}) when is_atom(reason), do: to_string(reason)
  defp error_message(_), do: "Failed"

  defp upload_error_message(:too_large), do: "File too large (max 10 MB)"
  defp upload_error_message(:not_accepted), do: "Only .xlsx files accepted"
  defp upload_error_message(:too_many_files), do: "Too many files for this slot"
  defp upload_error_message(_), do: "Upload error"

  # --- Render helpers ---

  defp any_files_queued?(uploads) do
    uploads.holdings.entries != [] or
      uploads.benefit_history.entries != [] or
      uploads.gl_expanded.entries != []
  end

  defp state_icon(:queued), do: {"○", "text-base-content/30"}
  defp state_icon(:detecting), do: {"●", "text-info animate-pulse"}
  defp state_icon(:parsing), do: {"●", "text-info animate-pulse"}
  defp state_icon(:done), do: {"✓", "text-success"}
  defp state_icon(:failed), do: {"✗", "text-error"}

  defp state_label(:queued), do: "Waiting"
  defp state_label(:detecting), do: "Checking type..."
  defp state_label(:parsing), do: "Parsing..."
  defp state_label(:done), do: "Done"
  defp state_label(:failed), do: "Failed"

  defp readiness_rows(readiness) do
    [
      {"Portfolio", readiness.portfolio},
      {"Vesting Schedule", readiness.vesting_schedule},
      {"Schedule FA", readiness.schedule_fa},
      {"Capital Gains", readiness.capital_gains},
      {"Schedule FSI", readiness.schedule_fsi},
      {"Sell Advisor", readiness.sell_advisor}
    ]
  end

  defp readiness_class(:ready), do: "badge-success"
  defp readiness_class(:limited), do: "badge-warning"
  defp readiness_class(:blocked), do: "badge-error"
  defp readiness_class(:not_applicable), do: "badge-ghost"

  defp readiness_label(:ready), do: "Ready"
  defp readiness_label(:limited), do: "Limited"
  defp readiness_label(:blocked), do: "Blocked"
  defp readiness_label(:not_applicable), do: "N/A"

  defp nudge_class(:error), do: "alert-error"
  defp nudge_class(:warning), do: "alert-warning"
  defp nudge_class(:info), do: "alert-info"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :has_files, any_files_queued?(assigns.uploads))

    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <h1 class="text-2xl font-bold mb-2">Upload Files</h1>
      <p class="text-base-content/60 mb-4">
        Drop your E*Trade exports below. When you're ready, click <strong>Upload All Files</strong>.
        Each file is validated and parsed in dependency order: Holdings → Benefit History → G&L.
      </p>

      <a href="/guide" class="alert alert-info mb-6 hover:bg-info/20 transition-colors">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5 shrink-0"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
          />
        </svg>
        <div class="flex-1">
          <p class="font-semibold">Need to download files from E*Trade?</p>
          <p class="text-sm">View the step-by-step download guide with screenshots →</p>
        </div>
      </a>

      <form id="upload-form" phx-submit="upload_all" phx-change="validate">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {drop_zone(
            assigns,
            :holdings,
            "Holdings",
            "ByBenefitType_expanded.xlsx",
            "Current portfolio snapshot (optional)"
          )}
          {drop_zone(
            assigns,
            :benefit_history,
            "Benefit History",
            "BenefitHistory.xlsx",
            "Grants, vests, sales — required"
          )}
          {drop_zone(
            assigns,
            :gl_expanded,
            "G&L Expanded",
            "G&L_Expanded.xlsx",
            "Lot-level sells — one per tax year"
          )}
        </div>

        <div class="flex justify-center mb-8">
          <button
            type="submit"
            class="btn btn-primary btn-lg"
            disabled={@processing or not @has_files}
          >
            <%= if @processing do %>
              <span class="loading loading-spinner loading-sm"></span> Processing…
            <% else %>
              Upload All Files
            <% end %>
          </button>
        </div>
      </form>

      <%= if @file_statuses != [] do %>
        <div class="card bg-base-100 shadow mb-6">
          <div class="card-body">
            <h2 class="card-title">Processing Status</h2>
            <ul class="space-y-2 mt-2">
              <%= for s <- @file_statuses do %>
                <% {icon, klass} = state_icon(s.state) %>
                <li class="flex items-start gap-3 text-sm">
                  <span class={"text-xl leading-none w-5 " <> klass}>{icon}</span>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-baseline justify-between gap-2">
                      <span class="font-mono truncate">{s.name}</span>
                      <span class="text-xs text-base-content/50 shrink-0">
                        {slot_label(s.slot)}
                      </span>
                    </div>
                    <div class="text-xs text-base-content/60 mt-0.5">
                      {state_label(s.state)}
                      <%= if s.detail do %>
                        — {s.detail}
                      <% end %>
                    </div>
                  </div>
                </li>
              <% end %>
            </ul>
          </div>
        </div>
      <% end %>

      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body">
          <div class="flex justify-between items-center mb-3">
            <h2 class="card-title">Data Readiness</h2>
            <a href="/history" class="link link-primary text-sm">View full timeline →</a>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">
            <%= for {feature, status} <- readiness_rows(@readiness) do %>
              <div class="flex items-center justify-between text-sm">
                <span>{feature}</span>
                <span class={"badge badge-sm " <> readiness_class(status)}>
                  {readiness_label(status)}
                </span>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%= if @nudges != [] do %>
        <div class="mb-6 space-y-2">
          <%= for n <- @nudges do %>
            <div class={"alert " <> nudge_class(n.severity)}>
              <div>
                <p class="font-semibold">{n.reason}</p>
                <p class="text-sm">{n.impact}</p>
                <p class="text-sm mt-1"><span class="font-medium">Next:</span> {n.action}</p>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <div class="flex items-center justify-between mb-3">
        <h2 class="text-xl font-bold">Upload History</h2>
        <%= if @ingestions != [] do %>
          <button
            type="button"
            class="btn btn-sm btn-error"
            phx-click="show_clear_confirm"
            disabled={@processing}
          >
            Clear all data
          </button>
        <% end %>
      </div>
      <%= if @ingestions == [] do %>
        <p class="text-base-content/50">No files uploaded yet.</p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>File</th>
                <th>Type</th>
                <th>Status</th>
                <th>Uploaded</th>
              </tr>
            </thead>
            <tbody>
              <%= for ing <- @ingestions do %>
                <tr>
                  <td class="font-mono text-sm">{ing.file_name}</td>
                  <td>
                    <span class={[
                      "badge badge-sm",
                      ing.category == "BENEFIT_HISTORY" && "badge-primary",
                      ing.category == "GL_EXPANDED" && "badge-secondary",
                      ing.category == "HOLDINGS" && "badge-accent"
                    ]}>
                      {ing.category}
                    </span>
                  </td>
                  <td>
                    <span class={[
                      "badge badge-sm",
                      ing.status == "ACTIVE" && "badge-success",
                      ing.status == "ARCHIVED" && "badge-ghost"
                    ]}>
                      {ing.status}
                    </span>
                  </td>
                  <td class="text-sm text-base-content/60">
                    {Calendar.strftime(ing.inserted_at, "%Y-%m-%d %H:%M")}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
      <%!-- Clear all data confirmation modal --%>
      <%= if @show_clear_confirm do %>
        <div class="modal modal-open">
          <div class="modal-box max-w-sm">
            <h3 class="font-bold text-lg text-error mb-1">Clear all data?</h3>
            <p class="text-sm text-base-content/70 mb-1">
              This will delete all uploaded files, grants, vests, sales, and G&L allocations for this account.
            </p>
            <p class="text-sm text-base-content/70 mb-4">
              You can restore everything by re-uploading your Holdings, Benefit History, and G&L files.
            </p>
            <div class="modal-action gap-3">
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="hide_clear_confirm"
              >
                Cancel
              </button>
              <button
                type="button"
                class="btn btn-error btn-sm"
                phx-click="clear_all_data"
              >
                Yes, clear everything
              </button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="hide_clear_confirm"></div>
        </div>
      <% end %>
    </div>
    """
  end

  defp drop_zone(assigns, slot, title, file_hint, description) do
    upload = assigns.uploads[slot]

    assigns =
      assign(assigns,
        upload: upload,
        slot: slot,
        title: title,
        file_hint: file_hint,
        description: description
      )

    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body p-4">
        <h3 class="font-semibold">{@title}</h3>
        <p class="text-xs text-base-content/60">{@description}</p>
        <p class="text-xs font-mono text-base-content/40 mb-2">{@file_hint}</p>

        <div
          class="border-2 border-dashed border-base-300 rounded-lg p-4 text-center hover:border-primary transition-colors"
          phx-drop-target={@upload.ref}
        >
          <.live_file_input upload={@upload} class="hidden" />
          <p class="text-sm">
            Drag & drop or
            <label for={@upload.ref} class="link link-primary cursor-pointer">browse</label>
          </p>
        </div>

        <%= for entry <- @upload.entries do %>
          <div class="flex items-center justify-between text-xs mt-2 bg-base-200 rounded px-2 py-1">
            <span class="font-mono truncate flex-1 mr-2">{entry.client_name}</span>
            <button
              type="button"
              class="text-error hover:font-bold"
              phx-click="cancel_entry"
              phx-value-slot={@slot}
              phx-value-ref={entry.ref}
              aria-label="Remove file"
            >
              ✕
            </button>
          </div>
        <% end %>

        <%= for err <- upload_errors(@upload) do %>
          <p class="text-error text-xs mt-1">{upload_error_message(err)}</p>
        <% end %>
      </div>
    </div>
    """
  end
end
