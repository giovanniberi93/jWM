#!/usr/bin/env bash
# ctrl+cmd+k must bounce a fullscreen window between screens regardless of
# which physical display is the primary. Runs the 3-press bounce test once
# with the current arrangement, then swaps primary via displayplacer and
# runs it again. Restores the original arrangement on exit.
#
# Catches the class of bugs where coordinate math depends on which NSScreen
# is screens[0] (e.g. menu-bar inset applied to the wrong screen, stale
# visibleFrame in the long-running jwm process after a primary swap).
#
# Requires: displayplacer (`brew install displayplacer`). Without it, the
# test exits with a clear setup error.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

require_screens 2

if ! command -v displayplacer >/dev/null 2>&1; then
    echo "  requires displayplacer — install with: brew install displayplacer" >&2
    exit 1
fi

# --- Snapshot current arrangement so we can restore on exit -------------------
# `displayplacer list` ends with a "displayplacer ..." command that recreates
# the current state. Grab the last such line. Each quoted "..." block is one
# screen.
SNAPSHOT_CMD=$(displayplacer list 2>/dev/null | grep '^displayplacer ' | tail -n1)
if [ -z "$SNAPSHOT_CMD" ]; then
    echo "  could not parse displayplacer list output (no recreate command found)" >&2
    exit 1
fi

# Extract quoted screen blocks. macOS bash is 3.2 → no mapfile; use perl + sed.
extract_block() {
    perl -ne 'print "$1\n" while /"([^"]+)"/g' <<<"$SNAPSHOT_CMD" | sed -n "${1}p"
}
SCREEN_A=$(extract_block 1)
SCREEN_B=$(extract_block 2)
SCREEN_C=$(extract_block 3)
if [ -z "$SCREEN_A" ] || [ -z "$SCREEN_B" ] || [ -n "$SCREEN_C" ]; then
    echo "  expected exactly 2 screen blocks in displayplacer output" >&2
    echo "  got: $SNAPSHOT_CMD" >&2
    exit 1
fi

restore_arrangement() {
    displayplacer "$SCREEN_A" "$SCREEN_B" >/dev/null 2>&1 || true
    sleep 1
}
trap restore_arrangement EXIT

# Build the swapped command: swap the two origin:(...) values between blocks.
# The screen at origin:(0,0) is the primary in macOS — moving (0,0) to the
# other screen makes it the new primary.
ORIGIN_A=$(perl -ne 'print $1 if /origin:\(([^)]+)\)/' <<<"$SCREEN_A")
ORIGIN_B=$(perl -ne 'print $1 if /origin:\(([^)]+)\)/' <<<"$SCREEN_B")
if [ -z "$ORIGIN_A" ] || [ -z "$ORIGIN_B" ]; then
    echo "  could not parse origins from displayplacer blocks" >&2
    exit 1
fi
# Two-step substitution via placeholder so we don't double-replace.
SCREEN_A_SWAP=$(sed "s|origin:($ORIGIN_A)|origin:(__P__)|; s|origin:(__P__)|origin:($ORIGIN_B)|" <<<"$SCREEN_A")
SCREEN_B_SWAP=$(sed "s|origin:($ORIGIN_B)|origin:(__P__)|; s|origin:(__P__)|origin:($ORIGIN_A)|" <<<"$SCREEN_B")

# --- Per-config bounce check --------------------------------------------------
# 3 presses of ctrl+cmd+k from a fullscreen window. Each press must move it
# to the other screen and have it land fullscreen there. Mirrors the inner
# loop of test 10.
run_three_moves() {
    local label="$1"
    local pid="$2"

    # Place fullscreen on whatever is currently screen 0 in the live layout.
    local fx fy fw fh
    read -r fx fy fw fh <<<"$(expected_rect_on 0 full)"
    victim_set_rect "$pid" "$fx" "$fy" "$fw" "$fh"
    sleep 0.2
    post_tile_current j  # promote via tile-current so jwm tracks it as full
    assert_rect_exact "$pid" "$fx" "$fy" "$fw" "$fh" || {
        echo "  $label setup: stub2 not fullscreen on screen 0" >&2
        return 1
    }

    local prev_screen
    prev_screen=$(screen_of_rect "$fx" "$fy" "$fw" "$fh")

    local i
    for i in 1 2 3; do
        post_tile_current k
        sleep 0.3
        local cur_rect cx cy cw ch cur_screen
        cur_rect=$(victim_get_rect "$pid")
        read -r cx cy cw ch <<<"$cur_rect"
        cur_screen=$(screen_of_rect "$cx" "$cy" "$cw" "$ch")
        if [ "$cur_screen" -lt 0 ]; then
            echo "  $label press $i: rect $cur_rect on no known screen" >&2
            return 1
        fi
        if [ "$cur_screen" = "$prev_screen" ]; then
            echo "  $label press $i: window stayed on screen $cur_screen" >&2
            echo "  rect: $cur_rect" >&2
            return 1
        fi
        local ex ey ew eh
        read -r ex ey ew eh <<<"$(expected_rect_on "$cur_screen" full)"
        assert_rect_exact "$pid" "$ex" "$ey" "$ew" "$eh" || {
            echo "  $label press $i: not fullscreen on destination screen $cur_screen" >&2
            return 1
        }
        prev_screen=$cur_screen
    done
}

# --- Run -----------------------------------------------------------------------
victim_launch com.giovanniberi93.jwm.stub2
victim_activate com.giovanniberi93.jwm.stub2
stub2_pid=$(victim_get_pid com.giovanniberi93.jwm.stub2)

run_three_moves "config A (original primary)" "$stub2_pid"

echo "  swapping primary via displayplacer..." >&2
displayplacer "$SCREEN_A_SWAP" "$SCREEN_B_SWAP" >/dev/null
# Display reconfig is async. Give AppKit and jwm time to refresh
# NSScreen state before the next chord.
sleep 2
# Stub2 may have been knocked off-frontmost by the display reconfig.
victim_activate com.giovanniberi93.jwm.stub2

run_three_moves "config B (swapped primary)" "$stub2_pid"
