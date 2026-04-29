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
cyan "Detected $sc screen(s)."
echo
if [ "$sc" -lt 2 ]; then
    yellow "NOTE: "
    echo "Only single-screen tests will run. Multi-screen tests under test-cases/multi-screen/ are skipped."
fi

STUB1_BUNDLE="com.giovanniberi93.jwm.stub1"
STUB2_BUNDLE="com.giovanniberi93.jwm.stub2"
STUB3_BUNDLE="com.giovanniberi93.jwm.stub3"

cleanup() {
    echo
    yellow "Cleaning up..."
    pkill -x "$JWM_PRODUCT_NAME" 2>/dev/null || true
    osascript -e "tell application id \"$STUB1_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$STUB2_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$STUB3_BUNDLE\" to quit" 2>/dev/null || true
}
trap cleanup EXIT

# Stop any existing jwm — only one instance can run (jwmApp.swift:92)
pkill -x "$JWM_PRODUCT_NAME" 2>/dev/null || true
sleep 0.15

cyan "Booting jwm with test bindings (Stub1=app1, Stub2=app2, Stub3=app3)..."
echo
"$JWM_BIN" \
    -app1_bundleID "$STUB1_BUNDLE" \
    -app2_bundleID "$STUB2_BUNDLE" \
    -app3_bundleID "$STUB3_BUNDLE" \
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
TEST_FILTER="${1:-}"
if [ -n "$TEST_FILTER" ]; then
    # Filter searches both single- and multi-screen dirs. require_screens at
    # the top of multi-screen tests turns a screen-count mismatch into a clean
    # failure rather than a silent skip.
    test_files=(
        "$ROOT"/integration-tests/test-cases/${TEST_FILTER}_*.sh
        "$ROOT"/integration-tests/test-cases/multi-screen/${TEST_FILTER}_*.sh
    )
    if [ ${#test_files[@]} -eq 0 ]; then
        red "ERROR: "
        echo "no test matches '$TEST_FILTER' in integration-tests/test-cases/"
        exit 1
    fi
else
    test_files=( "$ROOT"/integration-tests/test-cases/*.sh )
    if [ "$sc" -ge 2 ]; then
        test_files+=( "$ROOT"/integration-tests/test-cases/multi-screen/*.sh )
    fi
fi
for tc in "${test_files[@]}"; do
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
    # Reset victim state between tests: quit stubs so the next test's
    # victim_launch starts from a known one-window cold state.
    osascript -e "tell application id \"$STUB1_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$STUB2_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$STUB3_BUNDLE\" to quit" 2>/dev/null || true
    sleep 0.2
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
