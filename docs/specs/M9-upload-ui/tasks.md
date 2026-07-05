# Tasks: M9 — Upload UI

## Prerequisites

- M8: Ingestion Orchestrator (the API this UI calls)
- M1: Phoenix LiveView + Tailwind v4 + daisyUI configured

---

## Task 1: Route + Skeleton LiveView

- [ ] 1.1 Add `live "/upload", UploadLive` to router
- [ ] 1.2 Create `lib/stock_plan_web/live/upload_live.ex` with basic mount/render
- [ ] 1.3 Verify page renders at `http://localhost:4002/upload`

## Task 2: Shared Navigation

- [ ] 2.1 Add nav links to root layout or create nav component
- [ ] 2.2 Links: Home (`/`), Upload (`/upload`), Portfolio (`/portfolio`)
- [ ] 2.3 Update HomeLive to include link to Upload
- [ ] 2.4 Verify nav appears on all pages

## Task 3: File Upload — Benefit History

- [ ] 3.1 Add `allow_upload(:benefit_history, accept: ~w(.xlsx), max_entries: 1)` in mount
- [ ] 3.2 Add drag-and-drop upload area in template with `live_file_input`
- [ ] 3.3 Add "Upload Benefit History" button
- [ ] 3.4 Handle `upload_bh` event — consume file, run pipeline async via `Task.start`
- [ ] 3.5 Handle `{:ingestion_done, result}` in `handle_info` — update result + re-load ingestions
- [ ] 3.6 Show loading spinner while `@processing == true`, disable buttons
- [ ] 3.7 Display result summary on success
- [ ] 3.8 Display error message on failure (including fallback for unknown errors)
- [ ] 3.9 Show upload validation errors (file too large, wrong type)
- [ ] 3.10 Clean up temp file after ingestion (in Task)
- [ ] 3.11 Test: upload real BH file via browser

## Task 4: File Upload — G&L Expanded

- [ ] 4.1 Add `allow_upload(:gl_expanded, accept: ~w(.xlsx), max_entries: 1)` in mount
- [ ] 4.2 Add second upload area for G&L
- [ ] 4.3 Handle `upload_gl` event
- [ ] 4.4 Show appropriate errors (no BH, duplicate, etc.)
- [ ] 4.5 Test: upload G&L after BH via browser

## Task 5: Upload History List

- [ ] 5.1 Load all ingestions for account on mount
- [ ] 5.2 Display table: file_name, category, status, date
- [ ] 5.3 Style ACTIVE vs ARCHIVED (badge colors)
- [ ] 5.4 Re-load list after each upload
- [ ] 5.5 Order by date descending

## Task 6: Verification

- [ ] 6.1 `mix format --check-formatted`
- [ ] 6.2 `mix compile --warnings-as-errors`
- [ ] 6.3 `mix test` — all pass (LiveView ConnCase test for route)
- [ ] 6.4 Manual: start server, upload BH, upload G&L, verify summary + history
- [ ] 6.5 Manual: verify responsive on mobile viewport

---

## Definition of Done

- [ ] Upload page at `/upload` with two upload areas (BH + G&L)
- [ ] Drag-and-drop + file picker working
- [ ] Pipeline runs on upload, summary displayed
- [ ] Error messages for all failure cases
- [ ] Upload history list showing all ingestions
- [ ] Navigation between Home, Upload, Portfolio
- [ ] Works in browser with real XLSX files
