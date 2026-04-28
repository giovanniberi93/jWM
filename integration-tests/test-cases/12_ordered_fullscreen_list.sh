#!/usr/bin/env bash
# Ordered fullscreen list: jwm tracks more than one full-screen app at a time
# and pops displacement targets in reverse order of promotion. Three apps go
# full in sequence (T, TE, N), then two successive half-tile chords should
# displace N first, TE second.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.apple.Terminal
victim_launch com.apple.TextEdit
victim_launch com.apple.Notes

term_pid=$(victim_get_pid com.apple.Terminal)
te_pid=$(victim_get_pid com.apple.TextEdit)
notes_pid=$(victim_get_pid com.apple.Notes)

read -r fx fy fw fh <<<"$(expected_rect full)"
read -r lx ly lw lh <<<"$(expected_rect left)"
read -r rx ry rw rh <<<"$(expected_rect right)"

# Mirrors test 11's natively-zoomed setup. Three sequential activations let
# defocus-promote on each transition add the prior frontmost to the slot.
victim_activate com.apple.Terminal
victim_set_rect "$term_pid" "$fx" "$fy" "$fw" "$fh"
sleep 0.6

victim_activate com.apple.TextEdit
victim_set_rect "$te_pid" "$fx" "$fy" "$fw" "$fh"
sleep 0.6

victim_activate com.apple.Notes
victim_set_rect "$notes_pid" "$fx" "$fy" "$fw" "$fh"
sleep 0.6

# Chord 1: focus Terminal + tile half-left. defocus-promote on Notes lands it
# at the top of the fullscreen list; findDisplacementCandidate pops it.
post_chord_focus_tile 1 h

assert_rect_approx "$term_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  Terminal did not tile left" >&2
    exit 1
}
assert_rect_approx "$notes_pid" "$rx" "$ry" "$rw" "$rh" || {
    echo "  Notes did not displace right (top of list)" >&2
    exit 1
}

# Chord 2: focus Notes + tile half-left. Notes is no longer full; previous
# frontmost (Terminal) is half, so neither gets re-added. List should still
# carry TextEdit from the step-2 promotion — it pops next.
post_chord_focus_tile 3 h

assert_rect_approx "$notes_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  Notes did not tile left on second chord" >&2
    exit 1
}
assert_rect_approx "$te_pid" "$rx" "$ry" "$rw" "$rh" || {
    echo "  TextEdit did not displace right (next in list)" >&2
    exit 1
}
