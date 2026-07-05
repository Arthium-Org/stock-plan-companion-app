# Requirements Document: M8 — Ingestion Orchestrator

## Introduction

The Ingestion Orchestrator provides a single-call API for the full ingestion pipeline: upload file → create ingestion → parse → write Bronze → rebuild Silver (with FX + stock prices). It manages ingestion lifecycle (archiving previous uploads, duplicate detection) and is the entry point for both CLI (M13) and web UI (M9). No new data processing — just sequencing M3–M7 and managing ingestion records.

## Glossary

- **Pipeline**: The full sequence: create ingestion → parse → Bronze write → Silver rebuild
- **Archive**: Setting a previous Benefit History ingestion's status to ARCHIVED when a new one is uploaded
- **Duplicate_Detection**: Checking file_hash to prevent re-uploading the same file

## Requirements

### Requirement 1: Benefit History Ingestion

**User Story:** As a user, I want to upload a Benefit History XLSX and have the full pipeline run automatically.

#### Acceptance Criteria

1. `ingest_benefit_history(account_id, file_path)` SHALL run the full pipeline
2. THE function SHALL create an ingestion record with `category: "BENEFIT_HISTORY"`, `status: "ACTIVE"`
3. THE function SHALL compute `file_hash` (SHA256 of file contents) and store it
4. IF a previous ACTIVE Benefit History exists for this account, THE function SHALL archive it (set status to ARCHIVED) before creating the new one
5. THE function SHALL parse the XLSX (M3), write Bronze (M4), and rebuild Silver (M5+M6+M7)
6. THE function SHALL return `{:ok, summary}` with pipeline results or `{:error, reason}`
7. IF the file does not exist, THE function SHALL return `{:error, :file_not_found}`
8. IF parsing fails, THE function SHALL return `{:error, :parse_failed}` without creating an ingestion

### Requirement 2: G&L Ingestion

**User Story:** As a user, I want to upload a G&L Expanded XLSX and have it enrich existing data.

#### Acceptance Criteria

1. `ingest_gl(account_id, file_path)` SHALL run the G&L pipeline
2. THE function SHALL create an ingestion record with `category: "GL_EXPANDED"`, `status: "ACTIVE"`
3. G&L ingestions SHALL NOT archive previous G&L ingestions — multiple coexist
4. THE function SHALL parse (M6 parser), write Bronze (M4), and rebuild Silver
5. IF no ACTIVE Benefit History exists for this account, THE function SHALL return `{:error, :no_benefit_history}` — G&L requires BH first
6. THE function SHALL return `{:ok, summary}` with pipeline results

### Requirement 3: Duplicate File Detection

**User Story:** As a user, I want to be warned if I upload the same file again.

#### Acceptance Criteria

1. THE orchestrator SHALL compute SHA256 of the uploaded file using streaming (avoid loading entire file into memory)
2. IF a file with the same `file_hash` already exists for this account (any ingestion, any status), THE function SHALL return `{:error, :duplicate_file, existing_ingestion_id}`
3. Duplicate detection SHALL apply to both Benefit History and G&L uploads
4. THE error returns the existing ingestion_id — UI can offer "use existing" or future override

### Requirement 4: Rebuild

**User Story:** As a developer, I want to rebuild Silver from existing Bronze without re-uploading files.

#### Acceptance Criteria

1. `rebuild(account_id)` SHALL rebuild Silver from all existing Bronze data across ALL ACTIVE ingestions
2. THE function SHALL delegate to `SilverBuilder.build(account_id)`
3. THE function SHALL return `{:ok, summary}` or `{:error, reason}`
4. Rebuild order: Benefit History (Phase 1) → G&L (Phase 2) → FX (Phase 3) → Stock Prices (Phase 4)

### Requirement 5: Transaction Boundary

#### Acceptance Criteria

1. Parsing SHALL happen OUTSIDE the transaction — parse failure creates no DB state
2. DB operations (archive + create ingestion + write Bronze + rebuild Silver) SHALL be wrapped in a single `Repo.transaction` — atomic commit or full rollback
3. IF any DB step fails, the entire transaction SHALL roll back — no partial state
4. ALL errors SHALL return `{:error, reason}` — never raise

### Requirement 6: Contracts

1. **Idempotency:** Re-running ingestion with same file returns `{:error, :duplicate_file, id}`. Bronze/Silver never duplicated.
2. **Single ingestion at a time:** Phase 1 assumes no concurrent ingestions for the same account.
3. **G&L requires ACTIVE BH:** `validate_active_bh/1` checks for exactly one ACTIVE Benefit History (not just "exists").

### Requirement 7: Interface

1. THE module SHALL be at `lib/stock_plan/ingestions.ex` (replaces the existing context stub)
2. Public functions: `ingest_benefit_history/2`, `ingest_gl/2`, `rebuild/1`
3. THE module SHALL be the ONLY entry point for ingestion — no direct calls to parser/writer/builder from UI or CLI
