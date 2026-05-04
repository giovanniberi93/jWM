# Plan — replace AX systemWide cursor lookup with Quartz window list

## Why

`SnapManager.getWindowInfoUnderCursor` calls
`AXUIElementCopyElementAtPosition(systemWide, ...)` on every `leftMouseDown`.
This is synchronous Mach IPC against the app under the cursor. When that app
is slow or hung (most painful case observed: clicks inside an `NSOpenPanel`,
which is hosted by `com.apple.appkit.xpc.openAndSavePanelService`), the call
blocks the main thread for up to the AX messaging timeout — currently 100ms
after mitigation (1), previously 6s.

Rectangle's `AccessibilityElement.getWindowElementUnderCursor` avoids this hop
entirely in its default code path. It uses `CGWindowListCopyWindowInfo`
(Quartz, no IPC) to find the pid that owns the window under the cursor, then
only invokes AX against that specific pid. That is the change to replicate.

References:
- `Rectangle/Rectangle/AccessibilityElement.swift:328` — `getWindowElementUnderCursor`
- `Rectangle/Rectangle/Utilities/WindowUtil.swift:13` — `getWindowList`

## Goal

`SnapManager.getWindowInfoUnderCursor(at:)` should resolve `(pid, origin)`
for the window under the cursor without any AX call against the systemWide
element. AX should only be invoked against an already-known pid (via
`getWindowOrigin`), not against `systemWide`.

## Design

### New helper: `helpers/QuartzWindowList.swift`

Wraps `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`.

Returns an array of:

```swift
struct QuartzWindowInfo {
    let id: CGWindowID
    let level: CGWindowLevel
    let frame: CGRect       // CG coords (origin top-left of primary screen)
    let pid: pid_t
    let processName: String?
}
```

Add a small TTL cache (~100ms) keyed on the option set, mirroring Rectangle's
`WindowUtil.getWindowList`. Mouse-down events arrive in bursts during a drag;
the cache prevents redundant `CGWindowListCopyWindowInfo` calls without
hiding genuinely fresh state.

Filter rules in `getWindowAtPoint(_:)`:
1. `frame.contains(point)` — geometric hit test.
2. `level < CGWindowLevelForKey(.notificationWindowLevelKey)` — exclude
   Notification Center / overlays. Rectangle uses the literal `< 23`; prefer
   the symbolic constant for clarity. Keep the exclusion list short — only
   add constants for layers we've actually seen cause problems.
3. `processName != "Dock"`, `processName != "WindowManager"` — same as
   Rectangle.

Return the first match (window list is z-order, frontmost first).

### Rewrite `SnapManager.getWindowInfoUnderCursor`

Replace the AX-position-lookup path with:

```swift
guard let info = QuartzWindowList.windowAtPoint(point) else { return nil }
let pid = info.pid
guard let app = NSRunningApplication(processIdentifier: pid),
      let bundleID = app.bundleIdentifier,
      !Self.ignoredBundleIDs.contains(bundleID) else { return nil }
guard let origin = getWindowOrigin(pid: pid) else { return nil }
return (pid, origin)
```

The bundle-id ignore check now happens *before* any AX call (mitigation 3),
which is only possible because Quartz gives us the pid without IPC.

Note: `info.frame.origin` is roughly the window origin in CG coords already.
We could skip `getWindowOrigin` and use `info.frame.origin` directly, but that
diverges from the AX origin used by `setPosition` in WindowAccessibility.swift
and could introduce off-by-titlebar drift between mouseDown sample and later
AX writes. Defer this micro-optimization; keep `getWindowOrigin` as the
authoritative origin.

### Things to verify on multi-screen

Per `CLAUDE.md`: every change must be assessed for multi-screen. Quartz frames
are reported in CG coords (origin top-left of primary screen, y-down).
`SnapManager.handleMouseDown` already passes `NSEvent.mouseLocation.toCG` to
the lookup, so coordinate spaces match. Confirm:
- click on secondary screen window resolves the right pid;
- pid resolution still works with mixed full-screen / half-tiled layouts;
- the `level < 23` filter doesn't accidentally hide stage-strip windows on
  systems with Stage Manager enabled (Rectangle has special handling for this
  — see `StageUtil.getStageStripWindowGroup`. Out of scope for jwm unless a
  user reports issues.)

### Electron / broken AX trees

The current code has a comment noting Electron apps (WhatsApp, Slack) have
broken parent chains in the AX tree, which is why it doesn't walk up from
`elementRef` to find the window. That concern goes away with Quartz: Quartz
reports the owning pid directly from WindowServer, no AX walk needed.

### Removed AX call

`AXUIElementCopyElementAtPosition` is no longer used in jwm after this
change. The corresponding `makeSystemWideAXElement()` helper in
`AXTimeout.swift` becomes dead code unless we add another systemWide consumer
later. Remove the helper if there are no other callers, or keep it for
symmetry — author's call.

## Tests

Unit-test `QuartzWindowList.windowAtPoint(_:)` against a mock window list
(inject the raw CFArray for determinism). Cases:
- point inside frontmost window's frame → returns it
- point inside a frame but window is `Dock` → skipped, returns next
- point inside notification-level window → skipped
- point outside any frame → nil
- TTL cache: second call within 100ms reuses prior list

Integration: existing snap-on-drag integration tests should still pass
unchanged — the public behavior of `SnapManager.handleMouseDown` is the same.
Add one targeted test where the foreground app is the panel-service stub (or
any unresponsive stub) and verify mouseDown returns within ~10ms instead of
the AX-timeout window.

## Order of operations

1. Add `helpers/QuartzWindowList.swift` with `QuartzWindowInfo`,
   `windowAtPoint(_:)`, and a `TimeoutCache`.
2. Unit tests for the helper.
3. Rewrite `SnapManager.getWindowInfoUnderCursor` to use it. Move the
   `ignoredBundleIDs` check before `getWindowOrigin`.
4. Run integration tests (`make test-integration`).
5. Manual verification: open `NSOpenPanel` from settings, click around inside
   it, confirm no jwm hotkey lag.
6. (Optional cleanup) Remove `makeSystemWideAXElement` from `AXTimeout.swift`
   if no callers remain.

## Open questions

- Should we extend `ignoredBundleIDs` to include
  `com.apple.appkit.xpc.openAndSavePanelService` and
  `com.apple.coreservices.uiagent` while we're touching this code? Cheap, and
  matches Rectangle's `fullIgnoreIds` philosophy.
- Should snap be disabled entirely while the jwm settings window is key?
  Trivially achievable via a `frontAppChanged`-style observer. Less invasive
  than the current paused/resumed scheme but with the same effect.
