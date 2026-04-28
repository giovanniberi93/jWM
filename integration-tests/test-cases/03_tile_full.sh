#!/usr/bin/env bash
# ctrl+cmd+J fills visibleFrame (NOT native fullscreen — same desktop, menu bar
# and Dock still visible). The rect match implicitly verifies non-native: a
# native fullscreen window would fill the entire screen including menu bar,
# producing a different rect.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.apple.Terminal
victim_activate com.apple.Terminal
pid=$(victim_get_pid com.apple.Terminal)

victim_set_rect "$pid" 300 300 500 350
sleep 0.1

post_tile_current j

read -r ex ey ew eh <<<"$(expected_rect full)"
assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"
