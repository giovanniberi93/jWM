#!/usr/bin/env bash
# Regression: chord-driven launch must position windows according to the
# chord's target, not the launching app's restored geometry. Exercises
# WindowTiler.suppressDisplaceForBundleID.
#
# Bug shape: when the chord launches a cold app, macOS fires
# NSWorkspace.didActivateApplicationNotification → WindowTiler.onFocusChanged
# while the new window is still at its restored position. onFocusChanged's
# poll calls snapFocusedToExactHalf + displaceFullScreenSibling, which read
# the *restored* geometry and displace the fullscreen sibling to the wrong
# half. The chord's own tile() then can't recover because the sibling is no
# longer fullscreen (it just got moved) and gets pruned from the candidate
# list.
#
# Setup: stub1 fullscreen and tracked in slots. Pre-seed stub2's first
# window to land at the RIGHT half. Chord cmd+2+H asks for stub2 on LEFT.
# Without the fix, stub1 ends up on LEFT (picked by the activation race);
# with the fix, stub1 ends up on RIGHT (picked by the chord's tile()).
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

STUB1_BUNDLE="com.giovanniberi93.janzowm.stub1"
STUB2_BUNDLE="com.giovanniberi93.janzowm.stub2"
OVERRIDE_FILE="/tmp/janzowm-stub-initial-frame.txt"

# Clean up the override file even on early failure so it doesn't pollute
# subsequent tests that share the global stub binary.
trap 'rm -f "$OVERRIDE_FILE"' EXIT

# stub1: cold launch + chord-tile fullscreen so janzowm tracks it in slots.
victim_launch "$STUB1_BUNDLE"
stub1_pid=$(victim_get_pid "$STUB1_BUNDLE")
victim_activate "$STUB1_BUNDLE"
post_chord_focus_tile 1 j

read -r fx fy fw fh <<<"$(expected_rect full)"
assert_rect_approx "$stub1_pid" "$fx" "$fy" "$fw" "$fh" || {
    echo "  stub1 did not reach fullscreen (precondition failed)" >&2
    exit 1
}

# Pre-seed stub2's first window to the RIGHT half. The stub consumes this
# on its first window spawn and immediately deletes the file (one-shot).
read -r rx ry rw rh <<<"$(expected_rect right)"
echo "$rx $ry $rw $rh" > "$OVERRIDE_FILE"

# cmd+2+H: focus + tile stub2 LEFT via the launch path.
post_chord_focus_tile 2 h

# Wait for stub2 to materialize.
deadline=$(($(date +%s) + 5))
stub2_pid=""
while (( $(date +%s) < deadline )); do
    stub2_pid=$(victim_get_pid "$STUB2_BUNDLE" 2>/dev/null || echo "")
    if [ -n "$stub2_pid" ] && [ "$stub2_pid" != "0" ]; then break; fi
    sleep 0.1
done
if [ -z "$stub2_pid" ] || [ "$stub2_pid" = "0" ]; then
    echo "  stub2 never launched after chord" >&2
    exit 1
fi

# stub2 should land on the chord's target (LEFT), not its restored frame
# (RIGHT). Failure here means the chord's tile() didn't run or didn't win.
read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$stub2_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  stub2 not on left after chord (chord launch path regressed)" >&2
    exit 1
}

# The real regression check: stub1 must be displaced to RIGHT (opposite of
# the chord's target). Without suppressDisplaceForBundleID it ends up on
# LEFT (opposite of stub2's restored frame) — picked by the activation-time
# snap+displace race rather than by the chord's tile().
assert_rect_approx "$stub1_pid" "$rx" "$ry" "$rw" "$rh" || {
    echo "  stub1 not displaced to right — activation-time snap+displace likely fired on stub2's restored geometry" >&2
    exit 1
}
