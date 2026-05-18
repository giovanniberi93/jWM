import Cocoa
import os

enum WindowTiler {
    static var slots = SlotState()
    /// The previously active app. Used to promote-check on defocus, catching
    /// apps that resized to fullscreen while they were already focused.
    /// Strong ref: the NSRunningApplication from the notification may be transient,
    /// so a weak ref would go nil before the next activation fires.
    private static var lastActiveApp: NSRunningApplication?

    /// Wipe every piece of `WindowTiler` state that can carry between
    /// integration-test cases: slots (fullscreen window map), the
    /// defocus-snapshot anchor, and the chord-launch suppression flag. Called
    /// from the SIGUSR1 handler and from the ctrl+cmd+S abort path. Clearing
    /// `lastActiveApp` matters because otherwise the next activation's
    /// defocus path would re-snapshot the previously-frontmost (often a
    /// user-owned) app and re-populate slots before the test's chord runs.
    static func resetForIntegrationTest() {
        slots = SlotState()
        lastActiveApp = nil
        suppressDisplaceForBundleID = nil
    }

    /// While non-nil, `snapFocusedToExactHalf` refuses to act on the named
    /// bundleID. Set by the chord launch path so that the activation
    /// notification fired during launch (with the app at its *restored*
    /// position) doesn't trigger a snap + displacement based on the wrong
    /// geometry — the chord's own `tile()` is the single source of truth for
    /// positioning during a chord action.
    ///
    /// Primary clear: the launch path's `defer` in `launchAndWaitForWindow`'s
    /// completion (deterministic; completion is always invoked).
    ///
    /// Safety backstop: `snapFocusedToExactHalf` self-heals any suppression
    /// older than `maxSuppressionAge` so a bug in the primary path can never
    /// let a stale flag affect tiling indefinitely.
    static var suppressDisplaceForBundleID: String? {
        didSet { suppressDisplaceSetAt = suppressDisplaceForBundleID != nil ? Date() : nil }
    }
    private static var suppressDisplaceSetAt: Date?

    /// Generous upper bound: `launchAndWaitForWindow` times out at 10s, so
    /// any suppression older than this is by definition orphaned.
    private static let maxSuppressionAge: TimeInterval = 15.0

    /// Tolerance for "this window matches a slot rect" comparisons.
    /// 20px catches near-fullscreen windows whose AX position drifts slightly.
    private static let positionTolerance: CGFloat = 20

    /// Resolve a PID to app name for logging. Falls back to "pid=N" if app is gone.
    private static func appName(_ pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid=\(pid)"
    }

    private static func appName(_ app: NSRunningApplication) -> String {
        app.localizedName ?? "pid=\(app.processIdentifier)"
    }

    /// Tile the frontmost window of the given app to the specified position.
    /// If no app is specified, tiles the frontmost window of the currently active app.
    /// Automatically displaces a full-screen app to the opposite half when needed.
    ///
    /// Geometry only — slot tracking is updated by `syncSlots` at
    /// action boundaries (HotkeyManager `onBeforeAction` and `guardActivation`'s
    /// defocus path), not from inside `tile`.
    static func tile(_ position: TilePosition, app: NSRunningApplication? = nil, targetScreen: NSScreen? = nil) {
        guard let targetApp = app ?? NSWorkspace.shared.frontmostApplication else {
            logger.info("No frontmost app found")
            return
        }
        let pid = targetApp.processIdentifier
        logger.info("Tiling \(targetApp.localizedName ?? "unknown") to \(position)")

        if position == .nextScreen {
            moveToNextScreen(app: targetApp)
            return
        }

        guard let screen = targetScreen ?? screenForApp(targetApp) ?? NSScreen.main else {
            logger.info("No screen found")
            return
        }
        let screenIndex = NSScreen.screens.firstIndex(of: screen) ?? -1
        logger.info("\(targetApp.localizedName ?? "unknown") is on screen \(screenIndex) (frame: \(screen.frame))")

        let cgRect = Coords.rect(for: position, on: screen)

        // Displace a full-screen window to the opposite half if we're tiling
        // to a half. We exclude the *target window* (not the target pid) so a
        // second window of the same app can correctly displace the first —
        // see integration-tests/test-cases/19_multi_window_same_app_displacement_bug.sh.
        // findDisplacementCandidate validates each candidate is alive + still
        // fullscreen-sized; stale entries are pruned in-place.
        let displayID = screen.displayID
        logger.info("tile(\(targetApp.localizedName ?? "unknown"), pid=\(pid)): slots before displacement: \(slots.dump())")
        if let oppositePosition = position.opposite,
           let focusedWinId = WindowAX.getFocusedWindowId(pid: pid),
           let candidate = findDisplacementCandidate(excludingWindowId: focusedWinId, display: displayID, screen: screen) {
            logger.info("Displacing \(appName(candidate.pid)) (pid=\(candidate.pid), win=\(candidate.windowId)) to \(oppositePosition) on screen \(screenIndex) (display \(displayID))")
            let oppositeRect = Coords.rect(for: oppositePosition, on: screen)
            WindowAX.setPosition(pid: candidate.pid, windowId: candidate.windowId, rect: oppositeRect)
            // Don't touch slots here. The displaced window's next snapshot
            // (defocus path or next onBeforeAction) will see it's no longer
            // full and remove its entry via syncSlots.
        }

        WindowAX.setPosition(pid: pid, rect: cgRect)
    }

    /// Match a window rect against the left/right half positions for a given screen.
    /// Returns .left or .right if within tolerance, nil otherwise.
    /// Tight tolerance on position (20px); generous on size (15% of expected dim)
    /// to catch apps that restore to roughly-half sizes.
    static func matchHalfPosition(windowRect: CGRect, screen: NSScreen) -> TilePosition? {
        matchHalfPosition(windowRect: windowRect, frame: screen.visibleFrame, primaryHeight: Coords.primaryHeight)
    }

    /// Pure-logic seam for unit tests. Same semantics as the screen-based
    /// overload, but takes the visibleFrame and primary screen height directly
    /// so tests don't need to construct an NSScreen.
    static func matchHalfPosition(windowRect: CGRect, frame: NSRect, primaryHeight: CGFloat) -> TilePosition? {
        let leftRect = Coords.rect(for: .left, frame: frame, primaryHeight: primaryHeight)
        let rightRect = Coords.rect(for: .right, frame: frame, primaryHeight: primaryHeight)

        func matches(_ expected: CGRect) -> Bool {
            abs(windowRect.origin.x - expected.origin.x) < positionTolerance
                && abs(windowRect.origin.y - expected.origin.y) < positionTolerance
                && abs(windowRect.width - expected.width) < expected.width * 0.15
                && abs(windowRect.height - expected.height) < expected.height * 0.15
        }

        if matches(leftRect) { return .left }
        if matches(rightRect) { return .right }
        return nil
    }

    /// Pure-logic seam for unit tests — wraps Coords.rect(for:frame:primaryHeight:).
    static func rectForPosition(_ position: TilePosition, frame: NSRect, primaryHeight: CGFloat) -> CGRect {
        Coords.rect(for: position, frame: frame, primaryHeight: primaryHeight)
    }

    /// Returns true if a displacement actually happened.
    /// Pure-logic seam for unit tests. Clears `suppressDisplaceForBundleID`
    /// if its age against `now` exceeds `maxSuppressionAge`. Returns true
    /// iff a stale flag was cleared. The default `now = Date()` lets the
    /// production call site stay terse.
    @discardableResult
    static func clearSuppressionIfStale(now: Date = Date()) -> Bool {
        guard let suppressed = suppressDisplaceForBundleID,
              let setAt = suppressDisplaceSetAt,
              now.timeIntervalSince(setAt) > maxSuppressionAge else {
            return false
        }
        logger.error("clearSuppressionIfStale: clearing stale suppression for \(suppressed) (age > \(maxSuppressionAge)s)")
        suppressDisplaceForBundleID = nil
        return true
    }

    /// If the app's focused window is approximately at a half position
    /// (left/right), snap it to the *exact* half rect and return both the
    /// matched position and the screen it's on. Returns nil if not at a half,
    /// if the window/screen can't be read, or if displacement is currently
    /// suppressed (chord-launch path in flight). Callers pair this with
    /// `displaceFullScreenSibling` to finish the half-half layout.
    @discardableResult
    static func snapFocusedToExactHalf(for app: NSRunningApplication) -> (position: TilePosition, screen: NSScreen)? {
        let pid = app.processIdentifier
        let name = appName(app)
        clearSuppressionIfStale()
        if let suppressed = suppressDisplaceForBundleID, app.bundleIdentifier == suppressed {
            logger.info("snapFocusedToExactHalf(\(name)): suppressed — chord launch in flight for \(suppressed)")
            return nil
        }
        guard let windowRect = WindowAX.getRect(pid: pid) else {
            logger.info("snapFocusedToExactHalf: no window rect for \(name)")
            return nil
        }
        guard let screen = screenForApp(app) else {
            logger.info("snapFocusedToExactHalf: no screen for \(name)")
            return nil
        }
        guard let position = matchHalfPosition(windowRect: windowRect, screen: screen) else {
            logger.info("snapFocusedToExactHalf(\(name)): no half match (windowRect=\(windowRect) displayID=\(screen.displayID))")
            return nil
        }
        let snapRect = Coords.rect(for: position, on: screen)
        if windowRect != snapRect {
            logger.info("Snapping \(name) to exact \(position)")
            WindowAX.setPosition(pid: pid, rect: snapRect)
        }
        return (position, screen)
    }

    /// Move a fullscreen-tracked sibling on `screen` to the given half
    /// position, so the activated app's half and its sibling's half together
    /// tile the screen. Excludes the activated app's *focused* window — a
    /// background window of the same app is still a valid sibling. No-op if
    /// no candidate is found. Doesn't mutate slots; the next syncSlots over
    /// the displaced window will see it's no longer fullscreen.
    static func displaceFullScreenSibling(for app: NSRunningApplication, to position: TilePosition, on screen: NSScreen) {
        let pid = app.processIdentifier
        let name = appName(app)
        guard let focusedWinId = WindowAX.getFocusedWindowId(pid: pid) else {
            logger.info("displaceFullScreenSibling(\(name)): no focused windowId")
            return
        }
        guard let candidate = findDisplacementCandidate(excludingWindowId: focusedWinId, display: screen.displayID, screen: screen) else {
            return
        }
        let oppositeRect = Coords.rect(for: position, on: screen)
        logger.info("External activation: displacing \(appName(candidate.pid)) (win=\(candidate.windowId)) to \(position) for \(name)")
        WindowAX.setPosition(pid: candidate.pid, windowId: candidate.windowId, rect: oppositeRect)
    }

    /// Poll briefly, retrying `syncSlots` and (if the focused window is at a
    /// half) `snapFocusedToExactHalf` + `displaceFullScreenSibling` until the
    /// app's window settles. For already-running apps this fires on the first
    /// iteration; for freshly launched apps (e.g. via Spotlight) it retries
    /// until the window appears.
    static func guardActivation(app: NSRunningApplication) {
        logger.info("guardActivation(\(app.localizedName ?? "unknown"), pid=\(app.processIdentifier)) prev=\(lastActiveApp.map { "\($0.localizedName ?? "unknown")/pid=\($0.processIdentifier)" } ?? "nil") slots=\(slots.dump())")
        // Before processing the new app, snapshot the one that just lost focus.
        // Catches apps that resized to fullscreen while already active (no
        // activation event would have fired for them); also removes the entry
        // for apps that just got displaced from full to half.
        if let prev = lastActiveApp, prev.processIdentifier != app.processIdentifier {
            if syncSlots(for: prev) {
                logger.info("Recorded \(prev.localizedName ?? "unknown") (pid=\(prev.processIdentifier)) as fullscreen on defocus")
            }
        }
        lastActiveApp = app

        let pid = app.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            while Date().timeIntervalSince(start) < 0.5 {
                Thread.sleep(forTimeInterval: 0.05)
                if NSRunningApplication(processIdentifier: pid) == nil { return }
                var done = false
                DispatchQueue.main.sync {
                    if syncSlots(for: app) { done = true; return }
                    guard let result = snapFocusedToExactHalf(for: app) else { return }
                    done = true
                    if let opposite = result.position.opposite {
                        displaceFullScreenSibling(for: app, to: opposite, on: result.screen)
                    }
                }
                if done { return }
            }
        }
    }

    /// Sync `slots` for every window of the given app:
    /// - Each fullscreen-sized window is upserted (fresh seq → most-recent).
    /// - Each non-fullscreen window has its prior entry removed.
    /// Returns true iff the **focused** window is fullscreen-sized — that's
    /// what `guardActivation`'s early-return logic cares about. Background
    /// windows still get captured as a side effect so multi-window apps
    /// remain visible to `findDisplacementCandidate`.
    ///
    /// Enumeration uses `QuartzWindowList` (one WindowServer IPC, no AX hop
    /// into the target app) instead of walking kAXWindows. Reason: this runs
    /// from `onBeforeAction` on the main thread for every chord, and walking
    /// AX would scale per-window IPCs at `axMessagingTimeout` each. Same
    /// motivation as commit 9088b8e's SnapManager rewrite.
    @discardableResult
    static func syncSlots(for app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let name = appName(app)
        let windows = QuartzWindowList.windowsForPid(pid)
        if windows.isEmpty {
            logger.info("syncSlots(\(name)): no windows")
            slots.removeAll(forPid: pid)
            return false
        }
        // One AX call (focused window + getWindowId). Cheap relative to the
        // old per-window walk; gives us the "focusedFull" return value.
        let focusedWinId = WindowAX.getFocusedWindowId(pid: pid)
        var focusedFull = false
        for window in windows {
            guard let screen = Coords.screen(containingCG: window.frame) else {
                if slots.contains(windowId: window.id) {
                    logger.info("syncSlots(\(name)) win=\(window.id): off-screen, removing")
                }
                slots.remove(windowId: window.id)
                continue
            }
            let fullRect = Coords.rect(for: .fullScreen, on: screen)
            if window.frame.approxEquals(fullRect, tolerance: positionTolerance) {
                if !slots.contains(windowId: window.id) {
                    logger.info("Recording \(name) (pid=\(pid), win=\(window.id)) as fullscreen on display \(screen.displayID)")
                }
                slots.upsert(windowId: window.id, pid: pid, displayID: screen.displayID)
                if window.id == focusedWinId { focusedFull = true }
            } else {
                if slots.contains(windowId: window.id) {
                    logger.info("syncSlots(\(name)) win=\(window.id): no longer full, removing")
                }
                slots.remove(windowId: window.id)
            }
        }
        logger.info("Slots after syncSlots(\(name)): \(slots.dump())")
        return focusedFull
    }

    /// Find a valid displacement candidate on the given display, excluding the
    /// caller's own *window* (not pid — a sibling window of the same app is a
    /// valid victim). Walks entries newest-first and validates each:
    /// owning process running, window still exists, still fullscreen-sized.
    /// Stale entries are pruned in-place and the next candidate is tried.
    ///
    /// Validation reads the window's current frame from Quartz, not AX, so
    /// the per-candidate cost stays O(1) regardless of how many windows the
    /// candidate's app has. The only AX cost in the displacement path is the
    /// `setPosition(pid:windowId:rect:)` call at the end — and that's
    /// unavoidable since AX is the write API.
    private static func findDisplacementCandidate(
        excludingWindowId: CGWindowID,
        display: CGDirectDisplayID,
        screen: NSScreen
    ) -> (windowId: CGWindowID, pid: pid_t)? {
        let fullRect = Coords.rect(for: .fullScreen, on: screen)

        while let candidate = slots.mostRecentFullScreen(forDisplay: display, excluding: excludingWindowId) {
            let pid = candidate.pid
            let windowId = candidate.windowId
            let name = appName(pid)
            logger.info("findDisplacementCandidate: considering win=\(windowId)/pid=\(pid) (\(name)) on display \(display)")

            let nsra = NSRunningApplication(processIdentifier: pid)
            let posixAlive = (kill(pid, 0) == 0)
            let inWorkspaceList = NSWorkspace.shared.runningApplications.contains { $0.processIdentifier == pid }
            if nsra == nil {
                logger.info("Liveness mismatch pid=\(pid): NSRunningApplication=nil posixAlive=\(posixAlive) inWorkspaceList=\(inWorkspaceList)")
            }
            guard nsra != nil else {
                logger.info("Pruning \(name) (pid=\(pid), win=\(windowId)): process dead")
                slots.removeAll(forPid: pid)
                continue
            }
            guard let info = QuartzWindowList.windowsForPid(pid).first(where: { $0.id == windowId }) else {
                logger.info("Pruning \(name) (pid=\(pid), win=\(windowId)): window gone")
                slots.remove(windowId: windowId)
                continue
            }
            guard info.frame.approxEquals(fullRect, tolerance: positionTolerance) else {
                logger.info("Pruning \(name) (pid=\(pid), win=\(windowId)): window=\(info.frame) full=\(fullRect)")
                slots.remove(windowId: windowId)
                continue
            }
            return candidate
        }
        return nil
    }

    /// Find which screen the given app's window is on.
    /// Returns nil if the window rect can't be read or no screen contains it.
    private static func screenForApp(_ app: NSRunningApplication) -> NSScreen? {
        guard let windowRect = WindowAX.getRect(pid: app.processIdentifier) else { return nil }
        return Coords.screen(containingCG: windowRect)
    }

    /// Move the given app's window to the next screen, tiled full screen.
    /// Returns the target screen on success, nil if only one screen exists.
    @discardableResult
    private static func moveToNextScreen(app: NSRunningApplication) -> NSScreen? {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            logger.info("moveToNextScreen: only one screen, ignoring")
            return nil
        }

        let currentScreen = screenForApp(app)
        let currentIndex = currentScreen.flatMap { s in screens.firstIndex(of: s) } ?? 0
        let nextIndex = (currentIndex + 1) % screens.count
        let targetScreen = screens[nextIndex]
        logger.info("moveToNextScreen: moving \(app.localizedName ?? "unknown") from screen \(currentIndex) to \(nextIndex)")

        let cgRect = Coords.rect(for: .fullScreen, on: targetScreen)

        let pid = app.processIdentifier
        // Cross-screen flag enables read-back-and-retry inside setPosition.
        // macOS often clamps size to the source screen on a single 3-op pass.
        WindowAX.setPosition(pid: pid, rect: cgRect, crossScreen: true)
        return targetScreen
    }
}
