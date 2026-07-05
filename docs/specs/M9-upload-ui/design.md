# Design Document: M9 — Upload UI

## Overview

M9 is a Phoenix LiveView page for uploading XLSX files. It uses LiveView's built-in file upload support (drag-and-drop, progress, validation) and delegates all processing to `StockPlan.Ingestions` (M8). The page shows upload history and pipeline results.

### Architecture

```
Browser
  |
  v
┌─────────────────────────────────────────┐
│  StockPlanWeb.UploadLive                │
│                                         │
│  LiveView state:                        │
│    uploads: (LiveView upload config)    │
│    result: nil | {:ok, summary} | err   │
│    ingestions: [list of past uploads]   │
│    processing: boolean                  │
│                                         │
│  Events:                                │
│    "upload_bh" → Ingestions.ingest_bh   │
│    "upload_gl" → Ingestions.ingest_gl   │
└─────────────────────────────────────────┘
     |
     v
StockPlan.Ingestions (M8)
```

## Components

### 1. UploadLive (`lib/stock_plan_web/live/upload_live.ex`)

```elixir
defmodule StockPlanWeb.UploadLive do
  use StockPlanWeb, :live_view

  @account_id "default"  # Phase 1: single tenant
  @max_file_size 10_000_000  # 10 MB

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:result, nil)
     |> assign(:processing, false)
     |> assign(:ingestions, load_ingestions())
     |> allow_upload(:benefit_history, accept: ~w(.xlsx), max_entries: 1, max_file_size: @max_file_size)
     |> allow_upload(:gl_expanded, accept: ~w(.xlsx), max_entries: 1, max_file_size: @max_file_size)}
  end

  # --- Async ingestion with crash safety ---

  # Guard: ignore uploads while processing
  def handle_event("upload_bh", _params, %{assigns: %{processing: true}} = socket), do: {:noreply, socket}
  def handle_event("upload_gl", _params, %{assigns: %{processing: true}} = socket), do: {:noreply, socket}

  @impl true
  def handle_event("upload_bh", _params, socket) do
    path = save_uploaded_file(socket, :benefit_history)
    pid = self()
    Task.start_link(fn ->
      result = try do
        Ingestions.ingest_benefit_history(@account_id, path)
      rescue
        _ -> {:error, :internal_error}
      after
        File.rm(path)
      end
      send(pid, {:ingestion_done, result})
    end)
    {:noreply, assign(socket, processing: true, result: nil)}
  end

  @impl true
  def handle_event("upload_gl", _params, socket) do
    path = save_uploaded_file(socket, :gl_expanded)
    pid = self()
    Task.start_link(fn ->
      result = try do
        Ingestions.ingest_gl(@account_id, path)
      rescue
        _ -> {:error, :internal_error}
      after
        File.rm(path)
      end
      send(pid, {:ingestion_done, result})
    end)
    {:noreply, assign(socket, processing: true, result: nil)}
  end

  @impl true
  def handle_info({:ingestion_done, result}, socket) do
    {:noreply,
     socket
     |> assign(processing: false, result: result, ingestions: load_ingestions())}
  end

  # Safety: if linked Task crashes without sending result
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, processing: false, result: {:error, :internal_error})}
  end
end
```

**Key patterns:**
- **Async pipeline:** `Task.start` runs ingestion off the LiveView process. `handle_info` receives the result. UI stays responsive with loading spinner.
- **Temp file cleanup:** `File.rm(path)` after ingestion completes (in the Task).
- **Upload reset:** LiveView auto-resets upload input after `consume_uploaded_entries`.
- **Processing state:** `@processing` disables buttons and shows spinner.

### 2. Upload Flow (LiveView File Upload)

Phoenix LiveView handles file upload in 3 steps:
1. **allow_upload** in mount — configures accepted types, max size
2. **live_file_input** in template — renders the file picker
3. **consume_uploaded_entries** in event handler — saves file to tmp dir, returns path

```elixir
defp save_uploaded_file(socket, upload_name) do
  [path] =
    consume_uploaded_entries(socket, upload_name, fn %{path: path}, entry ->
      dest = Path.join(System.tmp_dir!(), "#{entry.uuid}_#{entry.client_name}")
      File.cp!(path, dest)
      {:ok, dest}
    end)
  path
end
```

### 3. Template (`lib/stock_plan_web/live/upload_live.html.heex`)

```
Page Layout:
┌─────────────────────────────────────────┐
│  Stock Plan Manager                     │
│  [Upload] [Portfolio] [Income]          │
├─────────────────────────────────────────┤
│                                         │
│  ┌── Benefit History ──┐  ┌── G&L ──┐  │
│  │  [drag & drop]      │  │ [drag]  │  │
│  │  or click to browse │  │         │  │
│  │  [Upload BH]        │  │ [Upload]│  │
│  └─────────────────────┘  └─────────┘  │
│                                         │
│  ┌── Result ───────────────────────────┐│
│  │  ✓ Uploaded: BenefitHistory.xlsx    ││
│  │  Bronze: 531 rows                  ││
│  │  Silver: 23 origins, 146 tranches  ││
│  │  FX: 23 origins enriched           ││
│  └─────────────────────────────────────┘│
│                                         │
│  ┌── Upload History ──────────────────┐ │
│  │  sample-BH.xlsx  BH  ACTIVE  today│ │
│  │  GL_2025.xlsx    G&L ACTIVE  today│ │
│  │  old-BH.xlsx     BH  ARCHIVED ... │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 4. Router Update

```elixir
scope "/", StockPlanWeb do
  pipe_through :browser

  live "/", HomeLive
  live "/upload", UploadLive
  live "/portfolio", PortfolioLive  # placeholder for M10
end
```

### 5. Shared Navigation

Add a nav component to the root layout or create a component:

```heex
<nav class="flex gap-4 p-4 bg-base-200">
  <.link navigate={~p"/"} class="btn btn-ghost">Home</.link>
  <.link navigate={~p"/upload"} class="btn btn-ghost">Upload</.link>
  <.link navigate={~p"/portfolio"} class="btn btn-ghost">Portfolio</.link>
</nav>
```

## Error Display Mapping

| Error | User Message |
|---|---|
| `{:error, :file_not_found}` | "File not found" |
| `{:error, :duplicate_file, id}` | "This file was already uploaded. Use Rebuild if you want to reprocess." |
| `{:error, :no_benefit_history}` | "Please upload a Benefit History file first" |
| `{:error, :invalid_format}` | "Invalid file format — expected .xlsx" |
| `{:error, :parse_failed}` | "Failed to parse file — please check format" |
| `{:error, _other}` | "Something went wrong. Please try again." (fallback) |

**Upload validation errors** (LiveView built-in):
| Error | User Message |
|---|---|
| `:too_large` | "File is too large (max 10 MB)" |
| `:not_accepted` | "Only .xlsx files are accepted" |
| `:too_many_files` | "Please select only one file" |

Render with:
```heex
<%= for err <- upload_errors(@uploads.benefit_history) do %>
  <p class="text-error text-sm"><%= error_to_string(err) %></p>
<% end %>
```

## Implementation Notes

- LiveView file upload requires `phx-drop-target` for drag-and-drop
- **Async processing:** Pipeline runs in `Task.start`, result sent via `send(pid, {:ingestion_done, result})`. UI shows spinner, buttons disabled during processing.
- **Temp file cleanup:** `File.rm(path)` in the Task after ingestion completes. No file accumulation.
- **Upload reset:** LiveView auto-clears file input after `consume_uploaded_entries`.
- **Buttons disabled during processing:** `disabled={@processing}` on submit buttons.
- **File size limit:** 10 MB max via `max_file_size` option.
- `@account_id "default"` hardcoded for Phase 1 — future: from session/auth
- The page re-loads ingestion list after each upload via `load_ingestions()`
- daisyUI components: `btn`, `alert`, `table`, `badge`, `loading`
