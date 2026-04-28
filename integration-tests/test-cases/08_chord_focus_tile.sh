#!/usr/bin/env bash
# cmd+2 + cmd+H → focus TextEdit AND tile it left. Full chord path through
# HotkeyManager.swift:117-121 → onFocusTile → WindowTiler.tile.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# Pre-launch TextEdit so the chord finds an existing window (not a fresh launch)
victim_launch com.apple.TextEdit
te_pid=$(victim_get_pid com.apple.TextEdit)
victim_set_rect "$te_pid" 400 400 500 350
sleep 0.1

# Activate Terminal so TextEdit is NOT currently frontmost
victim_launch com.apple.Terminal
victim_activate com.apple.Terminal

# Trigger: cmd+2 + cmd+H
post_chord_focus_tile 2 h

# TextEdit should now be frontmost
assert_frontmost com.apple.TextEdit || exit 1

# … and tiled left
read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$te_pid" "$lx" "$ly" "$lw" "$lh"
