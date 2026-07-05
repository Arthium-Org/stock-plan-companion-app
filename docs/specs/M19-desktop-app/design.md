# Design: M19 — Desktop Executable (Mac + Windows)

## Approach: mix release (primary), Burrito (optional wrap)

**Primary path:** Standard `mix release` with `include_erts: true` — proven, CI-friendly, ships as `.tar.gz` or wrapped `.exe`/`.app`.

**Optional:** [Burrito](https://github.com/burrito-elixir/burrito) for single-file executables. Burrito's Zig cross-compile adds CI complexity — use when mix release + launcher script is insufficient, not as the only path.

## Architecture

```
stock_plan_manager.app (or binary)
  └── Bundled BEAM VM + compiled app
       ├── Phoenix server (port 4002)
       ├── SQLite (ecto_sqlite3)
       ├── FX seed data (embedded)
       └── Static assets (CSS, JS)
```

## Configuration Changes

### mix.exs — Add Burrito

```elixir
defp deps do
  [
    ...
    {:burrito, "~> 1.0"}
  ]
end

def releases do
  [
    stock_plan: [
      steps: [:assemble, &Burrito.wrap/1],
      burrito: [
        targets: [
          macos_aarch64: [os: :darwin, cpu: :aarch64],
          macos_x86_64: [os: :darwin, cpu: :x86_64],
          windows_x86_64: [os: :win32, cpu: :x86_64]
        ]
      ]
    ]
  ]
end
```

### runtime.exs — Dynamic DB Path

```elixir
# In production/release, use ~/.stock_plan/
db_path =
  if config_env() == :prod do
    home = System.get_env("HOME") || "."
    dir = Path.join(home, ".stock_plan")
    File.mkdir_p!(dir)
    Path.join(dir, "stock_plan.db")
  else
    Path.expand("../tmp/stock_plan_dev.db", __DIR__)
  end

config :stock_plan, StockPlan.Repo,
  database: db_path
```

### Application Start — Auto-seed + Open Browser

```elixir
# In application.ex, after Repo starts:
defp on_start do
  # Run migrations
  StockPlan.Release.migrate()
  
  # Seed FX data if empty
  StockPlan.Release.seed_fx_if_needed()
  
  # Open browser — route depends on activation state (M30)
  Task.start(fn ->
    Process.sleep(2000)
    url =
      if StockPlan.License.activated?() do
        "http://localhost:4002/portfolio"
      else
        "http://localhost:4002/activate"
      end
    open_browser(url)
  end)
end

defp open_browser(url) do
  case :os.type() do
    {:unix, :darwin} -> System.cmd("open", [url])
    {:win32, _} -> System.cmd("cmd", ["/c", "start", url])
    _ -> :ok
  end
end
```

### Release Module

```elixir
defmodule StockPlan.Release do
  @app :stock_plan

  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed_fx_if_needed do
    load_app()
    count = StockPlan.Repo.aggregate(StockPlan.Schema.FxMonthlyRate, :count)

    if count == 0 do
      # Compiled module — NOT Code.eval_file (no .exs in release)
      StockPlan.Release.Seeds.seed_fx_monthly_rates!()
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.ensure_all_started(@app)
end
```

`StockPlan.Release.Seeds` — compiled Elixir module containing FX seed data (generated from `priv/repo/fx_seed_data.exs` at build time or maintained as `.ex`).

**Release checklist:** refresh embedded FX seed at least every **3 months** so non-subscribers have reasonably current bundled rates.

## Build Process

```bash
# Mac Apple Silicon
MIX_ENV=prod mix release stock_plan --overwrite
# Output: burrito_out/stock_plan_macos_aarch64

# Mac Intel (CI or cross-compile)
# Output: burrito_out/stock_plan_macos_x86_64

# Windows x86_64 (CI windows-latest runner)
# Output: burrito_out/stock_plan_windows_x86_64.exe
# Note: v1.4 Windows exe already shipped — align naming with manifest
```

Post-build:
1. Compute SHA-256 per artifact
2. Upload to CDN
3. Update `portal/priv/releases/manifest.json`

## Alternative: Mix Release (No Burrito)

If Burrito has issues, fallback to standard mix release:

```bash
MIX_ENV=prod mix release stock_plan --overwrite

# Output: _build/prod/rel/stock_plan/
# Ship as: stock_plan.tar.gz
# User extracts and runs: ./bin/stock_plan start
```

This requires bundling ERTS (Erlang Runtime System) in the release:

```elixir
# mix.exs
def project do
  [
    ...
    releases: [
      stock_plan: [
        include_erts: true,
        applications: [runtime_tools: :permanent]
      ]
    ]
  ]
end
```

## Distribution

1. Publish artifacts to CDN; portal `/download` serves links from manifest
2. **Mac:** Gatekeeper unsigned warning — right-click → Open
3. **Windows:** SmartScreen unsigned warning — "More info" → Run anyway
4. User activates (M30) then uploads locally

## File Layout

```
~/.stock_plan/                          # Mac: ~/.stock_plan/
  ├── stock_plan.db                     # SQLite (persists across runs)
  ├── license.json                      # M30 — tokens, entitlements
  ├── profile.json                      # Display name
  └── device_id                         # Optional separate file or in license.json

stock_plan_manager                      # Mac binary / .app
stock_plan_manager.exe                  # Windows exe
```

Windows paths use `%USERPROFILE%\.stock_plan\`.

## Portal Integration

Release build updates manifest consumed by M27:

```
portal/priv/releases/manifest.json  →  CDN URLs for each platform artifact
```

Compile-time config embeds production portal URL for M30:

```elixir
config :stock_plan, portal_api_base: "https://stockplan.example.com"
```
