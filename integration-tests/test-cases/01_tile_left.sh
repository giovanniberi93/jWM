#!/usr/bin/env bash
# ctrl+cmd+H tiles the focused app's window to the left half.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.apple.Terminal
victim_activate com.apple.Terminal
pid=$(victim_get_pid com.apple.Terminal)

# Start at a non-half rect so we can detect a no-op
victim_set_rect "$pid" 200 200 600 400
sleep 0.1

post_tile_current h

read -r ex ey ew eh <<<"$(expected_rect left)"
assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"
