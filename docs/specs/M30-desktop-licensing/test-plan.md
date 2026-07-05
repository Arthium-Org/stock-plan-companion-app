# Test Plan: M30 — Desktop Client Licensing & FX Sync

---

## TP-1: License Store (Automated)

**File:** `test/stock_plan/license/store_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-1.1 | Save and load | Round-trip JSON |
| TP-1.2 | Missing file | nil |
| TP-1.3 | device_id generation | UUID format, stable on reload |
| TP-1.4 | clear/0 | File removed |

## TP-2: Offline Grace (Automated)

**File:** `test/stock_plan/license_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-2.1 | Validated 1h ago, premium cached | premium? true |
| TP-2.2 | Validated 47h ago | premium? true |
| TP-2.3 | Validated 49h ago | premium? false |
| TP-2.4 | Expired entitlements | premium? false regardless of grace |
| TP-2.5 | offline_grace_hours from server | Uses 48 from license.json |
| TP-2.6 | offline_grace_remaining | Correct Duration |

## TP-3: Portal Client (Automated — Mox)

**File:** `test/stock_plan/portal_client_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-3.1 | login success | Parses tokens |
| TP-3.2 | activate success | Parses tokens + entitlements |
| TP-3.3 | validate success | Updates fields |
| TP-3.4 | refresh success | New token pair |
| TP-3.5 | Network error | {:error, :network} |
| TP-3.6 | 403 FX call | {:error, :forbidden} |

## TP-4: FX Sync (Automated)

**File:** `test/stock_plan/fx_sync_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-4.1 | Entitled user sync | Rows upserted in FxMonthlyRate |
| TP-4.2 | Not entitled | No HTTP call |
| TP-4.3 | Idempotent upsert | Same year_month updated not duplicated |
| TP-4.4 | last_fx_sync_month updated | license.json field set |
| TP-4.5 | Network failure | :ok, no crash |

## TP-5: Plugs (Automated)

**File:** `test/stock_plan_web/plugs/require_license_test.exs`

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-5.1 | No license | Redirect /activate |
| TP-5.2 | License present | Pass through |
| TP-5.3 | skip_license config | Pass through |

## TP-6: Activate LiveView (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-6.1 | Fresh install | Redirect to /activate |
| TP-6.2 | Login form | Activates, reaches portfolio |
| TP-6.3 | License key form | Activates |
| TP-6.4 | Invalid credentials | Error message |
| TP-6.5 | Register link | Opens portal in browser |

## TP-7: Feature Gating (Manual Browser)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-7.1 | Trial user | FA CSV download works |
| TP-7.2 | Expired user | Export disabled + upgrade prompt |
| TP-7.3 | /sell expired | Blocked or redirect |
| TP-7.4 | Upload expired | Still works |
| TP-7.5 | Portfolio expired | Still works |

## TP-8: Offline Scenarios (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-8.1 | Validate online → disconnect 24h | Premium works |
| TP-8.2 | Disconnect 49h | Premium blocked |
| TP-8.3 | Reconnect after grace | Validate restores premium |
| TP-8.4 | Offline startup | App loads, banner shown if grace low |

## TP-9: Platform (Manual — Mac + Windows)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-9.1 | Mac activate | platform macos_* in validation audit |
| TP-9.2 | Windows exe activate | platform windows_x86_64 |
| TP-9.3 | license.json path Windows | Under %USERPROFILE%\.stock_plan |

## TP-10: E2E with Portal (Manual — staging)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-10.1 | Full flow register → download → activate | End-to-end |
| TP-10.2 | FX sync after portal import new month | Local rate updated |
| TP-10.3 | Trial expiry on server | Desktop reflects on next validate |

## TP-11: Security (Manual)

| Test ID | Scenario | Assertion |
|---|---|---|
| TP-11.1 | license.json | No brokerage data fields |
| TP-11.2 | Network capture during use | No XLSX upload to portal |
| TP-11.3 | Logs | No tokens printed |

---

## Test Config

```elixir
# config/test.exs
config :stock_plan, skip_license: true, skip_portal: true
```

Dedicated integration test tag `@tag :portal_integration` for tests requiring live staging API.
