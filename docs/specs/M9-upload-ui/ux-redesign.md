# Spec: M9b — Upload UX Redesign

## Current State

The upload page (`/upload`) has 3 independent cards in a grid:

1. **Holdings** — drag-drop zone + "Upload Holdings" button
2. **Benefit History** — drag-drop zone + "Upload Benefit History" button
3. **G&L Expanded** — drag-drop zone + "Upload G&L Expanded" button

Each card is a separate `<form>` with its own submit event. User selects a file, clicks the card's button, waits for processing, sees result, then moves to the next card.

### Current problems

**UX:**
- User selects a file in one card and assumes it's uploaded (no visual confirmation beyond filename appearing). They move to the next card without clicking "Upload."
- 3 separate buttons feels like 3 separate workflows. User has to remember to click each one.
- No indication of overall progress ("2 of 3 files processed").
- G&L only accepts 1 file at a time (`max_entries: 1`), but users need to upload multiple G&L files (one per tax year). They have to repeat the flow for each.

**Validation:**
- BH and Holdings XLSX files have identical sheet names ("ESPP", "Restricted Stock"). The parsers look for the same sheets.
- Uploading BH into the Holdings slot (or vice versa) silently succeeds — the parser finds the expected sheets but interprets columns wrong, producing corrupted Silver data.
- No content-level detection. File extension (.xlsx) is the only validation.
- G&L has a unique sheet name ("G&L_Expanded") so it's safe, but BH↔Holdings swap is undetectable.

**Data corruption risk:**
- BH "Restricted Stock" has 43 columns. Holdings has 63 columns. Both have "Record Type" as column A.
- If BH is uploaded as Holdings: parser reads "Sellable Qty." from column index that maps to a different BH column → wrong quantities stored.
- If Holdings is uploaded as BH: parser reads "Event Type" from a column that doesn't exist in Holdings → null events, broken Silver.
- No rollback mechanism — corrupted data requires DB delete and re-upload.

## Why Redesign

1. **Single action:** User selects all files, clicks one button. No forgotten uploads.
2. **File fingerprinting:** Detect file type from content before processing. Prevent BH↔Holdings swap.
3. **Multi-file G&L:** Accept multiple G&L files at once instead of one-at-a-time.
4. **Clear feedback:** Show detected type per file, warn on mismatches, combined results summary.

## Requirements

### R1: Unified Upload Flow

1. Single page with 3 file selectors (drag-and-drop or browse):
   - Holdings (ByBenefitType_expanded.xlsx)
   - Benefit History (BenefitHistory.xlsx)
   - G&L Expanded (G&L_Expanded.xlsx) — supports multiple files (one per tax year)
2. User selects files across all sections, sees filenames listed.
3. One "Upload All Files" button at the bottom.
4. Processing indicator shows which file is being processed.
5. Summary shows results for all files after completion.

### R2: Auto-Detection (file fingerprinting)

Before processing, detect file type from content — do NOT trust which slot the user dropped it in.

#### Fingerprinting rules

| File Type | Detection | Confidence |
|---|---|---|
| **Benefit History** | Has sheet "Options" OR (has "Restricted Stock" with 43 cols AND col 23 = "Event Type") | High |
| **Holdings** | Has "Restricted Stock" with 60+ cols AND has "Est. Cost Basis (per share):" column | High |
| **G&L Expanded** | Has sheet "G&L_Expanded" with col 1 = "Record Type", col 3 = "Plan Type" | High |
| **Unknown** | None of the above match | Error |

#### Detection algorithm

```
detect_file_type(xlsx_path):
  sheets = extract sheet names + headers

  IF "G&L_Expanded" in sheet names:
    → :gl_expanded

  IF "Options" in sheet names:
    → :benefit_history

  IF "Restricted Stock" in sheet names:
    rs_headers = headers of "Restricted Stock"
    
    IF length(rs_headers) >= 55 AND "Est. Cost Basis (per share):" in rs_headers:
      → :holdings
    
    IF "Event Type" in rs_headers:
      → :benefit_history

  → :unknown
```

### R3: Slot Mismatch Warning

If user drops a file in one slot but fingerprinting detects a different type:
- Show warning: "This looks like a {detected} file, not {slot}. Proceed anyway?"
- Allow override (user knows best) but default to detected type.

### R4: Wrong File Error

If file type cannot be determined:
- Error: "Could not identify file type. Expected E*Trade Benefit History, Holdings (ByBenefitType), or G&L Expanded."
- Do NOT process.

### R5: Upload Order

Files must be processed in dependency order:
1. **Holdings** first (independent, no prerequisites)
2. **Benefit History** second (independent, but triggers Silver build)
3. **G&L Expanded** last (requires BH to exist for sale matching)

If only G&L is selected without existing BH: error "Please upload Benefit History first."

### R6: Multiple G&L Files

- G&L selector accepts multiple files (one per tax year).
- Each processed independently, in chronological order if possible.
- Show per-file result in summary.

### R7: Guided Onboarding (missing file prompts)

After upload, check what's missing and prompt the user with actionable questions.

#### Pre-upload prompts (if slot is empty)

| Missing File | Prompt | If Yes | If No |
|---|---|---|---|
| **Holdings** | "Do you currently hold any vested or unvested shares?" | Guide to download ByBenefitType from E*Trade → upload | Skip — Portfolio and Schedule FA will work with BH data only (limited accuracy) |
| **Benefit History** | "Without Benefit History, we cannot show portfolio, tax analysis, or sell guidance." | Guide to download → upload | Block — BH is required for all features |
| **G&L** | "Have you sold any shares recently or in the last financial year?" | Guide to download G&L Expanded from E*Trade → upload | Skip — Capital Gains and Tax Centre won't show sell details |

#### Post-upload nudges (from timeline validation)

After all files are processed, run `TrancheTimeline.build` and check for data gaps. Show actionable nudges:

```
Post-upload checks:

1. BH released vs sold mismatch (no Holdings):
   IF bh_sold < total_released AND no Holdings uploaded:
   → "Your Benefit History shows {N} shares still held. Upload Holdings 
      (ByBenefitType) for accurate portfolio and Schedule FA."

2. Sales detected but no G&L:
   IF BH has sell events in current or previous FY AND no G&L uploaded:
   → "We found sales in FY {year}. Upload G&L Expanded for that year 
      to enable Capital Gains statement and Schedule FA."

3. G&L coverage gaps:
   IF V2 validation fails for a CY with sells:
   → "Schedule FA for CY {year} requires G&L data. You have sales on 
      {dates} without matching G&L. Download G&L Expanded for {year}."

4. Holdings vs BH mismatch:
   IF V1 validation finds qty_mismatch warnings:
   → "Holdings and Benefit History don't match for {grant}. This may 
      indicate stale data. Re-download both from E*Trade."
```

#### Nudge placement

- Show as info cards below the upload results section.
- Each nudge has a "How to download" expandable with E*Trade step-by-step.
- Nudges update dynamically as user uploads more files (LiveView re-evaluates).

#### Feature availability matrix

| Feature | BH only | BH + Holdings | BH + G&L | All 3 |
|---|---|---|---|---|
| Portfolio (basic) | Yes | Yes (accurate) | Yes | Yes (accurate) |
| Vesting Schedule | Yes | Yes | Yes | Yes |
| Schedule FA | Limited* | Yes | Limited* | Yes |
| Capital Gains | No | No | Yes | Yes |
| Schedule FSI | No | No | Yes | Yes |
| Sell Advisor | No | Yes | No | Yes |

*Limited: FA works but sold detection relies on BH totals. With Holdings, sold detection is per-tranche accurate.

### R8: Data Readiness Panel

Persistent panel (on upload page and optionally in nav/sidebar) showing feature readiness.

Users don't think in terms of files — they think "what can I do?" This panel answers that.

```
Data Readiness
──────────────────────────────
Portfolio       ✅ Ready
Vesting Schedule ✅ Ready
Schedule FA     ⚠ Missing Holdings — limited accuracy
Capital Gains   ❌ Blocked — upload G&L for FY 2025
Schedule FSI    ❌ Blocked — upload G&L for FY 2025
Sell Advisor    ⚠ Missing Holdings — estimates only
Timeline        ⚠ 3 grants unreconciled — upload Holdings
```

Rules:
- Green: all required data present and validated
- Yellow: works with reduced accuracy (explain what's missing)
- Red: blocked (explain what's needed, link to upload)

Updates live after each file upload (LiveView assigns recalculated).

Computed from `TrancheTimeline.summary()` + validation results. Logic lives in `upload_checks.ex`, not in the LiveView.

### R9: Per-File Status Chain

Each uploaded file shows processing status, not just "success."

"Upload successful" ≠ "usable data." User must see the full chain.

```
BenefitHistory.xlsx
  ✓ Uploaded
  ✓ Parsed (23 origins, 146 tranches, 93 sales)
  ✓ Validated
  ✓ Usable

G&L_Expanded_2024.xlsx
  ✓ Uploaded
  ✓ Parsed (35 allocations)
  ⚠ Validated — 2 sell dates not matched to BH sales
  ⚠ Usable with warnings

ByBenefitType.xlsx
  ✓ Uploaded
  ✓ Parsed (42 RSU + 8 ESPP)
  ✓ Validated
  ✓ Usable
```

States:
- **Uploaded** — file received and saved
- **Parsed** — Bronze rows created, counts shown
- **Validated** — cross-checked against other sources (V1/V2/V3)
- **Usable** — data can power features (green = no issues, yellow = warnings, red = blocked)

Validation runs after ALL files are processed (not per-file), since cross-file checks need all data present.

### R10: Timeline Summary (post-upload)

After all files are processed, show an inline timeline summary using the shared timeline component (from M21) in **summary mode**.

This bridges "upload succeeded" → "here's what the system sees" → "here's what's missing."

```
┌──────────────────────────────────────────┐
│ Data Summary                        ADBE │
│──────────────────────────────────────────│
│ Released: 146 shares (23 grants)         │
│ Sold:     106 shares (G&L: 82, BH: 24)  │
│ Held:      40 shares (Holdings: 40)      │
│ Status:   ✅ Reconciled                  │
│──────────────────────────────────────────│
│ ⚠ ESPP sell dates inferred from BH      │
│   (accuracy may vary if data incomplete) │
│──────────────────────────────────────────│
│ [View full timeline →]  (/history)       │
└──────────────────────────────────────────┘
```

The component is defined in M21 spec (`lib/stock_plan_web/components/timeline_view.ex`) and reused here.

"View full timeline" links to `/history` where the **detail mode** shows the per-grant drill-down.

### R11: Structured Validation Output

All nudges, warnings, and errors use a standard format — not ad-hoc strings.

```elixir
%{
  severity: :error | :warning | :info,
  code: :gl_missing | :holdings_needed | :qty_mismatch | :espp_best_effort,
  reason: "G&L data missing for RSU sell dates: 2024-03-15, 2024-06-20",
  impact: "Schedule FA and Capital Gains cannot be computed for CY 2024",
  action: "Download G&L Expanded for 2024 from E*Trade and upload"
}
```

Every validation → actionable error. User sees what's wrong, why it matters, and what to do.

Rendered consistently in UI: severity badge + reason + impact + action button/link.

## Design

### Full Page Flow

The upload page has 4 stages. User progresses top to bottom. Completed stages stay visible.

```
┌─────────────────────────────────────────────────────────┐
│  Upload Files                                           │
│                                                         │
│  ── Stage 1: Select Files ──────────────────────────    │
│                                                         │
│  ┌────────────────────────────────────────────────┐     │
│  │  1. Holdings (optional)                         │     │
│  │  ┌──────────────────────────────────────┐       │     │
│  │  │  Drag & drop or browse               │       │     │
│  │  │  ByBenefitType_expanded.xlsx         │       │     │
│  │  └──────────────────────────────────────┘       │     │
│  │  ✓ Sample-Holdings.xlsx (detected: Holdings)    │     │
│  └────────────────────────────────────────────────┘     │
│                                                         │
│  ┌────────────────────────────────────────────────┐     │
│  │  2. Benefit History (required)                  │     │
│  │  ┌──────────────────────────────────────┐       │     │
│  │  │  Drag & drop or browse               │       │     │
│  │  └──────────────────────────────────────┘       │     │
│  │  ✓ BenefitHistory.xlsx (detected: BH)           │     │
│  └────────────────────────────────────────────────┘     │
│                                                         │
│  ┌────────────────────────────────────────────────┐     │
│  │  3. Gains & Losses (one per tax year)           │     │
│  │  ┌──────────────────────────────────────┐       │     │
│  │  │  Drag & drop or browse               │       │     │
│  │  └──────────────────────────────────────┘       │     │
│  │  ✓ G&L_2024.xlsx (detected: G&L)               │     │
│  │  ✓ G&L_2025.xlsx (detected: G&L)               │     │
│  └────────────────────────────────────────────────┘     │
│                                                         │
│  [ Upload All Files ]                                   │
│                                                         │
│  ── Stage 2: Processing ────────────────────────────    │
│                                                         │
│  ✓ Holdings — Uploaded → Parsed (42 RSU + 8 ESPP)      │
│  ● Benefit History — Processing...                      │
│  ○ G&L 2024 — Waiting                                   │
│  ○ G&L 2025 — Waiting                                   │
│                                                         │
│  ── Stage 3: Validation ────────────────────────────    │
│                                                         │
│  BenefitHistory.xlsx                                    │
│    ✓ Parsed (23 origins, 146 tranches, 93 sales)        │
│    ✓ Validated                                          │
│    ✓ Usable                                             │
│  G&L_Expanded_2024.xlsx                                 │
│    ✓ Parsed (35 allocations)                            │
│    ⚠ 2 sell dates not matched to BH — usable with warn │
│                                                         │
│  ── Stage 4: Data Summary ──────────────────────────    │
│                                                         │
│  ┌──────────────────────────────────────────────┐       │
│  │ ADBE — 146 released, 106 sold, 40 held       │       │
│  │ Status: ✅ Reconciled                         │       │
│  │ ⚠ ESPP sell dates inferred from BH           │       │
│  │ [View full timeline →]                        │       │
│  └──────────────────────────────────────────────┘       │
│                                                         │
│  Data Readiness                                         │
│  ─────────────────────────────────────────              │
│  Portfolio        ✅ Ready                              │
│  Vesting Schedule ✅ Ready                              │
│  Schedule FA      ⚠ Limited — upload Holdings           │
│  Capital Gains    ✅ Ready                              │
│  Sell Advisor     ⚠ Needs Holdings                      │
│                                                         │
│  ── Nudges ─────────────────────────────────────────    │
│                                                         │
│  ℹ Upload Holdings (ByBenefitType) for accurate         │
│    portfolio and Schedule FA.                           │
│    [How to download from E*Trade ▸]                     │
│                                                         │
│  ── Upload History ─────────────────────────────────    │
│  (existing table of past uploads)                       │
└─────────────────────────────────────────────────────────┘
```

### File Fingerprinting Module

```
lib/stock_plan/ingestion/file_detector.ex

  detect(xlsx_path) :: {:ok, :benefit_history | :holdings | :gl_expanded} | {:error, :unknown}
```

Lightweight — only reads sheet names + first row of headers. Does NOT parse the full file.

### Processing Pipeline

```
handle_event("upload_all", _, socket):
  1. For each selected file: detect type
  2. Warn on slot mismatches
  3. Sort by dependency: holdings → bh → gl
  4. Process sequentially
  5. Show combined results
  6. Run post-upload checks → show nudges
```

### Post-Upload Check Module

```
lib/stock_plan/ingestion/upload_checks.ex

  check(account_id) :: [%{type: atom, severity: :info | :warning, message: String, guide: String}]
```

Runs after all uploads complete. Uses timeline summary + validation to produce nudges.

```elixir
def check(account_id) do
  {timelines, validation} = TrancheTimeline.build(account_id)
  bh_sales = load_bh_sales(account_id)
  summary = TrancheTimeline.summary(timelines, bh_sales)
  has_holdings = Enum.any?(timelines, & &1.holdings_qty != nil)
  has_gl = Enum.any?(timelines, fn t -> Enum.any?(t.sells, & &1.source == :gl) end)
  
  nudges = []
  
  # Check 1: Holdings needed
  if not has_holdings and any_unsold?(summary) do
    nudges = [%{type: :holdings_needed, severity: :info, ...} | nudges]
  end
  
  # Check 2: G&L needed for recent sales
  if has_recent_sales?(bh_sales) and not has_gl do
    nudges = [%{type: :gl_needed, severity: :warning, ...} | nudges]
  end
  
  # Check 3: G&L coverage gaps (from V2)
  # Check 4: Holdings vs BH mismatch (from V1)
  
  nudges
end
```

## Dependencies

- **M21 — Tranche Timeline Builder:** provides `TrancheTimeline.build/1`, `TrancheTimeline.summary/2`, and the shared `timeline_view.ex` component (summary + detail modes). See `docs/specs/M21-tranche-timeline/design.md`.
- **M21 Milestone 8:** Timeline View UI must be built first (or in parallel). Upload page embeds summary mode; History page hosts detail mode.

## Files to Modify

- `lib/stock_plan/ingestion/file_detector.ex` — NEW: file type detection from XLSX content
- `lib/stock_plan/ingestion/upload_checks.ex` — NEW: post-upload checks (nudges + data readiness)
- `lib/stock_plan_web/live/upload_live.ex` — Rewrite: unified flow, 4 stages, embedded timeline summary
- `lib/stock_plan_web/live/history_live.ex` — NEW: History page hosting timeline detail mode (from M21)
- `lib/stock_plan_web/components/timeline_view.ex` — NEW: shared component (from M21)
- `lib/stock_plan_web/router.ex` — Add `/history` route
- `lib/stock_plan_web/components/layouts/` — Add History to nav
- `test/stock_plan/ingestion/file_detector_test.exs` — NEW: detection tests
- `test/stock_plan/ingestion/upload_checks_test.exs` — NEW: nudge + readiness tests

## Out of Scope

- Drag files between slots (too complex for now)
- Auto-detect and auto-assign to correct slot (Phase 2 — single drop zone)
- PDF upload (Trade Confirmations) — separate feature
- Timeline detail mode drill-down into individual sell transactions (future)
