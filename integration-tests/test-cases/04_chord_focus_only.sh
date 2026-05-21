#!/usr/bin/env bash
# cmd+1 + cmd-release (no position key) → focus configured app, no window move.
# Exercises the pendingAppKey path in HotkeyManager.swift:99-103.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# Make sure stub1 exists with a known rect, but is NOT frontmost
victim_launch com.giovanniberi93.janzowm.stub1
stub1_pid=$(victim_get_pid com.giovanniberi93.janzowm.stub1)
victim_set_rect "$stub1_pid" 250 250 600 400
sleep 0.1

# Activate something else so we can detect the focus change
victim_launch com.giovanniberi93.janzowm.stub2
victim_activate com.giovanniberi93.janzowm.stub2

# Snapshot stub1's rect before chord
before=$(victim_get_rect "$stub1_pid")
read -r bx by bw bh <<<"$before"

# Trigger chord: cmd+1 release (stub1 = app1)
post_chord_focus_only 1
sleep 0.15

# stub1 must now be frontmost
assert_frontmost com.giovanniberi93.janzowm.stub1 || exit 1

# stub1's rect must NOT have moved
assert_rect_stable "$stub1_pid" "$bx" "$by" "$bw" "$bh"
