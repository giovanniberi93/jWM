#!/usr/bin/env bash
# Shared helpers for jwm integration tests. Sourced by test-integration.sh and each test case.

set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCREEN_HELPER_SRC="$ROOT/integration-tests/screen-info-helper.swift"
SCREEN_HELPER_BIN="$ROOT/build/test/screen-info-helper"

# Tolerances mirror WindowTiler.matchHalfPosition: 20px absolute on origin,
# 15% on size. Tests stay deterministic without being brittle to AppKit rounding.
TOL_POS=${TOL_POS:-20}
TOL_SIZE_PCT=${TOL_SIZE_PCT:-15}

color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
green()  { color 32 "$1"; }
red()    { color 31 "$1"; }
yellow() { color 33 "$1"; }
cyan()   { color 36 "$1"; }

# Compile the AppKit-coords helper once per harness run instead of JIT-ing it
# on every call (each `swift script.swift` is ~1s).
ensure_screen_helper() {
    if [ ! -x "$SCREEN_HELPER_BIN" ] || [ "$SCREEN_HELPER_SRC" -nt "$SCREEN_HELPER_BIN" ]; then
        mkdir -p "$(dirname "$SCREEN_HELPER_BIN")"
        swiftc -O "$SCREEN_HELPER_SRC" -o "$SCREEN_HELPER_BIN"
    fi
}

expected_rect() {
    ensure_screen_helper
    "$SCREEN_HELPER_BIN" expected-rect "$1"
}

expected_rect_on() {
    ensure_screen_helper
    "$SCREEN_HELPER_BIN" expected-rect-on "$1" "$2"
}

screen_count() {
    ensure_screen_helper
    "$SCREEN_HELPER_BIN" screen-count
}

# Index of the NSScreen containing the rect's center, or -1.
screen_of_rect() {
    ensure_screen_helper
    "$SCREEN_HELPER_BIN" screen-of "$1" "$2" "$3" "$4"
}

# Self-guard for tests that need N screens. Used by tests under
# test-cases/multi-screen/ so a direct filter run on a single-screen system
# fails clearly instead of producing confusing assertion errors.
require_screens() {
    local needed="$1"
    local actual
    actual=$(screen_count)
    if (( actual < needed )); then
        echo "  requires $needed screens, found $actual" >&2
        exit 1
    fi
}

# --- Victim app management ----------------------------------------------------

# Launch app by bundle id and wait up to 5s for its first window. If running
# with no windows (typical between-tests state after close-every-window cleanup),
# explicitly creates a new window via app-specific AppleScript.
victim_launch() {
    local bundle="$1"
    open -b "$bundle" >/dev/null 2>&1 || true

    case "$bundle" in
        com.apple.Terminal)
            osascript -e 'tell application "Terminal" to if (count of windows) is 0 then do script ""' >/dev/null 2>&1 || true
            ;;
        com.apple.TextEdit)
            osascript -e 'tell application "TextEdit" to if (count of documents) is 0 then make new document' >/dev/null 2>&1 || true
            ;;
        com.apple.Notes)
            osascript -e 'tell application "Notes" to activate' >/dev/null 2>&1 || true
            ;;
    esac

    local deadline=$(($(date +%s) + 5))
    while (( $(date +%s) < deadline )); do
        local count
        count=$(osascript <<EOF 2>/dev/null || echo 0
tell application "System Events"
    if exists (first application process whose bundle identifier is "$bundle") then
        return count of windows of (first application process whose bundle identifier is "$bundle")
    else
        return 0
    end if
end tell
EOF
)
        if [[ "$count" =~ ^[1-9] ]]; then
            return 0
        fi
        sleep 0.1
    done
    echo "victim_launch: $bundle never opened a window" >&2
    return 1
}

victim_activate() {
    local bundle="$1"
    osascript -e "tell application id \"$bundle\" to activate" >/dev/null
    # NSWorkspace activation notification is async; let jwm process it before
    # the next chord. guardActivation polls at 0.05s, so 0.15s is a safe gap.
    sleep 0.2
}

victim_get_pid() {
    local bundle="$1"
    osascript <<EOF
tell application "System Events"
    return unix id of (first application process whose bundle identifier is "$bundle")
end tell
EOF
}

# Read front window rect via AppleScript AX. Returns "x y w h" in CG coords
# (top-left origin, matching Coords.cg from CoordinateHelper.swift).
victim_get_rect() {
    local pid="$1"
    osascript <<EOF
tell application "System Events"
    tell (first process whose unix id is $pid)
        if (count of windows) is 0 then return ""
        set p to position of front window
        set s to size of front window
        return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
    end tell
end tell
EOF
}

victim_set_rect() {
    local pid="$1" x="$2" y="$3" w="$4" h="$5"
    osascript <<EOF >/dev/null
tell application "System Events"
    tell (first process whose unix id is $pid)
        set position of front window to {$x, $y}
        set size of front window to {$w, $h}
    end tell
end tell
EOF
}

frontmost_bundle() {
    osascript -e 'tell application "System Events" to bundle identifier of (first application process whose frontmost is true)'
}

# --- Synthetic input ----------------------------------------------------------

# Keycodes for the chord keys. jwm reads these via Carbon kVK_ANSI_*; mapping
# is hardcoded here so the harness has no Carbon dependency. macOS default bash
# is 3.2 (no associative arrays), so this is a case.
keycode() {
    case "$1" in
        a) echo 0;;  s) echo 1;;  d) echo 2;;  f) echo 3;;
        h) echo 4;;  g) echo 5;;  z) echo 6;;  x) echo 7;;
        c) echo 8;;  v) echo 9;;  b) echo 11;;
        q) echo 12;; w) echo 13;; e) echo 14;; r) echo 15;;
        y) echo 16;; t) echo 17;;
        1) echo 18;; 2) echo 19;; 3) echo 20;; 4) echo 21;;
        6) echo 22;; 5) echo 23;; 9) echo 25;; 7) echo 26;; 8) echo 28;; 0) echo 29;;
        j) echo 38;; k) echo 40;; l) echo 37;;
        *) echo "unknown key: $1" >&2; return 1;;
    esac
}

# ctrl+cmd+<key> → tile current focused window (matches HotkeyManager.swift:136)
post_tile_current() {
    local key="$1"
    local kc
    kc=$(keycode "$key")
    osascript <<EOF >/dev/null
tell application "System Events"
    key code $kc using {command down, control down}
end tell
EOF
}

# cmd+<num> + <pos> with cmd held throughout → focus + tile
# (matches HotkeyManager.swift chord state machine)
post_chord_focus_tile() {
    local num="$1" pos="$2"
    local num_kc pos_kc
    num_kc=$(keycode "$num")
    pos_kc=$(keycode "$pos")
    osascript <<EOF >/dev/null
tell application "System Events"
    key down command
    delay 0.03
    key code $num_kc
    delay 0.03
    key code $pos_kc
    delay 0.03
    key up command
end tell
EOF
}

# cmd+<num> then release cmd → focus only (matches HotkeyManager.swift:99)
post_chord_focus_only() {
    local num="$1"
    local num_kc
    num_kc=$(keycode "$num")
    osascript <<EOF >/dev/null
tell application "System Events"
    key down command
    delay 0.03
    key code $num_kc
    delay 0.05
    key up command
end tell
EOF
    sleep 0.1
}

# --- Assertions ---------------------------------------------------------------

# Assert a window's rect approximately matches expected, polling for up to
# guardActivation's 0.5s displacement window plus headroom for AX latency.
assert_rect_approx() {
    local pid="$1" ex="$2" ey="$3" ew="$4" eh="$5"
    local deadline=$(($(date +%s) + 1))
    local last="" ax ay aw ah dx dy dw dh size_tol_w size_tol_h
    while (( $(date +%s) <= deadline )); do
        last=$(victim_get_rect "$pid" 2>/dev/null || echo "")
        if [ -n "$last" ]; then
            read -r ax ay aw ah <<<"$last"
            if [[ "$ax" =~ ^-?[0-9]+$ && "$ay" =~ ^-?[0-9]+$ && "$aw" =~ ^[0-9]+$ && "$ah" =~ ^[0-9]+$ ]]; then
                dx=$(( ax - ex )); dy=$(( ay - ey ))
                dw=$(( aw - ew )); dh=$(( ah - eh ))
                dx=${dx#-}; dy=${dy#-}; dw=${dw#-}; dh=${dh#-}
                size_tol_w=$(( ew * TOL_SIZE_PCT / 100 ))
                size_tol_h=$(( eh * TOL_SIZE_PCT / 100 ))
                if (( dx < TOL_POS && dy < TOL_POS && dw <= size_tol_w && dh <= size_tol_h )); then
                    return 0
                fi
            fi
        fi
        sleep 0.05
    done
    echo "  expected: $ex $ey $ew $eh" >&2
    echo "  actual:   ${last:-<unreadable>}" >&2
    return 1
}

# Same as assert_rect_approx but the failure is the success: assert the rect
# does NOT change within guardActivation's 0.5s displacement window. Used by
# test 05 (half-replaces-half = no displacement) and test 07 (focus-only no-op).
assert_rect_stable() {
    local pid="$1" ex="$2" ey="$3" ew="$4" eh="$5"
    local iterations=3  # ~3 × (osascript ~0.1s + 0.12s sleep) = ~0.65s, past guardActivation's 0.5s window
    local i
    for (( i = 0; i < iterations; i++ )); do
        local last
        last=$(victim_get_rect "$pid" 2>/dev/null || echo "")
        if [ -n "$last" ]; then
            read -r ax ay aw ah <<<"$last"
            local dx dy dw dh
            dx=$(( ax - ex )); dy=$(( ay - ey ))
            dw=$(( aw - ew )); dh=$(( ah - eh ))
            dx=${dx#-}; dy=${dy#-}; dw=${dw#-}; dh=${dh#-}
            local size_tol_w size_tol_h
            size_tol_w=$(( ew * TOL_SIZE_PCT / 100 ))
            size_tol_h=$(( eh * TOL_SIZE_PCT / 100 ))
            if ! (( dx < TOL_POS && dy < TOL_POS && dw <= size_tol_w && dh <= size_tol_h )); then
                echo "  rect drifted: expected $ex $ey $ew $eh, got $last" >&2
                return 1
            fi
        fi
        sleep 0.1
    done
    return 0
}

# Strict rect assertion with absolute px tolerance on every component.
# Use when TOL_SIZE_PCT (15%) is too loose — e.g. cross-screen fullscreen
# checks where a window that's clearly visibly off-full would still pass
# the percentage check. Default tol = 5px; override via 6th arg.
assert_rect_exact() {
    local pid="$1" ex="$2" ey="$3" ew="$4" eh="$5" tol="${6:-5}"
    local deadline=$(($(date +%s) + 1))
    local last="" ax ay aw ah dx dy dw dh
    while (( $(date +%s) <= deadline )); do
        last=$(victim_get_rect "$pid" 2>/dev/null || echo "")
        if [ -n "$last" ]; then
            read -r ax ay aw ah <<<"$last"
            if [[ "$ax" =~ ^-?[0-9]+$ && "$ay" =~ ^-?[0-9]+$ && "$aw" =~ ^[0-9]+$ && "$ah" =~ ^[0-9]+$ ]]; then
                dx=$(( ax - ex )); dy=$(( ay - ey ))
                dw=$(( aw - ew )); dh=$(( ah - eh ))
                dx=${dx#-}; dy=${dy#-}; dw=${dw#-}; dh=${dh#-}
                if (( dx <= tol && dy <= tol && dw <= tol && dh <= tol )); then
                    return 0
                fi
            fi
        fi
        sleep 0.05
    done
    echo "  expected (±${tol}px): $ex $ey $ew $eh" >&2
    echo "  actual:               ${last:-<unreadable>}" >&2
    return 1
}

assert_frontmost() {
    local expected_bundle="$1"
    local actual
    actual=$(frontmost_bundle 2>/dev/null || echo "")
    if [ "$actual" != "$expected_bundle" ]; then
        echo "  expected frontmost: $expected_bundle" >&2
        echo "  actual:             $actual" >&2
        return 1
    fi
    return 0
}
