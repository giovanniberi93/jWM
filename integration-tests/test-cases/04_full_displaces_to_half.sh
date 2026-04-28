#!/usr/bin/env bash
# Core slot displacement rule: a full-screen app gets shrunk to the opposite
# half when another app is tiled to a half on the same display.
# (CLAUDE.md "two-slot mental model" + WindowTiler.swift:59-67)
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# 1. Terminal full-screen
victim_launch com.apple.Terminal
victim_activate com.apple.Terminal
term_pid=$(victim_get_pid com.apple.Terminal)
victim_set_rect "$term_pid" 300 300 500 350
sleep 0.1
post_tile_current j
read -r fx fy fw fh <<<"$(expected_rect full)"
assert_rect_approx "$term_pid" "$fx" "$fy" "$fw" "$fh" || {
    echo "  setup failed: Terminal did not go full" >&2
    exit 1
}

# 2. TextEdit → left half. Terminal should auto-shrink to right.
victim_launch com.apple.TextEdit
victim_activate com.apple.TextEdit
te_pid=$(victim_get_pid com.apple.TextEdit)
victim_set_rect "$te_pid" 400 400 500 350
sleep 0.1
post_tile_current h

# Verify TextEdit left
read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$te_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  TextEdit did not tile left" >&2
    exit 1
}

# Verify Terminal displaced to right
read -r rx ry rw rh <<<"$(expected_rect right)"
assert_rect_approx "$term_pid" "$rx" "$ry" "$rw" "$rh"
