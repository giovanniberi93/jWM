#!/usr/bin/env bash
# Core slot displacement rule: a full-screen app gets shrunk to the opposite
# half when another app is tiled to a half on the same display.
# (CLAUDE.md "two-slot mental model" + WindowTiler.swift:59-67)
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

# 1. stub1 full-screen
victim_launch com.giovanniberi93.janzowm.stub1
victim_activate com.giovanniberi93.janzowm.stub1
stub1_pid=$(victim_get_pid com.giovanniberi93.janzowm.stub1)
victim_set_rect "$stub1_pid" 300 300 500 350
sleep 0.1
post_tile_current j
read -r fx fy fw fh <<<"$(expected_rect full)"
assert_rect_approx "$stub1_pid" "$fx" "$fy" "$fw" "$fh" || {
    echo "  setup failed: stub1 did not go full" >&2
    exit 1
}

# 2. stub2 → left half. stub1 should auto-shrink to right.
victim_launch com.giovanniberi93.janzowm.stub2
victim_activate com.giovanniberi93.janzowm.stub2
stub2_pid=$(victim_get_pid com.giovanniberi93.janzowm.stub2)
victim_set_rect "$stub2_pid" 400 400 500 350
sleep 0.1
post_tile_current h

# Verify stub2 left
read -r lx ly lw lh <<<"$(expected_rect left)"
assert_rect_approx "$stub2_pid" "$lx" "$ly" "$lw" "$lh" || {
    echo "  stub2 did not tile left" >&2
    exit 1
}

# Verify stub1 displaced to right
read -r rx ry rw rh <<<"$(expected_rect right)"
assert_rect_approx "$stub1_pid" "$rx" "$ry" "$rw" "$rh"
