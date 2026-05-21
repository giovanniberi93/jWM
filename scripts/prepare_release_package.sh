#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

APP_PATH="build/Build/Products/Release/janzowm.app"
BUNDLE_ID="com.giovanniberi93.janzowm"

RAW="$(git describe --tags --dirty --match 'v*')"
case "$RAW" in
    *-dirty)
        echo "Refusing to package a dirty tree: $RAW" >&2
        exit 1
        ;;
esac
VERSION="${RAW#v}"

rm -rf "$APP_PATH"
make release

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"

codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_PATH"

ZIP_PATH="build/janzoWM-${VERSION}.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Packaged: $ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
