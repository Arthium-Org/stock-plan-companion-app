# Requirements Document: M9 — Upload UI

## Introduction

The Upload UI provides a Phoenix LiveView page for uploading Benefit History and G&L Expanded XLSX files. It's the first user-facing page beyond the landing page. The UI calls `StockPlan.Ingestions` (M8) for all operations — no direct pipeline calls. After upload, it shows a summary of what was ingested and links to portfolio/income views.

## Requirements

### Requirement 1: Upload Page Route

1. THE page SHALL be accessible at `GET /upload`
2. THE page SHALL be a LiveView (`StockPlanWeb.UploadLive`)
3. THE router SHALL include the route in the browser pipeline

### Requirement 2: File Upload — Two Types

**User Story:** As a user, I want to upload either a Benefit History or G&L file and have the system process it.

#### Acceptance Criteria

1. THE page SHALL offer two upload areas:
   - **Benefit History** — primary data source (Benefit History XLSX)
   - **G&L Expanded** — enrichment data (G&L XLSX, per tax year)
2. EACH upload area SHALL support drag-and-drop AND file picker
3. THE upload SHALL accept `.xlsx` files only
4. THE upload SHALL show the selected filename before submission
5. THE page SHALL have a "Upload" button to trigger processing
6. THE page SHALL show a loading/processing indicator while pipeline runs

### Requirement 3: Account ID

1. Phase 1: single-tenant — account_id hardcoded or auto-generated on first use
2. THE account_id SHALL be stored in the session or derived from a simple config
3. Future: multi-user auth adds real account management

### Requirement 4: Pipeline Feedback

**User Story:** As a user, I want to see what happened after upload — how many grants, vests, sales were processed.

#### Acceptance Criteria

1. AFTER successful upload, THE page SHALL display a summary:
   - File name and type (BH or G&L)
   - Bronze: rows written
   - Silver: origins, tranches, sales, allocations created
   - FX rates applied, stock prices fetched
   - Warnings (if any)
2. AFTER failed upload, THE page SHALL display the error:
   - `:file_not_found` → "File not found"
   - `:duplicate_file` → "This file was already uploaded" (show existing ingestion)
   - `:no_benefit_history` → "Please upload Benefit History first"
   - `:invalid_format` → "Invalid file format — expected XLSX"
   - `:parse_failed` → "Failed to parse file"
3. THE summary SHALL remain visible until a new upload is started

### Requirement 5: Upload History

**User Story:** As a user, I want to see what files I've already uploaded.

#### Acceptance Criteria

1. THE page SHALL list all ingestions for the account (both ACTIVE and ARCHIVED)
2. EACH ingestion SHALL show: file_name, category, status, uploaded date
3. ACTIVE ingestions SHALL be visually distinct from ARCHIVED
4. THE list SHALL be ordered by upload date (newest first)

### Requirement 6: Navigation

1. THE page SHALL have a nav link to Portfolio (`/portfolio`) — even if not built yet
2. THE landing page (`/`) SHALL link to Upload (`/upload`)
3. THE nav SHALL be consistent across all pages (shared layout)

### Requirement 7: Styling

1. THE page SHALL use Tailwind v4 + daisyUI (already configured from M1)
2. THE page SHALL be responsive (works on mobile browser)
3. THE upload area SHALL have a clear visual affordance (dashed border, icon)
