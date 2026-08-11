#!/usr/bin/env bash
# package_app.sh — build ShopPilot release + assemble a double-clickable .app
# bundle, ad-hoc signed, with fixtures bundled. Output:
#   dist/ShopPilot-macOS.zip   (universal: arm64 + x86_64)
#
# Usage: ./scripts/package_app.sh
# Requires: Xcode toolchain (xcode-select -p must point at an Xcode install).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="ShopPilot"
# Explicit version override: VERSION=0.02 ./scripts/package_app.sh
VERSION="${VERSION:-$(git describe --tags --always 2>/dev/null || echo "0.0.0-dev")}"
# Explicit zip name override: ZIP_NAME=ShopPilot-0.02-macOS.zip ./scripts/package_app.sh
ZIP_NAME="${ZIP_NAME:-$APP_NAME-macOS.zip}"
BUNDLE_ID="com.shoppilot.app"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "=== ShopPilot package ($VERSION) ==="

# 1. Release builds for both architectures.
echo "-- building release (x86_64) --"
./scripts/swift_locked.sh build -c release --product "$APP_NAME" --arch x86_64
echo "-- building release (arm64) --"
./scripts/swift_locked.sh build -c release --product "$APP_NAME" --arch arm64

X86_BIN=".build/x86_64-apple-macosx/release/$APP_NAME"
ARM_BIN=".build/arm64-apple-macosx/release/$APP_NAME"
[[ -f "$X86_BIN" ]] || { echo "ERROR: x86_64 binary missing: $X86_BIN" >&2; exit 1; }
[[ -f "$ARM_BIN" ]] || { echo "ERROR: arm64 binary missing: $ARM_BIN" >&2; exit 1; }

# 2. Assemble bundle layout.
echo "-- assembling bundle --"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Universal binary via lipo.
lipo -create "$X86_BIN" "$ARM_BIN" -output "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# 3. Info.plist.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>ShopPilot</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Personal use — no warranty.</string>
</dict>
</plist>
PLIST

# 4. Bundle fixtures under Contents/Resources (proper bundle layout — anything
#    at the bundle root makes codesign report "unsealed contents"). Note: the
#    app also checks Bundle.main.bundleURL/fixtures for calibration_square.nc,
#    which is currently absent — the built-in air-cut square fallback is used.
if [[ -d "fixtures" ]]; then
    echo "-- bundling fixtures --"
    cp -R fixtures "$RESOURCES_DIR/fixtures"
fi

# 4b. App icon (SPK-visual): the .icns ships in Resources; Info.plist points
#     at CFBundleIconFile=ShopPilot. Regenerate with:
#     swift <T>/make_shoppilot_icon.swift dist/icon-src && iconutil -c icns ...
if [[ -f "dist/icon-src/ShopPilot.icns" ]]; then
    echo "-- bundling app icon --"
    cp "dist/icon-src/ShopPilot.icns" "$RESOURCES_DIR/ShopPilot.icns"
fi

# 5. Ad-hoc codesign (runs locally; Gatekeeper will still warn on first open
#    from another Mac — right-click → Open, or xattr -dr com.apple.quarantine).
echo "-- ad-hoc codesign --"
codesign --force --deep --sign - "$APP_DIR"

# 6. Zip.
echo "-- zipping --"
cd "$DIST_DIR"
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$ZIP_NAME"

echo ""
echo "=== DONE ==="
echo "  $DIST_DIR/$ZIP_NAME"
echo "  Universal (arm64 + x86_64), ad-hoc signed."
echo ""
echo "On first open from another Mac: right-click → Open (Gatekeeper), or:"
echo "  xattr -dr com.apple.quarantine $APP_NAME.app"
