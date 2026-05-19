#!/usr/bin/env bash
# Scenario 1: app sitting at fullscreen rect (not put there by jwm) should get
# displaced when user chord-tiles another app via cmd+N+H. Exercises the
# tile-then-activate order in onFocusTile (jwmApp.swift:150-160) — defocus-
# promote on the previously-active app must fire in time for tile()'s
# findDisplacementCandidate to find it.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# Preheat stub1 so cmd+1+H takes the running-with-windows path
victim_launch com.giovanniberi93.jwm.stub1
stub1_pid=$(victim_get_pid com.giovanniberi93.jwm.stub1)

# stub2 is the "natively-zoomed" app
victim_launch com.giovanniberi93.jwm.stub2
stub2_pid=$(victim_get_pid com.giovanniberi93.jwm.stub2)
victim_activate com.giovanniberi93.jwm.stub2

# Wait for post-activation poll to expire so promote can ONLY happen via the
# defocus path on the next activation event
sleep 0.6

# Simulate native zoom: stub2 at exact fullscreen rect, no jwm event fired
read -r fx fy fw fh <<<"$(expected_rect full)"
victim_set_rect "$stub2_pid" "$fx" "$fy" "$fw" "$fh"

# cmd+1+H: focus stub1 AND tile left
post_chord_focus_tile 1 h

# stub1 on left
read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$stub1_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  stub1 did not tile left" >&2
    exit 1
}

# stub2 displaced to right (depends on defocus-promote firing before tile)
read -r rx ry rw rh <<<"$(expected_rect right)"
assert_rect_approx "$stub2_pid" "$rx" "$ry" "$rw" "$rh"
