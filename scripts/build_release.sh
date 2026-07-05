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

APP_NAME="StockPlan"
APP_BUNDLE="release/$APP_NAME.app"
DMG_OUT="release/$APP_NAME.dmg"
TEMP_DMG="release/.$APP_NAME.tmp.dmg"
BG_PNG="release/.dmg_background.png"
MOUNT_POINT="/Volumes/$APP_NAME"
RELEASE_SRC="_build/prod/rel/stock_plan"

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

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>StockPlan</string>
    <key>CFBundleIdentifier</key>
    <string>com.stockplan.app</string>
    <key>CFBundleName</key>
    <string>StockPlan</string>
    <key>CFBundleDisplayName</key>
    <string>Stock Plan Manager</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
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
    -o "$APP_BUNDLE/Contents/MacOS/StockPlan" scripts/launcher.c
chmod +x "$APP_BUNDLE/Contents/MacOS/StockPlan"

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

echo "==> Re-signing modified binaries"
codesign --force --sign - "$CRYPTO_LIB_DIR/libcrypto.3.dylib"
codesign --force --sign - "$CRYPTO_LIB_DIR/crypto.so"
codesign --force --sign - "$CRYPTO_LIB_DIR/otp_test_engine.so"

echo "==> Ad-hoc signing the bundle"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign -dv "$APP_BUNDLE" 2>&1 | head -3

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

echo ""
echo "Built:"
ls -lh "$DMG_OUT"
echo ""
echo "Share $DMG_OUT — recipient: double-click DMG, drag StockPlan to Applications, double-click StockPlan in /Applications."
echo "First-launch override: System Settings → Privacy & Security → 'Open Anyway' once."
