#!/usr/bin/env bash
# Scenario 1: app sitting at fullscreen rect (not put there by jwm) should get
# displaced when user chord-tiles another app via cmd+N+H. Exercises the
# tile-then-activate order in onFocusTile (jwmApp.swift:150-160) — defocus-
# promote on the previously-active app must fire in time for tile()'s
# findDisplacementCandidate to find it.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# Preheat Terminal so cmd+1+H takes the running-with-windows path
victim_launch com.apple.Terminal
term_pid=$(victim_get_pid com.apple.Terminal)

# TextEdit is the "natively-zoomed" app
victim_launch com.apple.TextEdit
te_pid=$(victim_get_pid com.apple.TextEdit)
victim_activate com.apple.TextEdit

# Wait for post-activation poll to expire so promote can ONLY happen via the
# defocus path on the next activation event
sleep 0.6

# Simulate native zoom: TextEdit at exact fullscreen rect, no jwm event fired
read -r fx fy fw fh <<<"$(expected_rect full)"
victim_set_rect "$te_pid" "$fx" "$fy" "$fw" "$fh"

# cmd+1+H: focus Terminal AND tile left
post_chord_focus_tile 1 h

# Terminal on left
read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$term_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  Terminal did not tile left" >&2
    exit 1
}

# TextEdit displaced to right (depends on defocus-promote firing before tile)
read -r rx ry rw rh <<<"$(expected_rect right)"
assert_rect_approx "$te_pid" "$rx" "$ry" "$rw" "$rh"
