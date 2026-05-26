#!/usr/bin/env bash
# Regression for the LaunchServices "dying instance" race fixed in 02e70c6:
# when our open(_:withApplicationAt:) routes into a process that's already
# tearing down (cmd+Q in flight; IntelliJ's 3-4s post-quit window with the
# menu bar still up but Apple Events going nowhere), the dying instance
# silently drops the open event and then exits. Without the fix,
# launchAndWaitForWindow polls until its 10s timeout and the chord lands
# nowhere. With the fix, it captures the pre-open pid, notices it has gone
# during the wait, and reissues the LaunchServices launch once.
#
# Setup: launch the problematic stub with --spawn-delay-ms 30000 so it sits
# windowless throughout (mimics IntelliJ post-cmd+Q: running, no windows,
# won't respond). Fire a focus-tile chord — janzowmApp's onFocusTile
# always routes through launchAndWaitForWindow when the target has no
# windows, regardless of whether a path is attached. Kill the stub a beat
# later; with the retry in place, janzowm reissues the launch against a
# fresh process and the new instance opens a window normally.
#
# Path bindings aren't part of the setup: the retry lives inside
# launchAndWaitForWindow, which the no-path focus-tile branch exercises
# identically. Keeping the test path-less avoids handing the stub a URL
# (which would otherwise surface the system "cannot open files in the X
# format" NSAlert and defeat the windowless precondition).
set -euo pipefail
source "$ROOT/integration-tests/test-lib.sh"

PROB_BUNDLE="${PROB_BUNDLE:-com.giovanniberi93.janzowm.problematic}"

prob_running() {
    osascript -e "tell application \"System Events\" to exists (first application process whose bundle identifier is \"$PROB_BUNDLE\")" 2>/dev/null || echo "false"
}

prob_window_count() {
    osascript -e "tell application \"System Events\" to count of windows of (first application process whose bundle identifier is \"$PROB_BUNDLE\")" 2>/dev/null || echo 0
}

# Make sure no prior instance is around so we own the bundle id and can
# capture the pid we just launched.
osascript -e "tell application id \"$PROB_BUNDLE\" to quit" 2>/dev/null || true
deadline=$(($(date +%s) + 3))
while (( $(date +%s) < deadline )); do
    [ "$(prob_running)" = "true" ] || break
    sleep 0.1
done

# Cold launch with a 30s spawn delay — the stub is alive and visible to
# NSRunningApplication but produces zero AX windows for the whole test,
# matching the "running but unable to handle our open" state we want to
# simulate.
open -b "$PROB_BUNDLE" -n --args --spawn-delay-ms 30000 >/dev/null 2>&1 || {
    echo "  failed to launch $PROB_BUNDLE" >&2
    exit 1
}

deadline=$(($(date +%s) + 5))
initial_pid=""
while (( $(date +%s) < deadline )); do
    if [ "$(prob_running)" = "true" ]; then
        initial_pid=$(victim_get_pid "$PROB_BUNDLE" 2>/dev/null || echo "")
        [[ "$initial_pid" =~ ^[1-9][0-9]*$ ]] && break
        initial_pid=""
    fi
    sleep 0.1
done
if [ -z "$initial_pid" ]; then
    echo "  problematic stub never registered as running" >&2
    exit 1
fi
if [[ "$(prob_window_count)" =~ ^[1-9] ]]; then
    echo "  problematic stub spawned a window despite --spawn-delay-ms 30000" >&2
    exit 1
fi

trap 'osascript -e "tell application id \"$PROB_BUNDLE\" to quit" 2>/dev/null || true' EXIT

# Fire focus-tile chord (cmd+4 + J). With the target running and
# window-less, onFocusTile goes through launchAndWaitForWindow regardless
# of path. janzowm captures initial_pid synchronously inside
# launchAndWaitForWindow before kicking off its wait loop.
post_chord_focus_tile 4 j

# Brief window for janzowm to enter the wait loop and issue the first
# LaunchServices openApplication against initial_pid.
sleep 0.3

# Kill the stub. NSRunningApplication's list drops it within the wait
# loop's next 50ms poll, satisfying the retry's `runningNow == nil` guard.
kill -KILL "$initial_pid" 2>/dev/null || true

# The retry reissues openApplication once. With no instance running,
# LaunchServices cold-launches a fresh stub — without our
# --spawn-delay-ms — so it opens a window on the default code path.
deadline=$(($(date +%s) + 9))
new_pid=""
while (( $(date +%s) < deadline )); do
    p=$(victim_get_pid "$PROB_BUNDLE" 2>/dev/null || echo "")
    if [[ "$p" =~ ^[1-9][0-9]*$ && "$p" != "$initial_pid" ]]; then
        new_pid="$p"
        break
    fi
    sleep 0.1
done
if [ -z "$new_pid" ]; then
    echo "  expected $PROB_BUNDLE to relaunch after initial_pid=$initial_pid was killed mid-wait; never saw a fresh pid" >&2
    exit 1
fi

deadline=$(($(date +%s) + 3))
while (( $(date +%s) < deadline )); do
    [[ "$(prob_window_count)" =~ ^[1-9] ]] && exit 0
    sleep 0.1
done
echo "  relaunched $PROB_BUNDLE (pid=$new_pid) never produced a window" >&2
exit 1
