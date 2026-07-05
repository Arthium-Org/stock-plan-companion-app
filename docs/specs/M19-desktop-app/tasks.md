# Tasks: M19 — Desktop Executable (Mac + Windows)

## Prerequisites

- All features working (Portfolio, Tax Centre, Sell Advisor)
- Tests passing
- M30 activation flow (or stub `/activate` for build testing)

---

## Milestone 1: Release Configuration

- [ ] 1.1 Add Burrito dependency (or configure standard mix release with ERTS)
- [ ] 1.2 Configure release targets: `macos_aarch64`, `macos_x86_64`, `windows_x86_64`
- [ ] 1.3 Configure runtime.exs for production DB path (`~/.stock_plan/` / `%USERPROFILE%\.stock_plan\`)
- [ ] 1.4 Configure prod.exs (secret_key_base, server: true, port 4002)
- [ ] 1.5 Embed `portal_api_base` for M30
- [ ] 1.6 Ensure static assets compiled (esbuild + tailwind in prod)

## Milestone 2: Release Module

- [ ] 2.1 Create/update `lib/stock_plan/release.ex`
- [ ] 2.2 `migrate/0` — pending migrations on startup
- [ ] 2.3 `StockPlan.Release.Seeds` compiled module (NOT Code.eval_file)
- [ ] 2.4 Regenerate Seeds from fx_seed_data.exs in release checklist (min every 3 months)

## Milestone 3: Auto-Start Experience

- [ ] 3.1 Auto-run migrations on application start
- [ ] 3.2 Auto-seed FX on first launch
- [ ] 3.3 Auto-open browser: `/activate` if not licensed, `/portfolio` if licensed
- [ ] 3.4 Port conflict detection (4002 in use)
- [ ] 3.5 Windows: `cmd /c start` browser open
- [ ] 3.6 Mac: `open` browser command

## Milestone 4: Mac Build + Test

- [ ] 4.1 Build macos_aarch64 release
- [ ] 4.2 Test on Apple Silicon Mac — activate, upload, persist
- [ ] 4.3 Build macos_x86_64 (CI or Intel Mac)
- [ ] 4.4 Test on clean Mac without Elixir

## Milestone 5: Windows Build + Test

- [ ] 5.1 Build windows_x86_64 `.exe` (align with existing 1.4 pipeline)
- [ ] 5.2 Test on Windows 10/11 — activate, upload, persist
- [ ] 5.3 Verify `%USERPROFILE%\.stock_plan\` paths
- [ ] 5.4 SmartScreen unsigned flow documented

## Milestone 6: Portal Manifest (M27)

- [ ] 6.1 Add v1.4 Windows exe to `portal/priv/releases/manifest.json`
- [ ] 6.2 Document release checklist: build → sha256 → CDN → manifest bump
- [ ] 6.3 Verify `/download/manifest.json` serves correct checksums

## Milestone 7: Distribution Docs

- [ ] 7.1 User install guide (Mac + Windows) in M27 `getting-started.md`
- [ ] 7.2 Internal release runbook

---

## Definition of Done

- Mac + Windows artifacts run without Elixir installed
- Browser opens to activation on first launch
- DB + license persist across restarts
- Manifest lists all platform artifacts with checksums
- Upgrade from 1.4 → current preserves local DB
