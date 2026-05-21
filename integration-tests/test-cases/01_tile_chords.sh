#!/usr/bin/env bash
# The three basic tile chords:
#   ctrl+cmd+H → left half
#   ctrl+cmd+L → right half
#   ctrl+cmd+J → fill visibleFrame (NOT native fullscreen — same desktop,
#                menu bar and Dock still visible). The rect match implicitly
#                verifies non-native: a native fullscreen window would fill
#                the entire screen including menu bar, producing a different
#                rect.
# Between each chord the window is reset to a non-half rect so a no-op is
# detectable.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.giovanniberi93.janzowm.stub1
victim_activate com.giovanniberi93.janzowm.stub1
pid=$(victim_get_pid com.giovanniberi93.janzowm.stub1)

for entry in "h left" "l right" "j full"; do
    read -r key dir <<<"$entry"
    victim_set_rect "$pid" 200 200 600 400
    sleep 0.1

    post_tile_current "$key"

    read -r ex ey ew eh <<<"$(expected_rect "$dir")"
    assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"
done
