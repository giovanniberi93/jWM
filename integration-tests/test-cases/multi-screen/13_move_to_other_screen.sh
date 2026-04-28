#!/usr/bin/env bash
# ctrl+cmd+k bounces a fullscreen window between screens. Each press must
# (a) move the window to the other screen and (b) preserve fullscreen on
# whichever screen it lands. Three presses ⇒ ends on the screen opposite
# to the start.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

require_screens 2

victim_launch com.apple.Terminal
victim_activate com.apple.Terminal
term_pid=$(victim_get_pid com.apple.Terminal)

# Start fullscreen on the primary screen.
read -r fx fy fw fh <<<"$(expected_rect_on 0 full)"
victim_set_rect "$term_pid" "$fx" "$fy" "$fw" "$fh"
sleep 0.2
post_tile_current j  # promote via tile-current to make sure jwm tracks it
assert_rect_approx "$term_pid" "$fx" "$fy" "$fw" "$fh" || {
    echo "  setup: Terminal not fullscreen on screen 0" >&2
    exit 1
}

start_rect=$(victim_get_rect "$term_pid")
read -r sx sy sw sh <<<"$start_rect"
prev_screen=$(screen_of_rect "$sx" "$sy" "$sw" "$sh")
if [ "$prev_screen" -lt 0 ]; then
    echo "  could not determine starting screen for rect $start_rect" >&2
    exit 1
fi

for i in 1 2 3; do
    post_tile_current k
    sleep 0.3

    cur_rect=$(victim_get_rect "$term_pid")
    read -r cx cy cw ch <<<"$cur_rect"
    cur_screen=$(screen_of_rect "$cx" "$cy" "$cw" "$ch")

    if [ "$cur_screen" -lt 0 ]; then
        echo "  press $i: rect $cur_rect on no known screen" >&2
        exit 1
    fi
    if [ "$cur_screen" = "$prev_screen" ]; then
        echo "  press $i: window stayed on screen $cur_screen (expected to move)" >&2
        echo "  rect: $cur_rect" >&2
        exit 1
    fi

    read -r ex ey ew eh <<<"$(expected_rect_on "$cur_screen" full)"
    assert_rect_approx "$term_pid" "$ex" "$ey" "$ew" "$eh" || {
        echo "  press $i: not fullscreen on destination screen $cur_screen" >&2
        exit 1
    }

    prev_screen=$cur_screen
done

# Sanity: 3 alternations from screen 0 ⇒ end on screen 1 (or whatever ≠ start).
end_rect=$(victim_get_rect "$term_pid")
read -r ex2 ey2 ew2 eh2 <<<"$end_rect"
end_screen=$(screen_of_rect "$ex2" "$ey2" "$ew2" "$eh2")
start_screen=$(screen_of_rect "$sx" "$sy" "$sw" "$sh")
if [ "$end_screen" = "$start_screen" ]; then
    echo "  3 presses left Terminal back on start screen $start_screen (expected odd parity)" >&2
    exit 1
fi
