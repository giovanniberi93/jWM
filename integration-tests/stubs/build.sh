#!/usr/bin/env bash
# Build minimal AppKit stub apps used as victim apps in integration tests.
# All stubs share the same compiled binary but are packaged into distinct
# .app bundles with unique bundle ids:
#   com.giovanniberi93.janzowm.stub{1,2,3} — well-behaved victims
#   com.giovanniberi93.janzowm.problematic — opt-in misbehaviors via CLI flags
#     (--drift-back-times, --spawn-delay-ms, --windows 0); used to
#     exercise janzowm's defensive logic (guardPosition, onFocusChanged,
#     focusOrLaunch's no-window branch). Pass flags with
#     `open -b <bundle> -n --args ...`.
# Registered with Launch Services so `open -b` resolves them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$ROOT/build/test-stubs"
SRC="$ROOT/integration-tests/stubs/janzowm-stub.swift"
BIN="$BUILD_DIR/janzowm-stub"
OVERLAY_SRC="$ROOT/integration-tests/stubs/overlay-stub.swift"
OVERLAY_BIN="$BUILD_DIR/overlay-stub"

mkdir -p "$BUILD_DIR"
swiftc -O "$SRC" -o "$BIN"
swiftc -O "$OVERLAY_SRC" -o "$OVERLAY_BIN"

NAMES=(JanzoWMStub1 JanzoWMStub2 JanzoWMStub3 JanzoWMStubProblematic JanzoWMStubOverlay)
BUNDLE_IDS=(
    com.giovanniberi93.janzowm.stub1
    com.giovanniberi93.janzowm.stub2
    com.giovanniberi93.janzowm.stub3
    com.giovanniberi93.janzowm.problematic
    com.giovanniberi93.janzowm.overlay
)
# JanzoWMStubOverlay uses the overlay binary; the rest share janzowm-stub.
SRC_BIN_FOR=(janzowm-stub janzowm-stub janzowm-stub janzowm-stub overlay-stub)
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    bundle_id="${BUNDLE_IDS[$i]}"
    src_bin="${SRC_BIN_FOR[$i]}"
    app="$BUILD_DIR/$name.app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS"
    cp "$BUILD_DIR/$src_bin" "$app/Contents/MacOS/$name"
    cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$name</string>
    <key>CFBundleIdentifier</key><string>${bundle_id}</string>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
    "$LSREG" -f "$app"
    echo "Built $app  (${bundle_id})"
done
