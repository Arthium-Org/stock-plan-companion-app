# Stock Plan Manager — Mac Installation

## Download

Download **`StockPlanCompanion-arm64.dmg`** from the
[latest GitHub Release](https://github.com/Arthium-Org/stock-plan-companion-app/releases/latest)
on `Arthium-Org/stock-plan-companion-app`.

**Requires an Apple Silicon Mac (M1 or newer)**, macOS 13+.

## Install

1. Open the downloaded `StockPlanCompanion-arm64.dmg`.
2. Drag **StockPlanCompanion** into the **Applications** folder shown in the window.
3. Eject the disk image.

The app is signed and notarized, so it opens with no Gatekeeper warning.

## Run

Double-click **StockPlanCompanion** in Applications. It starts a local server in the
background and automatically opens your browser to the app
(`http://localhost:4002`). Double-click it again any time to reopen the tab —
if the server is already running it simply reopens the browser.

## First Time Setup

- The app creates a database at `~/.stock_plan/stock_plan.db`
- FX rates (333 monthly USD/INR rates) are loaded automatically
- Start by uploading your E*Trade files: Benefit History, G&L Expanded, Holdings

## Stop

The server runs in the background. It's harmless to leave running (local only,
port 4002), but to stop it, run in Terminal:

```bash
/Applications/StockPlanCompanion.app/Contents/Resources/release/bin/stock_plan stop
```

## Troubleshooting

### "Port 4002 already in use"
A previous instance is still running. Double-clicking StockPlanCompanion again detects a
hung server and restarts it automatically. To stop it manually:
```bash
/Applications/StockPlanCompanion.app/Contents/Resources/release/bin/stock_plan stop
```
Or: `lsof -i :4002 -t | xargs kill -9`

### App doesn't open in browser
Open manually: http://localhost:4002

### "This app can't be opened" (unsigned build only)
The signed release opens normally. If you were given an **unsigned** build,
right-click (Control-click) StockPlanCompanion → **Open** → **Open** to approve it once.

### Reset data (start fresh)
```bash
rm ~/.stock_plan/stock_plan.db
```
Next launch will create a fresh database.

## What's Included

- Portfolio view (ESPP + RSU holdings with live stock price)
- Tax Centre (Schedule FA, Capital Gains, Schedule FSI)
- Sell Advisor (tax-optimized lot selection)
- USD/INR toggle (SBI TT Buying Rate)

## System Requirements

- macOS 13+ (Ventura or later)
- Apple Silicon (M1/M2/M3) or Intel
- ~50MB disk space
- Internet connection (for live stock prices)

---

## Building, code-signing & notarizing the Mac artifact (for the release maintainer)

This section is for the developer/friend building and signing the Mac artifact
(`StockPlanCompanion-arm64.dmg`) for a release, not the end user. See
`docs/Windows-build-setup.md` §4 for the full release runbook (build artifacts →
sign/notarize Mac → bump version → tag → `gh release create` → release notes with
the severity-marker convention) — this section covers only the Mac-specific
build + code-sign + notarize + staple, which `scripts/build_release.sh` automates
(D-01b).

### Build, code-sign, notarize, and staple (Model A)

The Mac artifact is signed and notarized under **Model A**: the friend builds
and signs on his own Mac using his own Apple Developer ID Application
certificate. The certificate, private key, and Apple credentials **never leave
his machine** and are never shared with the maintainer — only the resulting
signed, notarized, stapled DMG is handed back (or attached directly to the
Release, since the friend has repo admin access).

**Running the release via Claude Code?** Hand Claude
`docs/distribution/CLAUDE-mac-release.md` — a step-by-step runbook that verifies
prereqs, interactively collects the signing inputs, runs the build below,
verifies Gatekeeper, and publishes (with an explicit confirmation). The rest of
this section is the manual equivalent.

`scripts/build_release.sh` does the whole thing in one command: it Mix-releases
the app, signs **every** nested Mach-O (ERTS binaries, NIFs, bundled libcrypto)
inside-out with the hardened runtime, notarizes + staples the `.app`, builds the
DMG, then signs + notarizes + staples the DMG:

```bash
# One-time: store notary credentials in the keychain
xcrun notarytool store-credentials stockplan-notary \
  --apple-id "<apple-id>" --team-id "<TeamID>" --password "<app-specific-password>"

# Each release (on the friend's Mac):
SIGN_IDENTITY="Developer ID Application: <Name> (<TeamID>)" \
NOTARY_KEYCHAIN_PROFILE="stockplan-notary" \
  ./scripts/build_release.sh
# → release/StockPlanCompanion-arm64.dmg  (signed + notarized + stapled)
```

The `<apple-id>` / `<app-specific-password>` (or an App Store Connect API key:
`.p8` + Key ID + Issuer ID) only authorizes the `notarytool` request — it does
**not** grant signing authority. The Developer ID Application certificate is the
sensitive credential and stays exclusively in the friend's keychain. Without
`SIGN_IDENTITY`, the script ad-hoc signs for local dev only (not shippable).

### Unsigned fallback (not launch-blocking)

If the friend is unavailable for a given release, ship the artifact
**unsigned** instead. macOS Gatekeeper will refuse to open it on a plain
double-click; document this workaround for end users:

1. In Finder, **right-click (or Control-click) the app → Open**.
2. Click **Open** again in the confirmation dialog.

This explicitly approves the unsigned binary for that user. This fallback
is an accepted trade-off per D-01b — it does not block shipping a release.
