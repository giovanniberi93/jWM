#!/usr/bin/env bash
# Intra-app focus-change displacement: when focus shifts between two windows
# of the *same* app (Cmd+`, click on background window, Window menu, etc.)
# without any jwm chord and without a cross-app activation, jwm should still
# react. If the now-focused sibling sits at a half rect and another window is
# tracked as fullscreen, that fullscreen window must be displaced to the
# opposite half.
#
# This exercises the AX-observer path (FocusWatcher) — not the chord path of
# test 16 and not the NSWorkspace-activation path of test 02. Setup is
# identical to test 16 but the trigger is the AX focused-window-changed
# notification fired by NSWindow.makeKeyAndOrderFront, with w2 pre-seeded at
# the left half so snapFocusedToExactHalf matches without any user input.

set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

OVERRIDE_FILE="/tmp/jwm-stub-initial-frame.txt"
trap 'rm -f "$OVERRIDE_FILE"' EXIT

read -r fx fy fw fh <<<"$(expected_rect full)"
read -r lx ly lw lh <<<"$(expected_rect left)"
read -r rx ry rw rh <<<"$(expected_rect right)"

# 1. stub1 + w1, tiled fullscreen so the slot map has a candidate to displace.
victim_launch com.giovanniberi93.jwm.stub1
victim_activate com.giovanniberi93.jwm.stub1
stub1_pid=$(victim_get_pid com.giovanniberi93.jwm.stub1)
victim_set_rect "$stub1_pid" 300 300 500 350
sleep 0.1
post_tile_current j
assert_rect_approx "$stub1_pid" "$fx" "$fy" "$fw" "$fh" || {
    echo "  setup failed: w1 did not go full-screen" >&2
    exit 1
}

# 2. Pre-seed w2's spawn rect to the left half. When the stub's SIGUSR1
# handler creates w2 and calls makeKeyAndOrderFront, w2 lands at left and
# becomes AX-focused — the AX focus-changed notification fires with no
# NSWorkspace activation (same app, same pid).
echo "$lx $ly $lw $lh" > "$OVERRIDE_FILE"
victim_add_window com.giovanniberi93.jwm.stub1
sleep 0.6

# 3. w1 (still AppleScript-window-2 behind w2) must have been displaced to
# the right half by the FocusWatcher → onFocusChanged path. Same polling
# shape as test 16's displaced-window check.
deadline=$(($(date +%s) + 1))
last=""
while (( $(date +%s) <= deadline )); do
    last=$(osascript <<EOF 2>/dev/null || echo ""
tell application "System Events"
    tell (first process whose unix id is $stub1_pid)
        if (count of windows) < 2 then return ""
        set p to position of window 2
        set s to size of window 2
        return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
    end tell
end tell
EOF
)
    if [ -n "$last" ]; then
        read -r ax ay aw ah <<<"$last"
        if [[ "$ax" =~ ^-?[0-9]+$ && "$ay" =~ ^-?[0-9]+$ && "$aw" =~ ^[0-9]+$ && "$ah" =~ ^[0-9]+$ ]]; then
            dx=$(( ax - rx )); dy=$(( ay - ry ))
            dw=$(( aw - rw )); dh=$(( ah - rh ))
            dx=${dx#-}; dy=${dy#-}; dw=${dw#-}; dh=${dh#-}
            size_tol_w=$(( rw * TOL_SIZE_PCT / 100 ))
            size_tol_h=$(( rh * TOL_SIZE_PCT / 100 ))
            if (( dx < TOL_POS && dy < TOL_POS && dw <= size_tol_w && dh <= size_tol_h )); then
                exit 0
            fi
        fi
    fi
    sleep 0.05
done

echo "  w1 was not displaced to the right half on intra-app focus change" >&2
echo "  expected: $rx $ry $rw $rh" >&2
echo "  actual:   ${last:-<unreadable>}" >&2
exit 1
