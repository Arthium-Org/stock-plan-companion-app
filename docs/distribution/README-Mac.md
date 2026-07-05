# Stock Plan Manager — Mac Installation

## Download

Download `stock_plan_mac.tar.gz` from the
[latest GitHub Release](https://github.com/Arthium-Org/stock-plan-companion-app/releases/latest)
on `Arthium-Org/stock-plan-companion-app`.

## Install

1. Open Terminal
2. Extract the archive:
   ```bash
   cd ~/Applications  # or wherever you want to keep it
   tar -xzf ~/Downloads/stock_plan_mac.tar.gz
   ```

## Run

```bash
~/Applications/stock_plan/bin/stock_plan daemon
```

Your browser will automatically open to the upload page.

## First Time Setup

- The app creates a database at `~/.stock_plan/stock_plan.db`
- FX rates (333 monthly USD/INR rates) are loaded automatically
- Start by uploading your E*Trade files: Benefit History, G&L Expanded, Holdings

## Stop

```bash
~/Applications/stock_plan/bin/stock_plan stop
```

## Daily Use

```bash
# Start
~/Applications/stock_plan/bin/stock_plan daemon

# Stop
~/Applications/stock_plan/bin/stock_plan stop
```

**Tip:** Create a shortcut — add an alias to your `~/.zshrc`:
```bash
alias stockplan="~/Applications/stock_plan/bin/stock_plan"
```
Then just: `stockplan daemon` / `stockplan stop`

## Troubleshooting

### "Port 4002 already in use"
Another instance is running. Stop it first:
```bash
~/Applications/stock_plan/bin/stock_plan stop
```
Or kill the process:
```bash
lsof -i :4002 -t | xargs kill -9
```

### App doesn't open in browser
Open manually: http://localhost:4002

### "Operation not permitted" on first run
macOS may block unsigned apps. Right-click the terminal command or run:
```bash
chmod +x ~/Applications/stock_plan/bin/*
```

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

This section is for the developer/friend building and signing
`stock_plan_mac.tar.gz` for a release, not the end user. See
`docs/Windows-build-setup.md` §4 for the full release runbook (build both
artifacts → sign/notarize Mac → bump version → tag → `gh release create` →
release notes with the severity-marker convention) — this section covers only
the Mac-specific code-sign + notarize + staple steps referenced from there
(D-01b).

### Code-sign, notarize, and staple (Model A)

The Mac `.app` is signed and notarized under **Model A**: the friend signs
on his own Mac using his own Apple Developer ID Application certificate. The
certificate, private key, and Apple credentials **never leave his machine**
and are never shared with the maintainer — only the resulting signed,
notarized, stapled artifact is handed back (attached directly to the
Release, since the friend has repo admin access).

```bash
# 1. Sign the built .app with the hardened runtime enabled
codesign --options runtime --sign "Developer ID Application: <Name> (<TeamID>)" \
  StockPlan.app

# 2. Zip it for notarization submission, then submit and wait for approval
ditto -c -k --keepParent StockPlan.app StockPlan.app.zip
xcrun notarytool submit StockPlan.app.zip --wait \
  --apple-id "<apple-id>" --team-id "<TeamID>" --password "<app-specific-password>"

# 3. Staple the notarization ticket to the .app so it works fully offline
xcrun stapler staple StockPlan.app

# 4. Re-package the signed, notarized, stapled .app for distribution
tar -czf stock_plan_mac.tar.gz StockPlan.app
```

The `<apple-id>` / `<app-specific-password>` (or an App Store Connect API
key: `.p8` + Key ID + Issuer ID) is only needed for the `notarytool submit`
step — it authorizes the notarization request, it does **not** grant signing
authority. The Developer ID Application certificate is the sensitive
credential and stays exclusively in the friend's keychain.

### Unsigned fallback (not launch-blocking)

If the friend is unavailable for a given release, ship the artifact
**unsigned** instead. macOS Gatekeeper will refuse to open it on a plain
double-click; document this workaround for end users:

1. In Finder, **right-click (or Control-click) the app → Open**.
2. Click **Open** again in the confirmation dialog.

This explicitly approves the unsigned binary for that user. This fallback
is an accepted trade-off per D-01b — it does not block shipping a release.
