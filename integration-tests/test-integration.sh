#!/usr/bin/env bash
# Integration test driver. Boots the debug build of jwm with test-only app
# bindings via NSArgumentDomain (does not touch persistent UserDefaults), then
# runs each integration-tests/test-cases/*.sh against it.
#
# Requires: Accessibility granted to build/test-bundle/Build/Products/Debug/jwm-debug.app and to
# /System/Applications/Utilities/Terminal.app (for osascript via System Events).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
source "$ROOT/integration-tests/test-lib.sh"

JWM_PRODUCT_NAME="jwm-debug"
JWM_BIN="$ROOT/build/test-bundle/Build/Products/Debug/${JWM_PRODUCT_NAME}.app/Contents/MacOS/${JWM_PRODUCT_NAME}"
JWM_LOG_DIR="$ROOT/build/test"
JWM_LOG="$JWM_LOG_DIR/jwm.log"

mkdir -p "$JWM_LOG_DIR"

if [ ! -x "$JWM_BIN" ]; then
    red "ERROR: "
    echo "Debug binary not found at $JWM_BIN"
    echo "Run: make build-test"
    exit 1
fi

sc=$(screen_count)
if [ "$sc" -gt 1 ]; then
    yellow "WARNING: "
    echo "$sc screens detected — v0 only covers single-screen scenarios."
    echo "Multi-screen behavior is NOT being verified by this run."
fi

# Disable auto-restore for victim apps so each test run starts clean
defaults write -app TextEdit NSQuitAlwaysKeepsWindows -bool false 2>/dev/null || true
defaults write -app Terminal NSQuitAlwaysKeepsWindows -bool false 2>/dev/null || true

cleanup() {
    echo
    yellow "Cleaning up..."
    pkill -x "$JWM_PRODUCT_NAME" 2>/dev/null || true
    osascript -e 'tell application "Terminal" to close every window saving no' 2>/dev/null || true
    osascript -e 'tell application "TextEdit" to close every document saving no' 2>/dev/null || true
    osascript -e 'tell application "Terminal" to quit'  2>/dev/null || true
    osascript -e 'tell application "TextEdit" to quit' 2>/dev/null || true
}
trap cleanup EXIT

# Stop any existing jwm — only one instance can run (jwmApp.swift:92)
pkill -x "$JWM_PRODUCT_NAME" 2>/dev/null || true
sleep 0.15

cyan "Booting jwm with test bindings (Terminal=app1, TextEdit=app2, Notes=app3)..."
echo
"$JWM_BIN" \
    -app1_bundleID com.apple.Terminal \
    -app2_bundleID com.apple.TextEdit \
    -app3_bundleID com.apple.Notes \
    >"$JWM_LOG" 2>&1 &
JWM_PID=$!

deadline=$(($(date +%s) + 5))
while (( $(date +%s) < deadline )); do
    if grep -q "Event tap started successfully" "$JWM_LOG" 2>/dev/null; then
        break
    fi
    if ! kill -0 "$JWM_PID" 2>/dev/null; then
        red "ERROR: "
        echo "jwm exited before its event tap came up. Log:"
        cat "$JWM_LOG"
        exit 1
    fi
    sleep 0.1
done

if ! grep -q "Event tap started successfully" "$JWM_LOG"; then
    red "ERROR: "
    echo "jwm did not start its event tap within 5s."
    echo
    echo "Most likely cause: Accessibility permission not granted to the dev/debug build."
    echo "Look for the row labeled 'jWM Debug' (bundle id com.giovanniberi93.jwm.debug),"
    echo "NOT 'jWM' — that's the /Applications install."
    echo
    echo "Open System Settings → Privacy & Security → Accessibility:"
    echo "  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
    echo
    echo "If AX was previously granted but now silently fails (cdhash churn after rebuild):"
    echo "  make reset-accessibility-permissions   # then re-grant 'jWM Debug'"
    echo
    echo "Recent jwm log:"
    tail -20 "$JWM_LOG"
    exit 1
fi
green "OK: "
echo "jwm event tap up (pid $JWM_PID, log $JWM_LOG)"

# --- Run test cases -----------------------------------------------------------

PASS=0
FAIL=0
FAILED_TESTS=()

shopt -s nullglob
for tc in "$ROOT"/integration-tests/test-cases/*.sh; do
    name=$(basename "$tc" .sh)
    echo
    cyan "▶ $name"
    # Mark jwm log position so we can extract just this test's slice on failure
    jwm_log_offset=$(wc -c <"$JWM_LOG" 2>/dev/null | tr -d ' ' || echo 0)
    if ROOT="$ROOT" bash "$tc"; then
        green "  PASS"
        echo
        PASS=$((PASS + 1))
    else
        red "  FAIL"
        echo
        yellow "  --- jwm log during this test ---"
        local_slice=$(tail -c "+$((jwm_log_offset + 1))" "$JWM_LOG" 2>/dev/null)
        if [ -n "$local_slice" ]; then
            printf '%s\n' "$local_slice" | sed 's/^/    /'
        else
            echo "    (no jwm output)"
        fi
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$name")
    fi
    # Reset victim state between tests
    osascript -e 'tell application "Terminal" to close every window saving no' 2>/dev/null || true
    osascript -e 'tell application "TextEdit" to close every document saving no' 2>/dev/null || true
    sleep 0.1
done

echo
echo "─────────────────────────────"
green "PASSED: $PASS"
if [ "$FAIL" -gt 0 ]; then
    echo
    red "FAILED: $FAIL"
    echo
    for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
    exit 1
fi
