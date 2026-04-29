#!/usr/bin/env bash
# A window resized to near-fullscreen WITHOUT being tiled via jwm should still
# get tracked in the fullscreen slot — but only if guardActivation's
# defocus-time promoteIfFullScreen runs (WindowTiler.swift:154-158).
#
# Without that defocus path, the next half-tile would have nothing to displace
# and the orphaned near-full window would just sit there.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.giovanniberi93.jwm.stub1
victim_launch com.giovanniberi93.jwm.stub2
stub1_pid=$(victim_get_pid com.giovanniberi93.jwm.stub1)
stub2_pid=$(victim_get_pid com.giovanniberi93.jwm.stub2)

victim_activate com.giovanniberi93.jwm.stub1
# Wait for stub1's post-activation poll to expire (WindowTiler.swift:163-174
# runs displaceIfHalf/promoteIfFullScreen for 0.5s). After this, the ONLY path
# that can promote stub1 is the defocus check on the next activation —
# which is exactly what this test exercises.
sleep 0.6

# Resize stub1 to near-fullscreen — within approxEquals' 20px tolerance.
# Fullscreen is the maximum within visibleFrame, so off-by-X means smaller.
read -r fx fy fw fh <<<"$(expected_rect full)"
near_full_w=$((fw - 15))
near_full_h=$((fh - 12))
victim_set_rect "$stub1_pid" "$fx" "$fy" "$near_full_w" "$near_full_h"

# Activate stub2. jwm's guardActivation(stub2) runs promoteIfFullScreen
# on prev=stub1 (the defocus path). stub1 is near-full → added to
# slots.fullScreen.
victim_activate com.giovanniberi93.jwm.stub2

# Tile stub2 to the left half. If the defocus-promote actually ran, jwm
# finds stub1 in the fullscreen slot via findDisplacementCandidate and
# shrinks it to the right half. If it didn't run, stub1 stays at near-full.
victim_set_rect "$stub2_pid" 400 400 500 350
sleep 0.1
post_tile_current h

read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$stub2_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  stub2 did not tile left" >&2
    exit 1
}

# stub1 displaced to right — only happens because defocus-promote ran.
read -r rx ry rw rh <<<"$(expected_rect right)"
assert_rect_approx "$stub1_pid" "$rx" "$ry" "$rw" "$rh"
