#!/usr/bin/env bash
# cmd+2 + cmd+H → focus stub2 AND tile it left. Full chord path through
# HotkeyManager.swift:117-121 → onFocusTile → WindowTiler.tile.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# Pre-launch stub2 so the chord finds an existing window (not a fresh launch)
victim_launch com.giovanniberi93.jwm.stub2
stub2_pid=$(victim_get_pid com.giovanniberi93.jwm.stub2)
victim_set_rect "$stub2_pid" 400 400 500 350
sleep 0.1

# Activate stub1 so stub2 is NOT currently frontmost
victim_launch com.giovanniberi93.jwm.stub1
victim_activate com.giovanniberi93.jwm.stub1

# Trigger: cmd+2 + cmd+H
post_chord_focus_tile 2 h

# stub2 should now be frontmost
assert_frontmost com.giovanniberi93.jwm.stub2 || exit 1

# … and tiled left
read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$stub2_pid" "$lx" "$ly" "$lw" "$lh"
