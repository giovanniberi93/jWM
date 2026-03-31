#!/bin/bash
# Generates app_icon.svg and all required macOS app icon PNGs
# from the menu bar icon SVG (the single source of truth).
#
# Usage: ./scripts/generate_app_icons.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MENU_BAR_SVG="$SCRIPT_DIR/../jwm/Assets.xcassets/MenuBarIcon.imageset/icon.svg"
APP_ICON_SVG="$SCRIPT_DIR/../jwm/Assets.xcassets/AppIcon.appiconset/app_icon.svg"
OUT_DIR="$SCRIPT_DIR/../jwm/Assets.xcassets/AppIcon.appiconset"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT

# --- Step 1: Generate app_icon.svg from menu bar icon ---

# Extract inner content (everything between <svg ...> and </svg>)
INNER=$(sed -n '/<svg/,/<\/svg>/{ /<svg/d; /<\/svg>/d; p; }' "$MENU_BAR_SVG")

# Swap colors for app icon (black → white on coloured background)
INNER=$(echo "$INNER" \
    | sed 's/fill="black"/fill="white"/g' \
    | sed 's/stroke="black"/stroke="white"/g')

cat > "$APP_ICON_SVG" << SVGEOF
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#5B9BF2"/>
      <stop offset="100%" stop-color="#2563EB"/>
    </linearGradient>
  </defs>

  <!-- macOS-style rounded rect background -->
  <rect width="1024" height="1024" rx="228" ry="228" fill="url(#bg)"/>

  <!--
    Menu bar icon scaled up and centered in the 1024x1024 canvas.
    Scale factor ~36x, offset to center: x+220, y+190
  -->
  <g transform="translate(220, 190) scale(36)">
$INNER
  </g>
</svg>
SVGEOF

echo "Generated $APP_ICON_SVG"

# --- Step 2: Clear Quick Look cache and render PNGs ---

qlmanage -r cache > /dev/null 2>&1

qlmanage -t -s 1024 -o "$TMP_DIR" "$APP_ICON_SVG" > /dev/null 2>&1
RENDERED="$TMP_DIR/app_icon.svg.png"

if [ ! -f "$RENDERED" ]; then
    echo "Error: qlmanage failed to render $APP_ICON_SVG"
    exit 1
fi

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

echo "Done."
