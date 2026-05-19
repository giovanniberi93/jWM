#!/usr/bin/env bash
# A window placed near (but not exactly at) a half slot should snap to exact-half
# on activation. Exercises WindowTiler.matchHalfPosition end-to-end:
# onFocusChanged → snapFocusedToExactHalf → matchHalfPosition → snap.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.giovanniberi93.jwm.stub1
stub1_pid=$(victim_get_pid com.giovanniberi93.jwm.stub1)

# Park stub2 on top so the next stub1 activation actually fires
# NSWorkspace.didActivateApplicationNotification.
victim_launch com.giovanniberi93.jwm.stub2
victim_activate com.giovanniberi93.jwm.stub2

# Place stub1 near the left half — within both tolerances of matchHalfPosition
# (20px on origin, 15% on size). Big enough offset that "no snap" would visibly
# fail the post-condition assertion below.
read -r lx ly lw lh <<<"$(expected_rect left)"
near_x=$((lx + 12))
near_y=$((ly + 8))
near_w=$((lw * 108 / 100))
near_h=$((lh * 92 / 100))
victim_set_rect "$stub1_pid" "$near_x" "$near_y" "$near_w" "$near_h"

# Fire activation → jwm's onFocusChanged polls snapFocusedToExactHalf, which
# calls matchHalfPosition, which returns .left, which triggers the snap.
victim_activate com.giovanniberi93.jwm.stub1

# Tight tolerance: the snap must produce the EXACT left rect, not just the
# original near-half rect (which would already pass default tolerance).
TOL_POS=5 TOL_SIZE_PCT=3 assert_rect_approx "$stub1_pid" "$lx" "$ly" "$lw" "$lh"
