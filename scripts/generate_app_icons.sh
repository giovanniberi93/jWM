#!/bin/bash
# Renders app_icon.svg into all required macOS app icon sizes.
# Uses qlmanage (built into macOS) + sips for resizing.
#
# Usage: ./scripts/generate_app_icons.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SVG="$SCRIPT_DIR/../jwm/Assets.xcassets/AppIcon.appiconset/app_icon.svg"
OUT_DIR="$SCRIPT_DIR/../jwm/Assets.xcassets/AppIcon.appiconset"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT

# Render SVG at the largest size we need (1024px)
qlmanage -t -s 1024 -o "$TMP_DIR" "$SVG" > /dev/null 2>&1
RENDERED="$TMP_DIR/app_icon.svg.png"

if [ ! -f "$RENDERED" ]; then
    echo "Error: qlmanage failed to render $SVG"
    exit 1
fi

# Required sizes: name -> pixel dimensions
declare -a SIZES=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

for entry in "${SIZES[@]}"; do
    name="${entry%%:*}"
    pixels="${entry##*:}"
    cp "$RENDERED" "$TMP_DIR/$name"
    sips -z "$pixels" "$pixels" "$TMP_DIR/$name" --out "$OUT_DIR/$name" > /dev/null 2>&1
    echo "  $name (${pixels}px)"
done

echo "Done. Icons written to $OUT_DIR"
