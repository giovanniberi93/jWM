#!/usr/bin/env bash
# Ordered fullscreen list: janzowm tracks more than one full-screen app at a time
# and pops displacement targets in reverse order of promotion. Three apps go
# full in sequence (T, TE, N), then two successive half-tile chords should
# displace N first, TE second.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.giovanniberi93.janzowm.stub1
victim_launch com.giovanniberi93.janzowm.stub2
victim_launch com.giovanniberi93.janzowm.stub3

stub1_pid=$(victim_get_pid com.giovanniberi93.janzowm.stub1)
stub2_pid=$(victim_get_pid com.giovanniberi93.janzowm.stub2)
stub3_pid=$(victim_get_pid com.giovanniberi93.janzowm.stub3)

read -r fx fy fw fh <<<"$(expected_rect full)"
read -r lx ly lw lh <<<"$(expected_rect left)"
read -r rx ry rw rh <<<"$(expected_rect right)"

# Mirrors test 08's natively-zoomed setup. Three sequential activations let
# defocus-promote on each transition add the prior frontmost to the slot.
victim_activate com.giovanniberi93.janzowm.stub1
victim_set_rect "$stub1_pid" "$fx" "$fy" "$fw" "$fh"
sleep 0.6

victim_activate com.giovanniberi93.janzowm.stub2
victim_set_rect "$stub2_pid" "$fx" "$fy" "$fw" "$fh"
sleep 0.6

victim_activate com.giovanniberi93.janzowm.stub3
victim_set_rect "$stub3_pid" "$fx" "$fy" "$fw" "$fh"
sleep 0.6

# Chord 1: focus stub1 + tile half-left. defocus-promote on stub3 lands it
# at the top of the fullscreen list; findDisplacementCandidate pops it.
post_chord_focus_tile 1 h

assert_rect_approx "$stub1_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  stub1 did not tile left" >&2
    exit 1
}
assert_rect_approx "$stub3_pid" "$rx" "$ry" "$rw" "$rh" || {
    echo "  stub3 did not displace right (top of list)" >&2
    exit 1
}

# Chord 2: focus stub3 + tile half-left. stub3 is no longer full; previous
# frontmost (stub1) is half, so neither gets re-added. List should still
# carry stub2 from the step-2 promotion — it pops next.
post_chord_focus_tile 3 h

assert_rect_approx "$stub3_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  stub3 did not tile left on second chord" >&2
    exit 1
}
assert_rect_approx "$stub2_pid" "$rx" "$ry" "$rw" "$rh" || {
    echo "  stub2 did not displace right (next in list)" >&2
    exit 1
}
