#!/usr/bin/env bash
# cmd+1 + cmd-release (no position key) → focus configured app, no window move.
# Exercises the pendingAppKey path in HotkeyManager.swift:99-103.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# Make sure Terminal exists with a known rect, but is NOT frontmost
victim_launch com.apple.Terminal
term_pid=$(victim_get_pid com.apple.Terminal)
victim_set_rect "$term_pid" 250 250 600 400
sleep 0.1

# Activate something else so we can detect the focus change
victim_launch com.apple.TextEdit
victim_activate com.apple.TextEdit

# Snapshot Terminal's rect before chord
before=$(victim_get_rect "$term_pid")
read -r bx by bw bh <<<"$before"

# Trigger chord: cmd+1 release (Terminal = app1)
post_chord_focus_only 1
sleep 0.15

# Terminal must now be frontmost
assert_frontmost com.apple.Terminal || exit 1

# Terminal's rect must NOT have moved
assert_rect_stable "$term_pid" "$bx" "$by" "$bw" "$bh"
