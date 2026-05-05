#!/usr/bin/env bash
# Drag-to-snap on the primary screen: dragging the title bar so the cursor
# enters the left / right edge band snaps the window to the matching half.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

skip_if_mouse_disabled

victim_launch com.giovanniberi93.jwm.stub1
victim_activate com.giovanniberi93.jwm.stub1
pid=$(victim_get_pid com.giovanniberi93.jwm.stub1)

# Center a 600x400 rect on the primary screen so the drag is short and the
# starting position never matches a snap shape.
read -r fx fy fw fh <<<"$(expected_rect_on 0 full)"
sw=600; sh=400
cx=$(( fx + (fw - sw) / 2 ))
cy=$(( fy + (fh - sh) / 2 ))

drag_to_edge() {
    local edge="$1"
    victim_set_rect "$pid" "$cx" "$cy" "$sw" "$sh"
    sleep 0.15

    read -r wx wy ww wh <<<"$(victim_get_rect "$pid")"
    read -r ex ey ew eh <<<"$(expected_rect_on 0 "$edge")"
    local to_x to_y
    if [ "$edge" = "left" ]; then
        to_x=$(( ex + 8 ))
    else
        to_x=$(( ex + ew - 8 ))
    fi
    to_y=$(( ey + eh / 2 ))

    # Title bar middle: AX rect includes the title bar, so y+14 lands inside it.
    drag_mouse $(( wx + ww / 2 )) $(( wy + 14 )) "$to_x" "$to_y"
    assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"
}

drag_to_edge left
drag_to_edge right
