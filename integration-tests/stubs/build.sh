#!/usr/bin/env bash
# Build three minimal AppKit stub apps used as victim apps in integration
# tests. Each stub shares the same compiled binary but is packaged into a
# distinct .app bundle with a unique bundle id so jwm can bind app1/app2/app3
# to com.giovanniberi93.jwm.stub{1,2,3}. Registered with Launch Services so
# `open -b` resolves them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$ROOT/build/test-stubs"
SRC="$ROOT/integration-tests/stubs/jwm-stub.swift"
BIN="$BUILD_DIR/jwm-stub"

mkdir -p "$BUILD_DIR"
swiftc -O "$SRC" -o "$BIN"

NAMES=(JwmStub1 JwmStub2 JwmStub3)
PREFIX="com.giovanniberi93.jwm.stub"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"
    n=$((i + 1))
    app="$BUILD_DIR/$name.app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS"
    cp "$BIN" "$app/Contents/MacOS/$name"
    cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$name</string>
    <key>CFBundleIdentifier</key><string>${PREFIX}${n}</string>
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
    echo "Built $app  (${PREFIX}${n})"
done
