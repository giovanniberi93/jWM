#!/usr/bin/env bash
# Half-tile replacing another half-tile must NOT cascade-move the previous
# occupant. Only full-screen apps get auto-displaced (CLAUDE.md design constraint).
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# 1. Terminal → left
victim_launch com.apple.Terminal
victim_activate com.apple.Terminal
term_pid=$(victim_get_pid com.apple.Terminal)
victim_set_rect "$term_pid" 300 300 500 350
sleep 0.1
post_tile_current h
read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$term_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  setup failed: Terminal not on left" >&2
    exit 1
}

# 2. TextEdit → left (same slot)
victim_launch com.apple.TextEdit
victim_activate com.apple.TextEdit
te_pid=$(victim_get_pid com.apple.TextEdit)
victim_set_rect "$te_pid" 400 400 500 350
sleep 0.1
post_tile_current h
assert_rect_approx "$te_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  TextEdit did not tile left" >&2
    exit 1
}

# 3. Terminal must still be on left (unchanged — no auto-rearrange for halves)
assert_rect_stable "$term_pid" "$lx" "$ly" "$lw" "$lh"
