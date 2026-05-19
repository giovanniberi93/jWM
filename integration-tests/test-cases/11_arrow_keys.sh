#!/usr/bin/env bash
# With useArrowKeys preference on, ctrl+cmd+←/→/↓ tile left/right/maximize.
# Verifies HotkeyManager picks up the live defaults value on each lookup.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

TEST_BUNDLE_ID="com.giovanniberi93.jwm.debug"

defaults write "$TEST_BUNDLE_ID" useArrowKeys -bool YES
trap 'defaults delete "$TEST_BUNDLE_ID" useArrowKeys 2>/dev/null || true' EXIT
# cfprefsd broadcasts the change to the running jwm; give it a moment.
sleep 0.4

victim_launch com.giovanniberi93.jwm.stub1
victim_activate com.giovanniberi93.jwm.stub1
pid=$(victim_get_pid com.giovanniberi93.jwm.stub1)

# Carbon kVK codes for arrows, hardcoded here so test-lib.sh stays unchanged.
LEFT_KC=123
RIGHT_KC=124
DOWN_KC=125
UP_KC=126

post_arrow_tile() {
    local kc="$1"
    osascript <<EOF >/dev/null
tell application "System Events"
    key code $kc using {command down, control down}
end tell
EOF
}

# ← → left half
victim_set_rect "$pid" 200 200 600 400
sleep 0.1
post_arrow_tile $LEFT_KC
read -r ex ey ew eh <<<"$(expected_rect left)"
assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"

# → → right half
victim_set_rect "$pid" 200 200 600 400
sleep 0.1
post_arrow_tile $RIGHT_KC
read -r ex ey ew eh <<<"$(expected_rect right)"
assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"

# ↓ → maximize
victim_set_rect "$pid" 200 200 600 400
sleep 0.1
post_arrow_tile $DOWN_KC
read -r ex ey ew eh <<<"$(expected_rect full)"
assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"

# ↑ → next screen (only when a second screen is connected)
if (( $(screen_count) >= 2 )); then
    cur_rect=$(victim_get_rect "$pid")
    read -r cx cy cw ch <<<"$cur_rect"
    start_screen=$(screen_of_rect "$cx" "$cy" "$cw" "$ch")
    if [ "$start_screen" -lt 0 ]; then
        echo "  could not resolve starting screen for rect $cur_rect" >&2
        exit 1
    fi

    post_arrow_tile $UP_KC
    sleep 0.3

    new_rect=$(victim_get_rect "$pid")
    read -r nx ny nw nh <<<"$new_rect"
    new_screen=$(screen_of_rect "$nx" "$ny" "$nw" "$nh")
    if [ "$new_screen" = "$start_screen" ]; then
        echo "  ↑ did not move window to a different screen (still on $start_screen)" >&2
        echo "  rect: $new_rect" >&2
        exit 1
    fi
fi
