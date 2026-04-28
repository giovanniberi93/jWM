#!/usr/bin/env bash
# A window placed near (but not exactly at) a half slot should snap to exact-half
# on activation. Exercises WindowTiler.swift:87 (matchHalfPosition) end-to-end:
# guardActivation → displaceIfHalf → matchHalfPosition → snap.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

victim_launch com.apple.Terminal
term_pid=$(victim_get_pid com.apple.Terminal)

# Park TextEdit on top so the next Terminal activation actually fires
# NSWorkspace.didActivateApplicationNotification.
victim_launch com.apple.TextEdit
victim_activate com.apple.TextEdit

# Place Terminal near the left half — within both tolerances of matchHalfPosition
# (20px on origin, 15% on size). Big enough offset that "no snap" would visibly
# fail the post-condition assertion below.
read -r lx ly lw lh <<<"$(expected_rect left)"
near_x=$((lx + 12))
near_y=$((ly + 8))
near_w=$((lw * 108 / 100))
near_h=$((lh * 92 / 100))
victim_set_rect "$term_pid" "$near_x" "$near_y" "$near_w" "$near_h"

# Fire activation → jwm's guardActivation polls displaceIfHalf, which calls
# matchHalfPosition, which returns .left, which triggers the snap.
victim_activate com.apple.Terminal

# Tight tolerance: the snap must produce the EXACT left rect, not just the
# original near-half rect (which would already pass default tolerance).
TOL_POS=5 TOL_SIZE_PCT=3 assert_rect_approx "$term_pid" "$lx" "$ly" "$lw" "$lh"
