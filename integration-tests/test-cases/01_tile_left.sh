#!/usr/bin/env bash
# ctrl+cmd+H tiles the focused app's window to the left half.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.giovanniberi93.jwm.stub1
victim_activate com.giovanniberi93.jwm.stub1
pid=$(victim_get_pid com.giovanniberi93.jwm.stub1)

# Start at a non-half rect so we can detect a no-op
victim_set_rect "$pid" 200 200 600 400
sleep 0.1

post_tile_current h

read -r ex ey ew eh <<<"$(expected_rect left)"
assert_rect_approx "$pid" "$ex" "$ey" "$ew" "$eh"
