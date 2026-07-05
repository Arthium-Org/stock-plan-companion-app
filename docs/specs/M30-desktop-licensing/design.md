# Design: M30 — Desktop Client Licensing & FX Sync

## Architecture

```
App Start (application.ex)
    │
    ├─► License.load()
    │
    ├─► if no license → browser to /activate
    │
    └─► if license present:
          └─► Task.start: License.validate_and_refresh()  ──► M28 refresh + validate
                  └─► on {:ok, _} → FxSync.run()           ──► M29 /fx/monthly
                  └─► on {:error, _} → log; use cached entitlements + offline grace

Request → Router
    ├─► :require_license plug
    └─► :require_premium plug (export routes, /sell)
```

---

## File Layout

```
lib/stock_plan/
├── license.ex                 # Core license state machine
├── license/store.ex           # Read/write license.json
├── portal_client.ex           # HTTP client for M28 + M29
└── fx_sync.ex                 # Upsert logic for monthly rates

lib/stock_plan_web/
├── plugs/
│   ├── require_license.ex
│   └── require_premium.ex
└── live/
    └── activate_live.ex

config/
├── config.exs                 # dev portal URL
└── runtime.exs                # prod portal URL from env
```

---

## License Store

```elixir
defmodule StockPlan.License.Store do
  @path Path.join([System.user_home!(), ".stock_plan", "license.json"])

  def load(), do: ...
  def save(map), do: ...
  def clear(), do: File.rm(@path)
  def device_id(), do: ...  # generate if missing
end
```

On save:
- Unix: `File.chmod(path, 0o600)`
- Windows: `icacls` restrict to current user (see requirements 1b)

---

## Offline Grace Logic

```elixir
defmodule StockPlan.License do
  @default_grace_hours 48

  def premium? do
    case load() do
      nil -> false
      license ->
        if entitlements_premium?(license) do
          within_grace?(license)
        else
          false
        end
    end
  end

  defp within_grace?(license) do
    validated_at = parse_dt!(license["last_validated_at"])
    grace_hours = license["offline_grace_hours"] || @default_grace_hours
    DateTime.diff(DateTime.utc_now(), validated_at, :hour) <= grace_hours
  end
end
```

**Important:** Online validation resets the 48h window. User must connect at least every 48h to keep premium, OR re-activate with license key on web if tokens expired.

---

## Portal Client

```elixir
defmodule StockPlan.PortalClient do
  def login(email, password)
  def activate(email, license_key, device_id, platform, version)
  def validate(access_token, device_id, platform, version)
  def refresh(refresh_token)
  def fx_sync_status(access_token)
  def fx_monthly(access_token, from_ym, to_ym)

  defp base_url() do
    System.get_env("STOCK_PLAN_PORTAL_URL") ||
      Application.get_env(:stock_plan, :portal_api_base)
  end

  defp post(path, body, opts \\ [])
  defp get(path, token)
end
```

Production: never read `portal_api_base` from `license.json`.

Platform values: `macos_aarch64`, `macos_x86_64`, `windows_x86_64` — detected at runtime.

---

## FX Sync

```elixir
defmodule StockPlan.FxSync do
  alias StockPlan.{PortalClient, License, Repo}
  alias StockPlan.Schema.FxMonthlyRate

  def run do
    with true <- License.fx_sync_allowed?(),
         {:ok, token} <- License.access_token(),
         {:ok, status} <- PortalClient.fx_sync_status(token),
         from <- sync_from_month(status),
         {:ok, %{rates: rates, sync_token: sync_token}} <-
           PortalClient.fx_monthly(token, from, status.latest_year_month) do
      upsert_all(rates)
      License.Store.update_last_fx_sync(sync_token)
      :ok
    else
      _ -> :ok  # non-fatal
    end
  end

  defp sync_from_month(status) do
    case License.Store.load()["last_fx_sync_month"] do
      nil -> status.earliest_year_month
      ym -> next_month(ym)  # avoid re-fetching last synced
    end
  end
end
```

Upsert on `{year_month, currency_pair}` — same as desktop schema.

---

## Application Startup Hook

```elixir
# application.ex — after Repo started
defp bootstrap_license do
  Task.start(fn ->
    case StockPlan.License.load() do
      nil -> :ok
      _ ->
        case StockPlan.License.validate_and_refresh() do
          {:ok, _} -> StockPlan.FxSync.run()
          {:error, reason} -> require Logger; Logger.warning("License validate failed: #{inspect(reason)}")
        end
    end
  end)
end
```

Non-blocking: app UI loads immediately; premium gates checked on action. Errors in the Task are logged, not raised.

---

## Router Plugs

```elixir
defp require_license(conn, _opts) do
  if License.activated?() do
    conn
  else
    conn |> redirect(to: "/activate") |> halt()
  end
end

defp require_premium(conn, _opts) do
  if License.premium?() do
    conn
  else
    conn
    |> redirect(to: "/upgrade")
    |> halt()
  end
end
```

`UpgradeLive` (/upgrade): explains expired/trial ended, CTA to portal `/account/billing`, shows offline grace status.

`activated?` = license.json exists with email + (token or license_key). Allows expired users into free tier.

---

## Activate LiveView

Two forms:
1. Email + password → `PortalClient.login` → save tokens → validate → redirect `/upload` or `/portfolio`
2. Email + license key → `PortalClient.activate` → save → redirect

Show: trial days remaining after success.

---

## Tax Centre Export Gating

In `TaxCentreLive`, export buttons:

```elixir
defp can_export?(socket), do: StockPlan.License.premium?()
```

Disable button + show upgrade link when false.

---

## Update Check

```elixir
defmodule StockPlan.UpdateCheck do
  def check() do
    # GET {portal}/download/manifest.json
    # Compare latest vs Application.spec(:stock_plan, :vsn)
  end
end
```

Called from application bootstrap alongside license validation.

---

## Test Bypass

```elixir
# application.ex — ONLY in test
if Mix.env() == :test and Application.get_env(:stock_plan, :skip_license) do
  :ok
else
  License.validate_and_refresh()
end
```

---

## Windows + Mac Platform Detection

```elixir
def platform_tag do
  case {OS.type(), OS.arch()} do
    {{:unix, :darwin}, :aarch64} -> "macos_aarch64"
    {{:unix, :darwin}, :x86_64} -> "macos_x86_64"
    {{:win32, _}, _} -> "windows_x86_64"
    _ -> "unknown"
  end
end
```

---

## Config

```elixir
# config/runtime.exs (desktop prod release)
config :stock_plan,
  portal_api_base: System.get_env("STOCK_PLAN_PORTAL_URL") || "https://stockplan.example.com",
  portal_jwt_public_key_pem: File.read!(Path.join(:code.priv_dir(:stock_plan), "portal_jwt_public.pem"))
```

Dev: `config :stock_plan, portal_api_base: "http://localhost:4003"`

---

## Testing Strategy

- `PortalClient` mocked via Mox in unit tests
- `License` grace logic tested with fixed DateTime (no network)
- Integration test: bypass in test env only

```elixir
# config/test.exs
config :stock_plan, skip_license: true, skip_portal: true
```

---

## Migration from Current Profile Flow

Current `~/.stock_plan/profile.json` (name only) remains for display name.

Order on first launch:
1. Activation (new)
2. Name prompt (existing HomeLive flow) — or merge name into activation as optional field later

Router: replace `check_profile` with `require_license` + keep profile check for name optional.
