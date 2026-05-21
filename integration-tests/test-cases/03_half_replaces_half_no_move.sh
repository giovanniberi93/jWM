#!/usr/bin/env bash
# Half-tile replacing another half-tile must NOT cascade-move the previous
# occupant. Only full-screen apps get auto-displaced (CLAUDE.md design constraint).
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# 1. stub1 → left
victim_launch com.giovanniberi93.janzowm.stub1
victim_activate com.giovanniberi93.janzowm.stub1
stub1_pid=$(victim_get_pid com.giovanniberi93.janzowm.stub1)
victim_set_rect "$stub1_pid" 300 300 500 350
sleep 0.1
post_tile_current h
read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$stub1_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  setup failed: stub1 not on left" >&2
    exit 1
}

# 2. stub2 → left (same slot)
victim_launch com.giovanniberi93.janzowm.stub2
victim_activate com.giovanniberi93.janzowm.stub2
stub2_pid=$(victim_get_pid com.giovanniberi93.janzowm.stub2)
victim_set_rect "$stub2_pid" 400 400 500 350
sleep 0.1
post_tile_current h
assert_rect_approx "$stub2_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  stub2 did not tile left" >&2
    exit 1
}

# 3. stub1 must still be on left (unchanged — no auto-rearrange for halves)
assert_rect_stable "$stub1_pid" "$lx" "$ly" "$lw" "$lh"
