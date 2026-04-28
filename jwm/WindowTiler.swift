import Cocoa
import os

enum WindowTiler {
    static var slots = SlotState()
    /// The previously active app. Used to promote-check on defocus, catching
    /// apps that resized to fullscreen while they were already focused.
    /// Strong ref: the NSRunningApplication from the notification may be transient,
    /// so a weak ref would go nil before the next activation fires.
    private static var lastActiveApp: NSRunningApplication?

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
    static func tile(_ position: TilePosition, app: NSRunningApplication? = nil, targetScreen: NSScreen? = nil) {
        guard let targetApp = app ?? NSWorkspace.shared.frontmostApplication else {
            logger.info("No frontmost app found")
            return
        }
        let pid = targetApp.processIdentifier
        logger.info("Tiling \(targetApp.localizedName ?? "unknown") to \(position)")
        slots.purgeDeadPids()

        if position == .nextScreen {
            slots.clearFullScreen(pid: pid)
            if let nextScreen = moveToNextScreen(app: targetApp) {
                slots.addFullScreen(pid, forDisplay: nextScreen.displayID)
                logger.info("Set fullScreen slot on display \(nextScreen.displayID) after nextScreen move")
            }
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
        // Validate the candidate is still alive and still actually fullscreen-sized
        // before displacing — it may have been resized, killed, or moved since promotion.
        let displayID = screen.displayID
        if let oppositePosition = position.opposite,
           let candidate = findDisplacementCandidate(excludingPid: pid, display: displayID, screen: screen) {
            logger.info("Displacing \(appName(candidate)) to \(oppositePosition) on screen \(screenIndex) (display \(displayID))")
            let oppositeRect = Coords.rect(for: oppositePosition, on: screen)
            WindowAX.setPosition(pid: candidate, rect: oppositeRect)
            // Clear all fullscreen entries on this display — the displaced app is
            // now a half, and any older entries are buried behind the new layout.
            slots.clearDisplay(displayID)
        }

        WindowAX.setPosition(pid: pid, rect: cgRect)

        // Update slot tracking
        switch position {
        case .left, .right:
            slots.clearFullScreen(pid: pid)
        case .fullScreen:
            slots.clearFullScreen(pid: pid)
            slots.addFullScreen(pid, forDisplay: displayID)
        case .nextScreen:
            break // handled by early return above
        }
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
    @discardableResult
    static func displaceIfHalf(app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let name = appName(app)
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
        slots.clearDisplay(displayID)
        return true
    }

    /// Poll briefly, retrying promoteIfFullScreen and displaceIfHalf until the
    /// app's window settles. For already-running apps this fires on the first
    /// iteration; for freshly launched apps (e.g. via Spotlight) it retries
    /// until the window appears.
    static func guardActivation(app: NSRunningApplication) {
        // Before processing the new app, promote-check the one that just lost
        // focus. Catches apps that resized to fullscreen while already active
        // (no activation event would have fired for them).
        if let prev = lastActiveApp, prev.processIdentifier != app.processIdentifier {
            if promoteIfFullScreen(app: prev) {
                logger.info("Promoted \(prev.localizedName ?? "unknown") on defocus (resized while active)")
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
                    if promoteIfFullScreen(app: app) { done = true; return }
                    if displaceIfHalf(app: app) { done = true; return }
                }
                if done { return }
            }
        }
    }

    /// If the given app's window is fullscreen-sized, promote it to slots.fullScreen.
    /// Returns true if the app was promoted (or was already in the slot).
    @discardableResult
    static func promoteIfFullScreen(app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let name = appName(app)
        guard let windowRect = WindowAX.getRect(pid: pid) else {
            logger.info("promoteIfFullScreen(\(name)): no window rect")
            return false
        }
        guard let screen = screenForApp(app) else {
            logger.info("promoteIfFullScreen(\(name)): no screen")
            return false
        }
        let fullRect = Coords.rect(for: .fullScreen, on: screen)
        let displayID = screen.displayID
        guard windowRect.approxEquals(fullRect, tolerance: positionTolerance) else {
            logger.info("promoteIfFullScreen(\(name)): not fullscreen (window=\(windowRect) expected=\(fullRect))")
            return false
        }
        if !slots.allFullScreen(forDisplay: displayID).contains(pid) {
            slots.clearFullScreen(pid: pid) // remove from other displays first
            slots.addFullScreen(pid, forDisplay: displayID)
            logger.info("Promoted \(name) to fullScreen slot on display \(displayID)")
        }
        return true
    }

    /// Find a valid displacement candidate on the given display, excluding the
    /// app that is about to be tiled. Walks the fullscreen list and validates
    /// each entry: the process must still be running, still have a readable
    /// window, and that window must still be fullscreen-sized on the expected
    /// screen. Stale entries (dead, resized, moved to another screen) are
    /// pruned as we go so the list stays clean.
    private static func findDisplacementCandidate(
        excludingPid: pid_t,
        display: CGDirectDisplayID,
        screen: NSScreen
    ) -> pid_t? {
        let candidates = slots.allFullScreen(forDisplay: display)
        let fullRect = Coords.rect(for: .fullScreen, on: screen)

        for pid in candidates.reversed() {
            if pid == excludingPid { continue }
            let name = appName(pid)

            // Still running?
            guard NSRunningApplication(processIdentifier: pid) != nil else {
                logger.info("Pruning \(name) from fullscreen slot: process dead")
                slots.clearFullScreen(pid: pid)
                continue
            }

            // Still has a window we can read?
            guard let windowRect = WindowAX.getRect(pid: pid) else {
                logger.info("Pruning \(name) from fullscreen slot: no window")
                slots.clearFullScreen(pid: pid)
                continue
            }

            // Still fullscreen-sized on this display?
            guard windowRect.approxEquals(fullRect, tolerance: positionTolerance) else {
                logger.info("Pruning \(name) from fullscreen slot: window resized/moved")
                slots.clearFullScreen(pid: pid)
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
        // Cross-screen moves need position first so macOS evaluates the resize
        // against the target screen's bounds, not the source screen's.
        WindowAX.setPosition(pid: pid, rect: cgRect, positionFirst: true)
        return targetScreen
    }
}
