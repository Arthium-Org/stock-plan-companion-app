# Test Plan: M19 — Desktop Executable (Mac + Windows)

---

## TP-1: Build (CI / Developer)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | mix test before build | All pass |
| TP-1.2 | MIX_ENV=prod mix release (each target) | Builds without error |
| TP-1.3 | Output artifacts exist | Mac binary + Windows exe |
| TP-1.4 | Binary size | Reasonable (<150MB each) |
| TP-1.5 | SHA-256 computed | Matches manifest.json |

## TP-2: First Launch — Mac

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Run binary | Server starts |
| TP-2.2 | Browser opens | `/activate` (M30) |
| TP-2.3 | DB created | `~/.stock_plan/stock_plan.db` |
| TP-2.4 | FX seeded | INR toggle works |
| TP-2.5 | After activate + upload | Portfolio populates |

## TP-3: First Launch — Windows

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | Run exe | Server starts |
| TP-3.2 | Browser opens | `/activate` if new; `/portfolio` if licensed |
| TP-3.3 | DB created | `%USERPROFILE%\.stock_plan\stock_plan.db` |
| TP-3.4 | FX seeded | INR toggle works |
| TP-3.5 | v1.4 → current upgrade | DB migrated, data preserved |

## TP-4: Persistence (Both Platforms)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | Stop, restart | Data present |
| TP-4.2 | FX not re-seeded | Seed once only |
| TP-4.3 | license.json preserved | M30 state survives restart |

## TP-5: Clean Machine

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | Mac — no Elixir | App runs |
| TP-5.2 | Windows — no Elixir | Exe runs |
| TP-5.3 | Gatekeeper / SmartScreen | Documented bypass works |
| TP-5.4 | Full workflow | Activate → Upload → Tax → Sell |

## TP-6: Edge Cases

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Port 4002 in use | Clear error |
| TP-6.2 | Two instances | Second detects conflict |
| TP-6.3 | No internet | App starts; activation may require network |

## TP-7: Manifest (M27 Integration)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | manifest.json | All 3 platform keys for latest version |
| TP-7.2 | Download URL | CDN link works |
| TP-7.3 | Checksum verify | sha256 matches artifact |

---

## Test Count: ~25 manual tests (Mac + Windows)
