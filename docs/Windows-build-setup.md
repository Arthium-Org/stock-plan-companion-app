# Building the Windows installer

One-time setup for the developer building `StockPlan-Setup.exe`. The end
user (CA) needs **none** of this — they just download and run the installer.

---

## 1. Install prerequisites on the build machine

### Erlang OTP for Windows

- Download the 64-bit OTP installer:
  <https://www.erlang.org/downloads>
- Choose OTP 27 (matches `.tool-versions` for macOS reproducibility).
- Run the installer with default options.
- Verify in PowerShell: `erl -version` should print the OTP version.

### Elixir for Windows

- Easiest: install via the official Windows installer:
  <https://elixir-lang.org/install.html#windows>
- Pick Elixir 1.18.x compiled for OTP 27.
- Verify: `elixir -v` should show `Elixir 1.18.x (compiled with Erlang/OTP 27)`.

### Inno Setup 6

- Download from <https://jrsoftware.org/isdl.php>.
- Install with defaults. The compiler ends up at
  `C:\Program Files (x86)\Inno Setup 6\ISCC.exe` — the build script
  hard-codes this path.

### Visual Studio Build Tools (C compiler)

- Needed to compile `launcher_win.c` into `StockPlan.exe`.
- Download from <https://visualstudio.microsoft.com/downloads/> →
  "Tools for Visual Studio" → **Build Tools for Visual Studio**.
- During install, select the workload **Desktop development with C++**.
- This gives you `cl.exe` and the Windows SDK.

---

## 2. Build the installer

1. Clone the repo on your Windows desktop:
   ```powershell
   git clone https://github.com/Arthium-Org/stock-plan-companion-app.git
   cd stock-plan-companion-app
   ```
2. Open the **x64 Native Tools Command Prompt for VS** from the Start Menu
   (this puts `cl.exe` and the Windows SDK on PATH).
3. Inside that command prompt, switch to PowerShell:
   ```cmd
   powershell
   ```
4. Run the build script:
   ```powershell
   .\scripts\build_release_windows.ps1
   ```

The script:
- Fetches prod dependencies, builds assets, runs `mix release --overwrite`
- Compiles `launcher_win.c` → `StockPlan.exe`
- Converts `docs\Logo.png` to `docs\Logo.ico`
- Downloads VC++ Redistributable (cached after the first run)
- Invokes Inno Setup to build `release\StockPlan-Setup.exe`
- Prints the file's SHA256 hash

Total time: ~5 minutes on a typical desktop after the one-time tool install.

---

## 3. Test the installer

Either on the same machine or a fresh Windows test VM:

1. Double-click `release\StockPlan-Setup.exe`.
2. SmartScreen: **More info → Run anyway** (unsigned installer).
3. Step through the wizard.
4. After install, the browser should open at `http://localhost:4002`.
5. To uninstall, use **Settings → Apps → Installed apps**.

---

## 4. Release runbook (build → sign → tag → publish)

This is the full, reproducible process for cutting a public release on
`Arthium-Org/stock-plan-companion-app`. It covers **both** desktop artifacts
(Windows + Mac) even though this file lives in the Windows build doc — the
Mac-side build steps live in `docs/distribution/README-Mac.md`; this section
is the single place that documents the end-to-end release flow (D-04).
Release creation for launch is a **manual** step, not a CI build matrix (D-03).

### 4.1 Build both artifacts

- **Windows:** run `.\scripts\build_release_windows.ps1` per §2 above →
  produces `release\StockPlan-Setup.exe`.
- **Mac:** build the Mac artifact per `docs/distribution/README-Mac.md` →
  produces `stock_plan_mac.tar.gz`.

### 4.2 Mac code-sign + notarize (Model A — friend signs, no credentials shared)

The Mac `.app` is code-signed and notarized under **Model A**: the friend
signs on his own Mac using his own Apple Developer ID Application
certificate. His certificate, private key, and Apple credentials **never
leave his machine** and are never shared with the maintainer (D-01b).

On the friend's Mac, after building the `.app`:

```bash
codesign --options runtime --sign "Developer ID Application: <Name> (<TeamID>)" \
  /path/to/StockPlan.app

xcrun notarytool submit /path/to/StockPlan.app.zip --wait \
  --apple-id "<apple-id>" --team-id "<TeamID>" --password "<app-specific-password>"

xcrun stapler staple /path/to/StockPlan.app
```

Then re-package the stapled `.app` into `stock_plan_mac.tar.gz` for upload.

**Unsigned fallback (not launch-blocking):** if the friend is unavailable for
a given release, ship the **unsigned** Mac artifact instead and document the
Gatekeeper bypass for end users: **right-click the app → Open → Open** (instead
of double-click), which lets the user explicitly approve the unsigned binary.
This fallback is an accepted, documented trade-off (D-01b) — it does not block
a release.

### 4.3 Bump the version (single source of truth)

Before tagging, bump `version:` in `mix.exs` to the new release version
(e.g. `"1.5.0"`). The tag **must** match this value exactly — this is the
single source of truth the in-app update checker (`StockPlan.Updates`)
compares against (D-02).

```elixir
# mix.exs
version: "1.5.0",
```

Commit the version bump before tagging.

### 4.4 Tag the release

Tag format is `vX.Y.Z`, matching the `mix.exs` version with a leading `v`:

```bash
git tag v1.5.0
git push origin v1.5.0
```

### 4.5 Publish with `gh release create`

```bash
gh release create v1.5.0 \
  release/StockPlan-Setup.exe \
  release/stock_plan_mac.tar.gz \
  --repo Arthium-Org/stock-plan-companion-app \
  --title "v1.5.0" \
  --notes "<release notes — see template below>"
```

(Requires `gh auth login` first, with admin/write access to
`Arthium-Org/stock-plan-companion-app`.)

### 4.6 Release notes template + severity-marker convention

The in-app update checker (`StockPlan.Updates.evaluate_release/3`) reads the
release **body** and looks for two specific lines to decide whether to show
the passive dismissable "update available" banner (D-07) or the stronger
non-dismissable "Important update — please upgrade" banner (D-07b). The
marker strings below must be reproduced **exactly** — the parser matches them
with a case-insensitive, multiline regex, so the literal text (key, colon,
value) shown here is the contract:

```
Severity: critical
min_supported_version: 1.4.0

## What's new
- ...
```

- `Severity: critical` — a line starting with `Severity:` followed by
  `critical`. Only present on releases that must not be skipped (e.g. a
  security fix, a data-corruption fix). Omit this line entirely for normal
  releases — the app then shows only the passive dismissable banner.
- `min_supported_version: X.Y.Z` — a line starting with
  `min_supported_version:` followed by a bare semver (no `v` prefix). The app
  shows the non-dismissable banner only when **both** lines are present
  **and** the running version is strictly below `min_supported_version`.

Standard (non-critical) release notes just omit both marker lines and use
whatever "What's new" / changelog format is useful.

### 4.7 Verify the release

```bash
gh release view v1.5.0 --repo Arthium-Org/stock-plan-companion-app
curl -s https://api.github.com/repos/Arthium-Org/stock-plan-companion-app/releases/latest
```

Confirm both artifacts are listed and `releases/latest` returns the new tag
(a 404 here means no releases exist yet on the repo).

---

## 5. When you get a Windows code signing certificate

The unsigned-installer SmartScreen warning is the only friction for end users
today. Signing eliminates it. To wire signing into the build script later:

1. Install your certificate into the Windows certificate store (or have the
   `.pfx` file accessible).
2. Add a `signtool sign` step in `build_release_windows.ps1` between the
   launcher compile and the Inno Setup invocation, and another after Inno
   Setup outputs the installer. Example:
   ```powershell
   $signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
   & $signtool sign /tr http://timestamp.digicert.com /td SHA256 /fd SHA256 `
       /a $LauncherOut
   & $signtool sign /tr http://timestamp.digicert.com /td SHA256 /fd SHA256 `
       /a (Join-Path $ProjectRoot "release\StockPlan-Setup.exe")
   ```
3. The Inno Setup `[Setup]` section can also be told to sign automatically
   via the `SignTool=` directive. Search the Inno Setup docs for "signing"
   when you're ready.

No other build changes are required. The installer payload doesn't change.

---

## Troubleshooting build issues

**`cl.exe is not recognized`** — You opened a regular PowerShell instead of
the **x64 Native Tools Command Prompt**. Close and reopen from the Start Menu.

**`mix is not recognized`** — Elixir wasn't added to your PATH. Open a new
shell after install, or check **System Properties → Environment Variables**.

**`Inno Setup not found`** — The script expects the default install path
`C:\Program Files (x86)\Inno Setup 6\`. If you installed elsewhere, edit
`$InnoSetupCompiler` near the top of `build_release_windows.ps1`.

**Build hangs on `mix deps.get`** — Probably a hex registry hiccup. Run
`mix local.hex --force` and retry.
