# Claude runbook — build, sign & publish the Mac release

**Audience: Claude Code, running on the signer's (friend's) Apple-Silicon Mac.**
The human hands this file to Claude and says *"follow the Mac release runbook"*.
Claude drives the whole flow, pausing only to (1) collect signing inputs, and
(2) get an explicit publish confirmation.

This wraps `scripts/build_release.sh` (which already does Mix-release → sign every
nested Mach-O → notarize+staple the `.app` → build the DMG → sign+notarize+staple
the DMG). Model A: **the Developer ID certificate, private key, and Apple
credentials never leave this Mac** — only the finished DMG is published (D-01b).

Repo: `Arthium-Org/stock-plan-companion-app`. Stable DMG filename (never
versioned): `StockPlanCompanion-arm64.dmg`.

---

## Claude: follow these steps in order

### Step 0 — Confirm you're in the right place

```bash
git rev-parse --show-toplevel        # must be the stock-plan-companion-app clone
git remote -v | grep Arthium-Org     # must point at the public repo
git fetch origin && git status -sb   # pull latest main first if behind
```

If the clone is behind `origin/main`, `git pull` before building — the release
must be built from current code.

### Step 1 — Verify build prerequisites (report any miss, then stop)

Run these and confirm each passes. If any fails, tell the human exactly which
one and the fix (see the "Prereqs" table at the bottom), then stop.

```bash
elixir -v                                            # Elixir 1.18.x / OTP 27 (via asdf .tool-versions)
ls ~/openssl-compat/lib/libcrypto.3.dylib            # macOS-11-compatible libcrypto (required)
xcode-select -p                                      # Xcode command-line tools present
security find-identity -v -p codesigning | grep "Developer ID Application"   # signing cert in keychain
gh auth status                                       # gh logged in with write access to Arthium-Org
```

Do **not** proceed past a missing Developer ID identity or a missing
`~/openssl-compat/lib/libcrypto.3.dylib` — the build cannot produce a shippable
DMG without them.

### Step 2 — Ask the human the version decision (interactive)

Ask which kind of release this is, and derive the version from the current
`mix.exs` value (read it: `grep -E 'version:' mix.exs`):

| Choice | Meaning | Version move (from `X.Y.Z`) | Tag |
|---|---|---|---|
| **Reuse existing tag** | Re-sign / replace the artifact on a tag that already exists; code may have minor changes nobody's downloaded yet | unchanged | existing `vX.Y.Z` |
| **Patch** | Bug fix | `Z += 1` (e.g. 1.5.1 → 1.5.2) | new `vX.Y.(Z+1)` |
| **Minor** | New feature | `Y += 1, Z = 0` (e.g. 1.5.2 → 1.6.0) | new `vX.(Y+1).0` |

**⚠ Cross-platform coordination (state this to the human before a bump):** a
version bump makes the **Mac DMG** a new version, but the **Windows `.exe`** for
that version does **not** exist until the maintainer rebuilds it on Windows
(`scripts/build_release_windows.ps1`) and uploads it to the same tag. Reusing an
existing tag has no such issue. If the human wants a bump, confirm they'll
handle the Windows rebuild — otherwise the release will ship with only the Mac
artifact at the new version (which is valid, but flag it).

**If Patch or Minor** — bump the single source of truth and tag:

```bash
# 1. Edit mix.exs:  version: "X.Y.Z"  ->  the new value
# 2. Commit + push
git add mix.exs
git commit -m "chore(release): bump version to X.Y.Z"
git push origin main
# 3. Tag must equal the mix.exs version with a leading v
git tag vX.Y.Z
git push origin vX.Y.Z
```

**If Reuse existing tag** — leave `mix.exs` and tags alone; note the tag string
(`vX.Y.Z`) for the publish step.

### Step 3 — Collect signing inputs (interactive, never store to disk)

Ask the human for:

1. **`SIGN_IDENTITY`** — their full Developer ID Application string, e.g.
   `Developer ID Application: Jane Doe (SL8GR6RD2C)`. (They can list it with
   `security find-identity -v -p codesigning`.)
2. **Notary method** — one of:
   - **Keychain profile (preferred):** a profile name they stored once via
     `xcrun notarytool store-credentials <name> --apple-id … --team-id … --password …`.
     Ask for the profile name (e.g. `stockplan-notary`).
   - **Inline creds:** Apple ID + Team ID + app-specific password.

Pass these as environment variables on the build command only — do not echo the
app-specific password back, and do not write any credential into a file or commit.

### Step 4 — Build the signed DMG

Using the collected inputs (keychain-profile form shown; swap for the inline
form if that's what they gave):

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TeamID>)" \
NOTARY_KEYCHAIN_PROFILE="<profile-name>" \
  ./scripts/build_release.sh
```

Inline-creds alternative:

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TeamID>)" \
APPLE_ID="<apple-id>" APPLE_TEAM_ID="<TeamID>" APPLE_APP_PASSWORD="<app-specific-password>" \
  ./scripts/build_release.sh
```

The script notarizes with `--wait`, so it blocks until Apple returns a verdict
(usually 1–5 min). Output: `release/StockPlanCompanion-arm64.dmg`. If the script
prints a `WARNING: … NOT notarized` line, signing succeeded but notary creds were
missing/rejected — stop and re-collect the notary input; do not publish a
non-notarized DMG.

### Step 5 — Verify Gatekeeper + notarization before publishing

```bash
spctl -a -vvv -t open --context context:primary-signature release/StockPlanCompanion-arm64.dmg
xcrun stapler validate release/StockPlanCompanion-arm64.dmg
shasum -a 256 release/StockPlanCompanion-arm64.dmg
```

The `spctl` assessment must read `accepted` / `source=Notarized Developer ID`,
and `stapler validate` must report `The validate action worked`. If either
fails, stop and report — do not publish.

### Step 6 — Confirm, then publish (interactive)

Show the human: the DMG path, its size, the SHA256, and the target tag. Ask for
an explicit **"publish"** confirmation. Only on confirmation:

**Reuse existing tag** (overwrite the DMG asset, keep the exe intact):

```bash
gh release upload vX.Y.Z release/StockPlanCompanion-arm64.dmg \
  --repo Arthium-Org/stock-plan-companion-app --clobber
```

**New tag** (create the release; attach the DMG). For a **critical** release,
write `notes.md` first with the severity markers documented in
`docs/Windows-build-setup.md` §4.6 (`Severity: critical` and
`min_supported_version: X.Y.Z`, reproduced exactly). For a normal release, a
plain "What's new" `notes.md` is fine:

```bash
gh release create vX.Y.Z release/StockPlanCompanion-arm64.dmg \
  --repo Arthium-Org/stock-plan-companion-app --title "vX.Y.Z" --notes-file notes.md
```

### Step 7 — Verify the published release

```bash
gh release view vX.Y.Z --repo Arthium-Org/stock-plan-companion-app --json tagName,assets \
  --jq '{tag: .tagName, assets: [.assets[] | {name, size, digest}]}'
# Confirm the DMG's digest matches the shasum from Step 5, and the exe is still attached.
curl -s -o /dev/null -w "dmg latest-download: %{http_code}\n" -L --range 0-0 \
  https://github.com/Arthium-Org/stock-plan-companion-app/releases/latest/download/StockPlanCompanion-arm64.dmg
```

The published DMG digest must equal the local SHA256, and (for reuse-existing-tag)
`StockPlan-Setup.exe` must still be listed. Report the final asset list to the human.

---

## Unsigned fallback (only if signing is impossible)

If the Developer ID cert is genuinely unavailable, `build_release.sh` run with no
`SIGN_IDENTITY` produces an **ad-hoc** DMG — **not notarized, Gatekeeper-blocked
on other Macs**. This is an accepted, documented trade-off (D-01b) and does not
block a launch, but only ship it deliberately: end users must right-click → Open
→ Open (see `README-Mac.md`). Never publish an ad-hoc DMG without telling the
human it's unsigned.

## Prereqs (one-time on the signer's Mac)

| Requirement | Check | Fix |
|---|---|---|
| Erlang/Elixir via asdf `.tool-versions` | `elixir -v` | `asdf install` in the repo root |
| macOS-11 `libcrypto.3.dylib` | `ls ~/openssl-compat/lib/libcrypto.3.dylib` | build OpenSSL from source with `MACOSX_DEPLOYMENT_TARGET=11.0` (see the OpenSSL note in `scripts/build_release.sh`) |
| Xcode command-line tools | `xcode-select -p` | `xcode-select --install` |
| Developer ID Application cert | `security find-identity -v -p codesigning` | install the cert + private key into the login keychain |
| Notary credentials | `xcrun notarytool history --keychain-profile <name>` | `xcrun notarytool store-credentials <name> --apple-id … --team-id … --password …` |
| `gh` with write access | `gh auth status` | `gh auth login` as an account with write to `Arthium-Org` |
