import Cocoa
import os

enum WindowTiler {
    static var slots = SlotState()
    /// The previously active app. Used to promote-check on defocus, catching
    /// apps that resized to fullscreen while they were already focused.
    /// Strong ref: the NSRunningApplication from the notification may be transient,
    /// so a weak ref would go nil before the next activation fires.
    private static var lastActiveApp: NSRunningApplication?

    /// While non-nil, `displaceIfHalf` refuses to act on the named bundleID.
    /// Set by the chord launch path so that the activation notification fired
    /// during launch (with the app at its *restored* position) doesn't trigger
    /// a displacement based on the wrong geometry — the chord's own `tile()`
    /// is the single source of truth for positioning during a chord action.
    ///
    /// Primary clear: the launch path's `defer` in `launchAndWaitForWindow`'s
    /// completion (deterministic; completion is always invoked).
    ///
    /// Safety backstop: `displaceIfHalf` self-heals any suppression older
    /// than `maxSuppressionAge` so a bug in the primary path can never let
    /// a stale flag affect tiling indefinitely.
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
    /// Geometry only — slot tracking is updated by `snapshotIfFullScreen` at
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

        // Displace a full-screen app to the opposite half if we're tiling to a half.
        // findDisplacementCandidate validates each candidate is still alive +
        // fullscreen-sized; stale entries are pruned in-place.
        let displayID = screen.displayID
        logger.info("tile(\(targetApp.localizedName ?? "unknown"), pid=\(pid)): slots before displacement: \(slots.dump())")
        if let oppositePosition = position.opposite,
           let candidate = findDisplacementCandidate(excludingPid: pid, display: displayID, screen: screen) {
            logger.info("Displacing \(appName(candidate)) (pid=\(candidate)) to \(oppositePosition) on screen \(screenIndex) (display \(displayID))")
            let oppositeRect = Coords.rect(for: oppositePosition, on: screen)
            WindowAX.setPosition(pid: candidate, rect: oppositeRect)
            // Don't touch slots here. The displaced app's `lastActiveApp`
            // defocus check (next activation) will see it's no longer full
            // and remove it via snapshotIfFullScreen.
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
        logger.error("displaceIfHalf: clearing stale suppression for \(suppressed) (age > \(maxSuppressionAge)s)")
        suppressDisplaceForBundleID = nil
        return true
    }

    @discardableResult
    static func displaceIfHalf(app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let name = appName(app)
        clearSuppressionIfStale()
        if let suppressed = suppressDisplaceForBundleID, app.bundleIdentifier == suppressed {
            logger.info("displaceIfHalf(\(name)): suppressed — chord launch in flight for \(suppressed)")
            return false
        }
        guard let windowRect = WindowAX.getRect(pid: pid) else {
            logger.info("displaceIfHalf: no window rect for \(name)")
            return false
        }
        guard let screen = screenForApp(app) else {
            logger.info("displaceIfHalf: no screen for \(name)")
            return false
        }
        let displayID = screen.displayID

        let leftRect = Coords.rect(for: .left, on: screen)
        let rightRect = Coords.rect(for: .right, on: screen)
        logger.info("displaceIfHalf(\(name)): windowRect=\(windowRect) leftRect=\(leftRect) rightRect=\(rightRect) displayID=\(displayID)")

        guard let position = matchHalfPosition(windowRect: windowRect, screen: screen) else {
            logger.info("displaceIfHalf(\(name)): no half match")
            return false
        }

        // Snap the activated app to the exact half position
        let snapRect = Coords.rect(for: position, on: screen)
        if windowRect != snapRect {
            logger.info("Snapping \(name) to exact \(position)")
            WindowAX.setPosition(pid: pid, rect: snapRect)
        }

        guard let candidate = findDisplacementCandidate(excludingPid: pid, display: displayID, screen: screen),
              let oppositePosition = position.opposite else {
            return true
        }

        let oppositeRect = Coords.rect(for: oppositePosition, on: screen)
        logger.info("External activation: displacing \(appName(candidate)) to \(oppositePosition) for \(name)")
        WindowAX.setPosition(pid: candidate, rect: oppositeRect)
        // Don't touch slots — defocus path on `candidate` next activation will
        // see it's no longer full and remove it via snapshotIfFullScreen.
        return true
    }

    /// Poll briefly, retrying snapshotIfFullScreen and displaceIfHalf until the
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
            if snapshotIfFullScreen(app: prev) {
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
                    if snapshotIfFullScreen(app: app) { done = true; return }
                    if displaceIfHalf(app: app) { done = true; return }
                }
                if done { return }
            }
        }
    }

    /// Snapshot the app's current fullscreen state into `slots`:
    /// - If its window is fullscreen-sized on its current screen, upsert.
    /// - Else, remove any prior entry.
    /// Returns true iff the app was fullscreen-sized.
    @discardableResult
    static func snapshotIfFullScreen(app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let name = appName(app)
        guard let windowRect = WindowAX.getRect(pid: pid) else {
            logger.info("snapshotIfFullScreen(\(name)): no window rect")
            slots.remove(pid: pid)
            return false
        }
        guard let screen = screenForApp(app) else {
            logger.info("snapshotIfFullScreen(\(name)): no screen")
            slots.remove(pid: pid)
            return false
        }
        let fullRect = Coords.rect(for: .fullScreen, on: screen)
        guard windowRect.approxEquals(fullRect, tolerance: positionTolerance) else {
            if slots.contains(pid: pid) {
                logger.info("snapshotIfFullScreen(\(name)): no longer fullscreen, removing")
            }
            slots.remove(pid: pid)
            return false
        }
        if !slots.contains(pid: pid) {
            logger.info("Recording \(name) (pid=\(pid)) as fullscreen on display \(screen.displayID)")
        }
        slots.upsert(pid: pid, displayID: screen.displayID)
        logger.info("Slots after upsert(\(name), pid=\(pid)): \(slots.dump())")
        return true
    }

    /// Find a valid displacement candidate on the given display, excluding the
    /// app that is about to be tiled. Walks entries newest-first and validates
    /// each: process running, window readable, still fullscreen-sized. Stale
    /// entries are pruned in-place and the next candidate is tried.
    private static func findDisplacementCandidate(
        excludingPid: pid_t,
        display: CGDirectDisplayID,
        screen: NSScreen
    ) -> pid_t? {
        let fullRect = Coords.rect(for: .fullScreen, on: screen)

        while let pid = slots.mostRecentFullScreen(forDisplay: display, excluding: excludingPid) {
            let name = appName(pid)
            logger.info("findDisplacementCandidate: considering pid=\(pid) (\(name)) on display \(display)")

            let nsra = NSRunningApplication(processIdentifier: pid)
            let posixAlive = (kill(pid, 0) == 0)
            let inWorkspaceList = NSWorkspace.shared.runningApplications.contains { $0.processIdentifier == pid }
            if nsra == nil {
                logger.info("Liveness mismatch pid=\(pid): NSRunningApplication=nil posixAlive=\(posixAlive) inWorkspaceList=\(inWorkspaceList)")
            }
            guard nsra != nil else {
                logger.info("Pruning \(name) (pid=\(pid)): process dead")
                slots.remove(pid: pid)
                continue
            }
            guard let windowRect = WindowAX.getRect(pid: pid) else {
                logger.info("Pruning \(name) (pid=\(pid)): no window")
                slots.remove(pid: pid)
                continue
            }
            guard windowRect.approxEquals(fullRect, tolerance: positionTolerance) else {
                logger.info("Pruning \(name) (pid=\(pid)): window=\(windowRect) full=\(fullRect)")
                slots.remove(pid: pid)
                continue
            }
            return pid
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
