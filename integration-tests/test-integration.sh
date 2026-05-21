#!/usr/bin/env bash
# Integration test driver. Boots the debug build of janzowm with test-only app
# bindings via NSArgumentDomain (does not touch persistent UserDefaults), then
# runs each integration-tests/test-cases/*.sh against it.
#
# Requires: Accessibility granted to build/test-bundle/Build/Products/Debug/janzowm-debug.app and to
# /System/Applications/Utilities/Terminal.app (for osascript via System Events).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
source "$ROOT/integration-tests/test-lib.sh"

JANZOWM_PRODUCT_NAME="janzowm-debug"
JANZOWM_BIN="$ROOT/build/test-bundle/Build/Products/Debug/${JANZOWM_PRODUCT_NAME}.app/Contents/MacOS/${JANZOWM_PRODUCT_NAME}"
JANZOWM_LOG_DIR="$ROOT/build/test"
JANZOWM_LOG="$JANZOWM_LOG_DIR/janzowm.log"

mkdir -p "$JANZOWM_LOG_DIR"

if [ ! -x "$JANZOWM_BIN" ]; then
    red "ERROR: "
    echo "Debug binary not found at $JANZOWM_BIN"
    echo "Run: make build-test"
    exit 1
fi

sc=$(screen_count)
cyan "Detected $sc screen(s)."
echo
if [ "$sc" -lt 2 ]; then
    yellow "NOTE: "
    echo "Multi-screen tests under test-cases/multi-screen/ will report SKIP."
fi

COUNTDOWN_SRC="$ROOT/integration-tests/countdown-overlay.swift"
COUNTDOWN_BIN="$ROOT/build/test/countdown-overlay"
if [ ! -x "$COUNTDOWN_BIN" ] || [ "$COUNTDOWN_SRC" -nt "$COUNTDOWN_BIN" ]; then
    mkdir -p "$(dirname "$COUNTDOWN_BIN")"
    swiftc -O "$COUNTDOWN_SRC" -o "$COUNTDOWN_BIN"
fi

notify() {
    osascript -e "display notification \"$1\" with title \"janzoWM integration tests\"" >/dev/null 2>&1 || true
}

"$COUNTDOWN_BIN" 3

STUB1_BUNDLE="com.giovanniberi93.janzowm.stub1"
STUB2_BUNDLE="com.giovanniberi93.janzowm.stub2"
STUB3_BUNDLE="com.giovanniberi93.janzowm.stub3"
PROB_BUNDLE="com.giovanniberi93.janzowm.problematic"
OVERLAY_BUNDLE="com.giovanniberi93.janzowm.overlay"
export PROB_BUNDLE

cleanup() {
    echo
    yellow "Cleaning up..."
    pkill -x "$JANZOWM_PRODUCT_NAME" 2>/dev/null || true
    osascript -e "tell application id \"$STUB1_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$STUB2_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$STUB3_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$PROB_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$OVERLAY_BUNDLE\" to quit" 2>/dev/null || true
    defaults delete com.giovanniberi93.janzowm.debug useArrowKeys 2>/dev/null || true
    notify "Done — pass=${PASS:-?} fail=${FAIL:-?} skip=${SKIP:-?}"
}
trap cleanup EXIT

# Pin letter-mode for the suite; 11_arrow_keys.sh flips to arrows then restores.
defaults write com.giovanniberi93.janzowm.debug useArrowKeys -bool NO

# Stop any existing janzowm — only one instance can run (janzowmApp.swift:92)
pkill -x "$JANZOWM_PRODUCT_NAME" 2>/dev/null || true
sleep 0.15

cyan "Booting janzowm with test bindings (Stub1=app1, Stub2=app2, Stub3=app3, Problematic=app4)..."
echo
"$JANZOWM_BIN" \
    -app1_bundleID "$STUB1_BUNDLE" \
    -app2_bundleID "$STUB2_BUNDLE" \
    -app3_bundleID "$STUB3_BUNDLE" \
    -app4_bundleID "$PROB_BUNDLE" \
    -hasCompletedFirstRunTutorial YES \
    -integrationTestMode YES \
    >"$JANZOWM_LOG" 2>&1 &
JANZOWM_PID=$!

deadline=$(($(date +%s) + 5))
while (( $(date +%s) < deadline )); do
    if grep -q "Event tap started successfully" "$JANZOWM_LOG" 2>/dev/null; then
        break
    fi
    if ! kill -0 "$JANZOWM_PID" 2>/dev/null; then
        red "ERROR: "
        echo "janzowm exited before its event tap came up. Log:"
        cat "$JANZOWM_LOG"
        exit 1
    fi
    sleep 0.1
done

if ! grep -q "Event tap started successfully" "$JANZOWM_LOG"; then
    red "ERROR: "
    echo "janzowm did not start its event tap within 5s."
    echo
    echo "Most likely cause: Accessibility permission not granted to the dev/debug build."
    echo "Look for the row labeled 'janzoWM Debug' (bundle id com.giovanniberi93.janzowm.debug),"
    echo "NOT 'janzoWM' — that's the /Applications install."
    echo
    echo "Open System Settings → Privacy & Security → Accessibility:"
    echo "  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
    echo
    echo "If AX was previously granted but now silently fails (cdhash churn after rebuild):"
    echo "  make reset-accessibility-permissions   # then re-grant 'janzoWM Debug'"
    echo
    echo "Recent janzowm log:"
    tail -20 "$JANZOWM_LOG"
    exit 1
fi
green "OK: "
echo "janzowm event tap up (pid $JANZOWM_PID, log $JANZOWM_LOG)"

# --- Run test cases -----------------------------------------------------------

PASS=0
FAIL=0
SKIP=0
FAILED_TESTS=()
SKIPPED_TESTS=()

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
    test_files=(
        "$ROOT"/integration-tests/test-cases/*.sh
        "$ROOT"/integration-tests/test-cases/multi-screen/*.sh
    )
fi
for tc in "${test_files[@]}"; do
    # The abort hotkey (ctrl+cmd+S, gated on integrationTestMode) terminates
    # janzowm cleanly so a wedged test can be killed without leaking stubs. If
    # janzowm is gone for any reason — abort, crash, or external pkill — stop
    # the suite instead of running a no-op test against a dead event tap.
    if ! kill -0 "$JANZOWM_PID" 2>/dev/null; then
        echo
        red "ABORTED: "
        echo "janzowm (pid $JANZOWM_PID) is no longer running — stopping suite."
        break
    fi
    name=$(basename "$tc" .sh)
    echo
    cyan "▶ $name"
    echo
    # Mark janzowm log position so we can extract just this test's slice on failure
    janzowm_log_offset=$(wc -c <"$JANZOWM_LOG" 2>/dev/null | tr -d ' ' || echo 0)
    rc=0
    ROOT="$ROOT" bash "$tc" || rc=$?
    if [ "$rc" -eq 0 ]; then
        green "  PASS"
        echo
        PASS=$((PASS + 1))
    elif [ "$rc" -eq 77 ]; then
        yellow "  SKIP"
        echo
        SKIP=$((SKIP + 1))
        SKIPPED_TESTS+=("$name")
    else
        red "  FAIL"
        echo
        yellow "  --- janzowm log during this test ---"
        local_slice=$(tail -c "+$((janzowm_log_offset + 1))" "$JANZOWM_LOG" 2>/dev/null)
        if [ -n "$local_slice" ]; then
            printf '%s\n' "$local_slice" | sed 's/^/    /'
        else
            echo "    (no janzowm output)"
        fi
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$name")
    fi
    # Reset victim state between tests: quit stubs so the next test's
    # victim_launch starts from a known one-window cold state.
    osascript -e "tell application id \"$STUB1_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$STUB2_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$STUB3_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$PROB_BUNDLE\" to quit" 2>/dev/null || true
    osascript -e "tell application id \"$OVERLAY_BUNDLE\" to quit" 2>/dev/null || true
    sleep 0.2
    # Then clear janzowm's fullscreen slot map. When focus reverts to the
    # developer's terminal between cases, onFocusChanged's defocus-promote
    # may record any of its windows that happens to sit at the fullscreen
    # rect — phantom entries that would otherwise become displacement
    # candidates in the next test. The SIGUSR1 handler in
    # AppDelegate.installSlotResetSignalHandler clears them.
    kill -USR1 "$JANZOWM_PID" 2>/dev/null || true
done

echo
echo "─────────────────────────────"
green "PASSED: $PASS"
if [ "$SKIP" -gt 0 ]; then
    echo
    yellow "SKIPPED: $SKIP"
    echo
    for t in "${SKIPPED_TESTS[@]}"; do echo "  - $t"; done
fi
if [ "$FAIL" -gt 0 ]; then
    echo
    red "FAILED: $FAIL"
    echo
    for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
    exit 1
fi
