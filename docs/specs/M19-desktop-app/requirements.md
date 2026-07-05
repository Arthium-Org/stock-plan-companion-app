# Requirements: M19 — Desktop Executable (Mac + Windows)

## Introduction

Package Stock Plan Manager as standalone **macOS** and **Windows** applications. User downloads from portal (M27), installs locally, and runs — browser opens to localhost. **No cloud hosting of the app.** Financial data stays in local SQLite.

**Existing artifact:** Windows `.exe` built for **v1.4** release. This milestone formalizes Mac + Windows as first-class targets and ties into portal download manifest (M27) and licensing (M30).

Phase 1: Mac (Apple Silicon + Intel) + Windows (x86_64 `.exe`). Code signing / notarization deferred.

---

## Requirement 1: Platform Artifacts

### macOS

1. Output: `.app` bundle or standalone binary per Burrito/mix release
2. Targets: `macos_aarch64` (Apple Silicon), `macos_x86_64` (Intel)
3. Minimum: macOS 13+
4. No Elixir/Erlang/Node required on user machine

### Windows

1. Output: single `.exe` (existing 1.4 pipeline)
2. Target: `windows_x86_64`
3. Minimum: Windows 10+
4. No Elixir/Erlang/Node required on user machine
5. SmartScreen unsigned warning acceptable for early releases (same as Mac Gatekeeper)

## Requirement 2: Bundled Runtime

1. THE artifact SHALL bundle: BEAM VM + compiled Phoenix app + static assets
2. THE artifact SHALL include FX seed data (embedded `priv/` — fallback when offline / no subscription sync)
3. THE artifact SHALL NOT bundle Postgres or cloud portal code
4. THE artifact SHALL embed default `portal_api_base` URL (M30) at compile time

## Requirement 3: First Launch Experience

1. Double-click / run exe → starts Phoenix server on **localhost:4002**
2. Automatically opens default browser to `http://localhost:4002/activate` (M30 — or `/` if license already present)
3. First time: empty DB, FX seed auto-loaded, activation screen shown
4. After activation: normal upload / portfolio flow

## Requirement 4: Data Persistence

1. SQLite DB: `~/.stock_plan/stock_plan.db` (Mac) / `%USERPROFILE%\.stock_plan\stock_plan.db` (Windows)
2. License state: `~/.stock_plan/license.json` (M30)
3. Profile: `~/.stock_plan/profile.json` (existing)
4. Data persists across app restarts and version upgrades (migrations on startup)
5. FX seed runs only if local FX table empty; subscriber sync (M30) adds newer months

## Requirement 5: App Lifecycle

1. **Start:** launch server + open browser
2. **Running:** dock icon (Mac) / taskbar (Windows) — system tray optional, out of scope
3. **Stop:** quit app → stops server, frees port 4002
4. **Port conflict:** detect if 4002 in use → show clear error (native dialog or browser error page)

## Requirement 6: Distribution via Portal (M27)

1. Each release SHALL update `portal/priv/releases/manifest.json` with:
   - Version (semver, matches `mix.exs`)
   - Per-platform download URL, SHA-256, size_bytes
   - `release_notes_url`
2. Binaries hosted on CDN — not served by Phoenix binary
3. Version **1.4** Windows exe SHALL be listed in manifest as baseline until superseded

## Requirement 7: Build & CI

1. Mac builds: developer Mac or CI (GitHub Actions macos runner)
2. Windows builds: CI (windows runner) or cross-compile via Burrito
3. Release checklist: tests pass → build all targets → checksums → update manifest → upload CDN

## Requirement 8: Code Signing (Before Public Launch)

1. macOS: plan Apple Developer code signing + notarization before paid public launch (Gatekeeper quarantine friction)
2. Windows: Authenticode signing planned before public launch; SmartScreen bypass acceptable for beta/friends testing only
3. Phase 1 beta: unsigned with documented bypass steps

## Requirement 9: Upgrade Path

1. User downloads new version from `/download` — manual upgrade (no auto-update Phase 1)
2. New version runs migrations against existing `~/.stock_plan/stock_plan.db`
3. `license.json` preserved across upgrade
4. Desktop shows "Update available" banner when manifest version > installed (M30)

---

## Out of Scope (Phase 1)

- Auto-update download/install (notification only via M30 banner)
- Installer wrappers (.dmg, .msi) — single artifact download only
- Linux desktop
- Cloud deployment of app server

Note: Code signing deferred for beta; **required before paid public launch** (Requirement 8).

## Dependencies

- M30: activation first-launch URL
- M27: download manifest and CDN URLs
