#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Use asdf-managed Erlang/Elixir so the release targets the macOS minimum
# defined in .tool-versions, not whatever Homebrew has stamped today.
export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
export PATH="$ASDF_DATA_DIR/shims:$PATH"

# Backwards-compatible deployment target — picked up by clang and any
# native build steps inside Mix release.
export MACOSX_DEPLOYMENT_TARGET=11.0

APP_NAME="StockPlanCompanion"
APP_BUNDLE="release/$APP_NAME.app"
# Stable, version-LESS distribution filename so the GitHub "magic" download URL
# (…/releases/latest/download/StockPlanCompanion-arm64.dmg) stays valid across
# every release. The version lives in the git tag and mix.exs, not the filename.
DMG_OUT="release/StockPlanCompanion-arm64.dmg"
TEMP_DMG="release/.$APP_NAME.tmp.dmg"
BG_PNG="release/.dmg_background.png"
MOUNT_POINT="/Volumes/$APP_NAME"
RELEASE_SRC="_build/prod/rel/stock_plan"

# App version — single source of truth is mix.exs. Stamped into Info.plist so
# Finder "Get Info" matches the release. (The in-app update check reads the OTP
# application vsn, also from mix.exs — not Info.plist — so these stay in lockstep.)
APP_VERSION="$(sed -nE 's/^[[:space:]]*version:[[:space:]]*"([^"]+)".*/\1/p' mix.exs | head -1)"
if [ -z "$APP_VERSION" ]; then
    echo "ERROR: could not read version: from mix.exs" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Code-signing / notarization configuration (all optional — unset => local dev)
#
#   SIGN_IDENTITY   Developer ID Application identity for a DISTRIBUTABLE build,
#                   e.g. "Developer ID Application: Opsflow LLC (SL8GR6RD2C)".
#                   Unset or "-" => ad-hoc signing: fine for local runs, but NOT
#                   notarizable and Gatekeeper-blocked on other Macs.
#
#   Notary credentials (only used when SIGN_IDENTITY is a real identity), pick one:
#     NOTARY_KEYCHAIN_PROFILE   name of a profile stored via
#                               `xcrun notarytool store-credentials` (preferred)
#   — or —
#     APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD   (app-specific password)
#
# With a real SIGN_IDENTITY AND notary creds, the script produces a fully
# signed + notarized + stapled DMG ready for `gh release create`.
# ---------------------------------------------------------------------------
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

notary_creds_present() {
    [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ] || \
        { [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; }
}

# notarize <path-to-.zip-or-.dmg> — submit and block until Apple returns a verdict.
notarize() {
    if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
        xcrun notarytool submit "$1" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    else
        xcrun notarytool submit "$1" \
            --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
    fi
}

echo "==> Cleaning previous artifacts"
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
rm -rf "$APP_BUNDLE" "$DMG_OUT" "$TEMP_DMG" "$BG_PNG"

echo "==> Fetching prod dependencies"
MIX_ENV=prod mix deps.get --only prod

echo "==> Building assets"
MIX_ENV=prod mix assets.deploy

echo "==> Building Mix release"
MIX_ENV=prod mix release --overwrite

echo "==> Assembling $APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp -R "$RELEASE_SRC" "$APP_BUNDLE/Contents/Resources/release"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.stockplan.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Stock Plan Manager</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSBackgroundOnly</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "==> Generating app icon from docs/Logo.png"
ICON_SRC="docs/Logo.png"
if [ ! -f "$ICON_SRC" ]; then
    echo "ERROR: $ICON_SRC not found" >&2
    exit 1
fi
ICONSET_DIR="release/.AppIcon.iconset"
SQ_PNG="release/.icon_square.png"
rm -rf "$ICONSET_DIR" "$SQ_PNG"
mkdir -p "$ICONSET_DIR"

SRC_W=$(sips -g pixelWidth "$ICON_SRC" | awk '/pixelWidth/ {print $2}')
SRC_H=$(sips -g pixelHeight "$ICON_SRC" | awk '/pixelHeight/ {print $2}')
SQ_SIZE=$(( SRC_W < SRC_H ? SRC_W : SRC_H ))
sips -c "$SQ_SIZE" "$SQ_SIZE" "$ICON_SRC" --out "$SQ_PNG" >/dev/null

for pair in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" \
            "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" \
            "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" \
            "1024 icon_512x512@2x.png"; do
    set -- $pair
    sips -z "$1" "$1" "$SQ_PNG" --out "$ICONSET_DIR/$2" >/dev/null
done

iconutil -c icns -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$ICONSET_DIR"
rm -rf "$ICONSET_DIR" "$SQ_PNG"

echo "==> Compiling native launcher"
clang -O2 -Wall -mmacosx-version-min=11.0 \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" scripts/launcher.c
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Bundling OpenSSL (libcrypto)"
# Custom-built openssl with MACOSX_DEPLOYMENT_TARGET=11.0 so the dylib loads
# on macOS 11+ (Homebrew's openssl is stamped with whatever the build host's
# macOS is, which on Tahoe means minos=26 and refuses to load on Sequoia).
OPENSSL_COMPAT_LIB="$HOME/openssl-compat/lib/libcrypto.3.dylib"
OPENSSL_HOMEBREW_LIB="/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib"

if [ -f "$OPENSSL_COMPAT_LIB" ]; then
    OPENSSL_SRC="$OPENSSL_COMPAT_LIB"
else
    echo "ERROR: backwards-compatible openssl not found at $OPENSSL_COMPAT_LIB." >&2
    echo "Build it from source with MACOSX_DEPLOYMENT_TARGET=11.0 first." >&2
    exit 1
fi
CRYPTO_LIB_DIR=$(ls -d "$APP_BUNDLE/Contents/Resources/release/lib/crypto-"*/priv/lib | head -1)
cp "$OPENSSL_SRC" "$CRYPTO_LIB_DIR/libcrypto.3.dylib"
chmod 755 "$CRYPTO_LIB_DIR/libcrypto.3.dylib"
install_name_tool -id "@loader_path/libcrypto.3.dylib" "$CRYPTO_LIB_DIR/libcrypto.3.dylib"
# Rewrite whichever absolute path Erlang's crypto.so was linked against
# (Homebrew path during build) to the bundled relative @loader_path.
install_name_tool -change "$OPENSSL_HOMEBREW_LIB" "@loader_path/libcrypto.3.dylib" "$CRYPTO_LIB_DIR/crypto.so" 2>/dev/null || true
install_name_tool -change "$OPENSSL_HOMEBREW_LIB" "@loader_path/libcrypto.3.dylib" "$CRYPTO_LIB_DIR/otp_test_engine.so" 2>/dev/null || true

echo "==> Signing all Mach-O binaries (inside-out)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "    mode: ad-hoc — local dev only (NOT notarizable; set SIGN_IDENTITY for a release build)"
    SIGN_ARGS=(--force --sign -)
else
    echo "    mode: Developer ID — $SIGN_IDENTITY"
    SIGN_ARGS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
fi

# Sign every nested Mach-O (ERTS executables, .so nifs, the bundled libcrypto)
# BEFORE the bundle. This subsumes the crypto re-sign above and is what
# notarization requires — Apple discourages --deep for distribution.
while IFS= read -r -d '' f; do
    if file "$f" | grep -q "Mach-O"; then
        codesign "${SIGN_ARGS[@]}" "$f"
    fi
done < <(find "$APP_BUNDLE/Contents/Resources" -type f -print0)

# Native launcher, then the bundle itself, signed last.
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"
codesign -dv "$APP_BUNDLE" 2>&1 | head -3

# Notarize + staple the .app itself so it launches offline, even before the
# DMG is stapled (only when a real identity is used).
if [ "$SIGN_IDENTITY" != "-" ]; then
    if notary_creds_present; then
        echo "==> Notarizing the .app (submit + wait, then staple)"
        APP_ZIP="release/.$APP_NAME.notarize.zip"
        ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
        notarize "$APP_ZIP"
        xcrun stapler staple "$APP_BUNDLE"
        rm -f "$APP_ZIP"
    else
        echo "WARNING: SIGN_IDENTITY is set but no notary credentials were provided."
        echo "         The .app is Developer-ID signed but NOT notarized — it will be"
        echo "         Gatekeeper-blocked on other Macs. Set NOTARY_KEYCHAIN_PROFILE (or"
        echo "         APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD) for a shippable build."
    fi
fi

echo "==> Generating DMG background image"
swift scripts/make_dmg_background.swift "$BG_PNG"

echo "==> Creating writable DMG"
APP_SIZE_KB=$(du -sk "$APP_BUNDLE" | awk '{print $1}')
DMG_SIZE_MB=$(( (APP_SIZE_KB / 1024) + 30 ))
hdiutil create -size "${DMG_SIZE_MB}m" -fs HFS+ -volname "$APP_NAME" -ov "$TEMP_DMG" >/dev/null

echo "==> Mounting and staging contents"
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse >/dev/null
cp -R "$APP_BUNDLE" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"
cp scripts/install_guide.html "$MOUNT_POINT/Install Guide.html"
mkdir "$MOUNT_POINT/.background"
cp "$BG_PNG" "$MOUNT_POINT/.background/background.png"

echo "==> Configuring Finder window layout"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1000, 600}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {150, 170}
        set position of item "Applications" of container window to {450, 170}
        set position of item "Install Guide.html" of container window to {300, 420}
        try
            set extension hidden of file "Install Guide.html" of container window to true
        end try
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync

echo "==> Unmounting and compressing"
hdiutil detach "$MOUNT_POINT" -quiet
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT" >/dev/null
rm "$TEMP_DMG" "$BG_PNG"

# Sign + notarize + staple the DMG container itself so even the download wrapper
# is tamper-evident and mounts without a quarantine prompt (only for real builds).
if [ "$SIGN_IDENTITY" != "-" ]; then
    echo "==> Signing the DMG"
    codesign --force --sign "$SIGN_IDENTITY" "$DMG_OUT"
    if notary_creds_present; then
        echo "==> Notarizing the DMG (submit + wait, then staple)"
        notarize "$DMG_OUT"
        xcrun stapler staple "$DMG_OUT"
    fi
fi

echo ""
echo "Built $APP_VERSION:"
ls -lh "$DMG_OUT"
echo ""
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Signing: ad-hoc (local dev). Recipients must approve on first launch via"
    echo "  System Settings → Privacy & Security → 'Open Anyway'."
    echo "  For a public release, re-run with SIGN_IDENTITY + notary credentials set."
else
    echo "Signing: Developer ID — $SIGN_IDENTITY"
    echo "Verify before publishing:"
    echo "  spctl -a -vvv -t open --context context:primary-signature \"$DMG_OUT\""
    echo "  xcrun stapler validate \"$DMG_OUT\""
    echo "Publish (tag must equal mix.exs version $APP_VERSION):"
    echo "  gh release create v$APP_VERSION \"$DMG_OUT\" \\"
    echo "    --repo Arthium-Org/stock-plan-companion-app --title \"v$APP_VERSION\" --notes-file <notes.md>"
fi
