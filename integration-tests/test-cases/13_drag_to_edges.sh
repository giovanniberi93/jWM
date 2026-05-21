#!/usr/bin/env bash
# Drag-to-snap on the primary screen: dragging the title bar so the cursor
# enters the left / right / top edge band snaps the window to the matching
# half (left, right) or to fullscreen (top).
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

skip_if_mouse_disabled

# Launch the overlay stub: a borderless level-21 window covering the screen
# whose bundle id is in janzowm's ignoredBundleIDs. This recreates the wild
# Notification-Center-covers-the-click-point condition that exposed the Quartz
# windowAtPoint short-circuit (see SnapManager.getWindowInfoUnderCursor's
# AX fallback). Without this, the fast path almost always succeeds and the
# fallback is untested.
open -gb com.giovanniberi93.janzowm.overlay >/dev/null 2>&1 || true
trap 'osascript -e "tell application id \"com.giovanniberi93.janzowm.overlay\" to quit" 2>/dev/null || true' EXIT

victim_launch com.giovanniberi93.janzowm.stub1
victim_activate com.giovanniberi93.janzowm.stub1
pid=$(victim_get_pid com.giovanniberi93.janzowm.stub1)

# Center a 600x400 rect on the primary screen so the drag is short and the
# starting position never matches a snap shape.
read -r fx fy fw fh <<<"$(expected_rect_on 0 full)"
sw=600; sh=400
cx=$(( fx + (fw - sw) / 2 ))
cy=$(( fy + (fh - sh) / 2 ))

drag_to_edge() {
    local edge="$1"
    victim_set_rect "$pid" "$cx" "$cy" "$sw" "$sh"
    sleep 0.05

    read -r wx wy ww wh <<<"$(victim_get_rect "$pid")"
    # "top" snaps to fullscreen — expectation is the visibleFrame rect.
    local expect_shape
    case "$edge" in
        left|right) expect_shape="$edge" ;;
        top)        expect_shape="full" ;;
    esac
    read -r ex ey ew eh <<<"$(expected_rect_on 0 "$expect_shape")"
    local to_x to_y
    case "$edge" in
        left)
            to_x=$(( ex + 8 ))
            to_y=$(( ey + eh / 2 ))
            ;;
        right)
            to_x=$(( ex + ew - 8 ))
            to_y=$(( ey + eh / 2 ))
            ;;
        top)
            # CG y=2 sits inside the menu bar, above visibleFrame. Drives the
            # cursor right up against the top of the physical display so the
            # Mission Control mitigation (cursor-y clamp) is exercised too.
            to_x=$(( ex + ew / 2 ))
            to_y=2
            ;;
    esac

    # Title bar middle: AX rect includes the title bar, so y+14 lands inside it.
    drag_mouse $(( wx + ww / 2 )) $(( wy + 14 )) "$to_x" "$to_y"
    assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"
}

drag_to_edge left
drag_to_edge right
drag_to_edge top
