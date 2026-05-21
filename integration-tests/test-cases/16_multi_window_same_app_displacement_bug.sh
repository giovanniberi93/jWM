#!/usr/bin/env bash
# Regression test for multi-window displacement: a full-screen window must be
# displaced to the opposite half when *another window of the same app* is
# tiled to a half. Same rule as test 02, but with both windows sharing a pid.
#
# Setup
#   1. stub1 launches with one window (w1) and is tiled to full-screen.
#   2. A second window (w2) is spawned inside stub1 via SIGUSR1. NSWindow's
#      makeKeyAndOrderFront brings w2 to the front; w1 sits behind it.
#   3. ctrl+cmd+L tiles the focused window (w2) to the right half.
#
# Expected: w1 auto-shrinks to the left half.

set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# Read rect of a specific AppleScript-indexed window (1 = frontmost). Same
# "x y w h" CG-coord format as victim_get_rect.
get_rect_window_n() {
    local pid="$1" n="$2"
    osascript <<EOF
tell application "System Events"
    tell (first process whose unix id is $pid)
        if (count of windows) < $n then return ""
        set p to position of window $n
        set s to size of window $n
        return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
    end tell
end tell
EOF
}

read -r fx fy fw fh <<<"$(expected_rect full)"
read -r lx ly lw lh <<<"$(expected_rect left)"
read -r rx ry rw rh <<<"$(expected_rect right)"

# 1. stub1 + w1, tiled full.
victim_launch com.giovanniberi93.janzowm.stub1
victim_activate com.giovanniberi93.janzowm.stub1
stub1_pid=$(victim_get_pid com.giovanniberi93.janzowm.stub1)
victim_set_rect "$stub1_pid" 300 300 500 350
sleep 0.1
post_tile_current j
assert_rect_approx "$stub1_pid" "$fx" "$fy" "$fw" "$fh" || {
    echo "  setup failed: w1 did not go full-screen" >&2
    exit 1
}

# 2. Spawn w2 inside stub1. The SIGUSR1 handler calls makeKeyAndOrderFront,
# so after this returns w2 is z-order top and AX-focused, w1 is behind.
victim_add_window com.giovanniberi93.janzowm.stub1
sleep 0.6

# 3. Tile current (= w2) to the right half. No NSWorkspace activation fires
# (same app), so onFocusChanged isn't involved — this exercises tile()'s
# inline displacement path.
post_tile_current l

# w2 must land on the right half — verifies the focused-window tile worked.
assert_rect_approx "$stub1_pid" "$rx" "$ry" "$rw" "$rh" || {
    echo "  w2 (focused window) did not tile right" >&2
    exit 1
}

# 4. w1 (AppleScript window 2, since w2 is window 1) must have been displaced
# to the left half. assert_rect_approx polls the front window via pid; here
# we need window 2 specifically, so check the rect inline using the same
# tolerance model.
deadline=$(($(date +%s) + 1))
last=""
while (( $(date +%s) <= deadline )); do
    last=$(get_rect_window_n "$stub1_pid" 2 2>/dev/null || echo "")
    if [ -n "$last" ]; then
        read -r ax ay aw ah <<<"$last"
        if [[ "$ax" =~ ^-?[0-9]+$ && "$ay" =~ ^-?[0-9]+$ && "$aw" =~ ^[0-9]+$ && "$ah" =~ ^[0-9]+$ ]]; then
            dx=$(( ax - lx )); dy=$(( ay - ly ))
            dw=$(( aw - lw )); dh=$(( ah - lh ))
            dx=${dx#-}; dy=${dy#-}; dw=${dw#-}; dh=${dh#-}
            size_tol_w=$(( lw * TOL_SIZE_PCT / 100 ))
            size_tol_h=$(( lh * TOL_SIZE_PCT / 100 ))
            if (( dx < TOL_POS && dy < TOL_POS && dw <= size_tol_w && dh <= size_tol_h )); then
                exit 0
            fi
        fi
    fi
    sleep 0.05
done

echo "  w1 was not displaced to the left half" >&2
echo "  expected: $lx $ly $lw $lh" >&2
echo "  actual:   ${last:-<unreadable>}" >&2
exit 1
