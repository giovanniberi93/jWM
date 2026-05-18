#!/usr/bin/env bash
# Drag-to-snap on the secondary screen: dragging the title bar to screen 1's
# left / right / top edge band must snap to the matching half (or fullscreen)
# on screen 1, not on the primary. Exercises SnapManager.currentSnapScreen
# tracking, including the top-edge → fullscreen path.
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

# CG y of the physical top of screen 1, used as the drop target for "top".
screen1_top_y=$(screen_top_cg_y 1)

drag_to_edge() {
    local edge="$1"
    victim_set_rect "$pid" "$cx" "$cy" "$sw" "$sh"
    sleep 0.15

    read -r wx wy ww wh <<<"$(victim_get_rect "$pid")"
    local expect_shape
    case "$edge" in
        left|right) expect_shape="$edge" ;;
        top)        expect_shape="full" ;;
    esac
    read -r ex ey ew eh <<<"$(expected_rect_on 1 "$expect_shape")"
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
            # 2px below screen 1's physical top — inside the menu bar area,
            # above visibleFrame. Exercises the Mission Control cursor clamp.
            to_x=$(( ex + ew / 2 ))
            to_y=$(( screen1_top_y + 2 ))
            ;;
    esac

    drag_mouse $(( wx + ww / 2 )) $(( wy + 14 )) "$to_x" "$to_y"
    assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"
}

drag_to_edge left
drag_to_edge right
drag_to_edge top
