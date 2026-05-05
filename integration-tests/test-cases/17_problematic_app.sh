#!/usr/bin/env bash
# Three-phase test exercising the "problematic app" defenses. Each phase
# launches the same stub binary with a different flag set so a failure isolates
# which defense regressed:
#
#   Phase 1 — #3: focusOrLaunch's no-window branch via onFocusTile, which
#                 routes to launchAndWaitForWindow → openApplication →
#                 applicationShouldHandleReopen.
#   Phase 2 — #2: launchAndWaitForWindow's poll loop when the reopen-spawned
#                 window appears 200ms late.
#   Phase 3 — #1: WindowAX.guardPosition retiling after the stub reverts
#                 (drift-back) once.
#
# All three use the same chord (cmd+4 + J → focus-tile full) so phases differ
# only in stub configuration, not in jwm-side machinery.
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

PROB_BUNDLE="${PROB_BUNDLE:-com.giovanniberi93.jwm.problematic}"

# --- Helpers -----------------------------------------------------------------

prob_running() {
    osascript -e "tell application \"System Events\" to exists (first application process whose bundle identifier is \"$PROB_BUNDLE\")" 2>/dev/null || echo "false"
}

prob_window_count() {
    osascript -e "tell application \"System Events\" to count of windows of (first application process whose bundle identifier is \"$PROB_BUNDLE\")" 2>/dev/null || echo 0
}

# Quit any prior instance, wait for full termination, then cold-launch with
# the given flags via `open -b -n --args`. Returns once the process is visible
# to System Events. Doesn't wait for a window — phases that pass --windows 0
# rely on there being none.
launch_problematic() {
    osascript -e "tell application id \"$PROB_BUNDLE\" to quit" 2>/dev/null || true
    local deadline=$(($(date +%s) + 3))
    while (( $(date +%s) < deadline )); do
        [ "$(prob_running)" = "true" ] || break
        sleep 0.1
    done

    open -b "$PROB_BUNDLE" -n --args "$@" >/dev/null 2>&1 || {
        echo "  failed to launch $PROB_BUNDLE" >&2
        return 1
    }

    deadline=$(($(date +%s) + 5))
    while (( $(date +%s) < deadline )); do
        [ "$(prob_running)" = "true" ] && return 0
        sleep 0.1
    done
    echo "  problematic stub process never appeared" >&2
    return 1
}

# Poll up to 3s for the problematic stub's window to appear after a chord.
# Echoes the pid on success; exits the test with the given message on failure.
wait_for_window_or_fail() {
    local fail_msg="$1"
    local deadline=$(($(date +%s) + 3))
    local pid=""
    while (( $(date +%s) < deadline )); do
        if [[ "$(prob_window_count)" =~ ^[1-9] ]]; then
            pid=$(victim_get_pid "$PROB_BUNDLE" 2>/dev/null || echo "")
            if [ -n "$pid" ]; then
                echo "$pid"
                return 0
            fi
        fi
        sleep 0.1
    done
    echo "$fail_msg" >&2
    exit 1
}

# Park stub1 in front so the chord routes through onFocusTile's "not running
# OR no windows" branch (the one that wraps in guardPosition).
park_other_app_in_front() {
    victim_launch com.giovanniberi93.jwm.stub1
    victim_activate com.giovanniberi93.jwm.stub1
}

assert_full_or_fail() {
    local pid="$1" tag="$2"
    local fx fy fw fh
    read -r fx fy fw fh <<<"$(expected_rect full)"
    if ! assert_rect_approx "$pid" "$fx" "$fy" "$fw" "$fh"; then
        echo "  $tag: window did not reach full-screen" >&2
        exit 1
    fi
}

# --- Phase 1: #3 (no-window-on-activate) -------------------------------------
# No spawn delay, no drift. If this fails, the openApplication/reopen path is
# broken: a windowless running app didn't get its window (re)spawned.
echo "  phase 1: #3 no-window-on-activate"
launch_problematic --windows 0
[[ "$(prob_window_count)" == "0" ]] || { echo "  phase 1: expected 0 initial windows" >&2; exit 1; }
park_other_app_in_front
post_chord_focus_tile 4 j
pid=$(wait_for_window_or_fail "  phase 1 (#3): window never appeared after chord — focusOrLaunch's no-window branch may have regressed")
assert_full_or_fail "$pid" "phase 1 (#3)"

# --- Phase 2: #2 (delayed reopen-spawned window) -----------------------------
# Same chord, but the reopen handler defers spawnWindow by 200ms. If this
# fails while phase 1 passed, launchAndWaitForWindow's poll loop is the suspect
# (timed out, gave up, or completed before the window existed).
echo "  phase 2: #2 delayed spawn (200ms)"
launch_problematic --windows 0 --spawn-delay-ms 200
[[ "$(prob_window_count)" == "0" ]] || { echo "  phase 2: expected 0 initial windows" >&2; exit 1; }
park_other_app_in_front
post_chord_focus_tile 4 j
pid=$(wait_for_window_or_fail "  phase 2 (#2): window never appeared — launchAndWaitForWindow's poll loop may have regressed")
assert_full_or_fail "$pid" "phase 2 (#2)"

# --- Phase 3: #1 (drift-back / guardPosition retile) -------------------------
# No spawn delay; instead, the spawned window reverts to its default frame
# 100ms after every external resize/move (debounce > guardPosition's 50ms
# poll interval to keep ordering deterministic). If this fails while phases 1
# and 2 passed, guardPosition didn't catch the drift.
echo "  phase 3: #1 drift-back (1 revert, 100ms debounce)"
launch_problematic --windows 0 --drift-back-times 1 --drift-back-delay-ms 100
[[ "$(prob_window_count)" == "0" ]] || { echo "  phase 3: expected 0 initial windows" >&2; exit 1; }
park_other_app_in_front
post_chord_focus_tile 4 j
pid=$(wait_for_window_or_fail "  phase 3 (#1): window never appeared")
# assert_rect_approx polls for 1s; that's longer than the 100ms drift cycle
# plus guardPosition's first ~50–100ms poll, so the retile has time to land.
assert_full_or_fail "$pid" "phase 3 (#1)"
