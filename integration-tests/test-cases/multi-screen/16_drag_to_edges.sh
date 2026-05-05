#!/usr/bin/env bash
# Drag-to-snap on the secondary screen: dragging the title bar to screen 1's
# left / right edge band must snap to the matching half on screen 1, not on
# the primary. Exercises SnapManager.currentSnapScreen tracking.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

require_screens 2
skip_if_mouse_disabled

victim_launch com.giovanniberi93.jwm.stub1
victim_activate com.giovanniberi93.jwm.stub1
pid=$(victim_get_pid com.giovanniberi93.jwm.stub1)

# Center a 600x400 rect on screen 1 so the drag stays on that screen.
read -r fx fy fw fh <<<"$(expected_rect_on 1 full)"
sw=600; sh=400
cx=$(( fx + (fw - sw) / 2 ))
cy=$(( fy + (fh - sh) / 2 ))

drag_to_edge() {
    local edge="$1"
    victim_set_rect "$pid" "$cx" "$cy" "$sw" "$sh"
    sleep 0.15

    read -r wx wy ww wh <<<"$(victim_get_rect "$pid")"
    read -r ex ey ew eh <<<"$(expected_rect_on 1 "$edge")"
    local to_x to_y
    if [ "$edge" = "left" ]; then
        to_x=$(( ex + 8 ))
    else
        to_x=$(( ex + ew - 8 ))
    fi
    to_y=$(( ey + eh / 2 ))

    drag_mouse $(( wx + ww / 2 )) $(( wy + 14 )) "$to_x" "$to_y"
    assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"
}

drag_to_edge left
drag_to_edge right
