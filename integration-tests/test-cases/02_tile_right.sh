#!/usr/bin/env bash
# ctrl+cmd+L tiles the focused app's window to the right half.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.apple.Terminal
victim_activate com.apple.Terminal
pid=$(victim_get_pid com.apple.Terminal)

victim_set_rect "$pid" 200 200 600 400
sleep 0.1

post_tile_current l

read -r ex ey ew eh <<<"$(expected_rect right)"
assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"
