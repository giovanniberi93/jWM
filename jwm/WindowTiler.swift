import Cocoa
import os

enum TilePosition: CustomStringConvertible {
    case left
    case right
    case fullScreen
    case nextScreen

    var description: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .fullScreen: return "fullScreen"
        case .nextScreen: return "nextScreen"
        }
    }

    /// Mirror half. Nil for non-half positions.
    var opposite: TilePosition? {
        switch self {
        case .left: return .right
        case .right: return .left
        case .fullScreen, .nextScreen: return nil
        }
    }
}

/// Tracks which apps occupy the full-screen slot on each display.
/// Multiple apps can be fullscreen-sized simultaneously (e.g. one tiled, one
/// just focused) so we keep an ordered list per display rather than a single PID.
struct SlotState {
    private var fullScreen: [CGDirectDisplayID: [pid_t]] = [:]

    /// Primary fullscreen app for a display (last promoted). Returns nil if empty.
    func fullScreen(forDisplay id: CGDirectDisplayID) -> pid_t? {
        fullScreen[id]?.last
    }

    /// All fullscreen PIDs tracked on a display, newest last.
    func allFullScreen(forDisplay id: CGDirectDisplayID) -> [pid_t] {
        fullScreen[id] ?? []
    }

    /// Add a PID to a display's fullscreen list (no-op if already present).
    mutating func addFullScreen(_ pid: pid_t, forDisplay id: CGDirectDisplayID) {
        var list = fullScreen[id] ?? []
        if !list.contains(pid) {
            list.append(pid)
        }
        fullScreen[id] = list
    }

    /// Clear the entire fullscreen list for a display.
    mutating func clearDisplay(_ id: CGDirectDisplayID) {
        fullScreen.removeValue(forKey: id)
    }

    /// Remove a specific PID from all displays.
    mutating func clearFullScreen(pid: pid_t) {
        for id in fullScreen.keys {
            fullScreen[id]?.removeAll { $0 == pid }
            if fullScreen[id]?.isEmpty == true {
                fullScreen.removeValue(forKey: id)
            }
        }
    }

    /// Clear any entries holding PIDs of apps that are no longer running.
    mutating func purgeDeadPids() {
        for id in fullScreen.keys {
            fullScreen[id]?.removeAll { NSRunningApplication(processIdentifier: $0) == nil }
            if fullScreen[id]?.isEmpty == true {
                fullScreen.removeValue(forKey: id)
            }
        }
    }
}

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
            setWindowPosition(pid: candidate, rect: oppositeRect)
            // Clear all fullscreen entries on this display — the displaced app is
            // now a half, and any older entries are buried behind the new layout.
            slots.clearDisplay(displayID)
        }

        setWindowPosition(pid: pid, rect: cgRect)

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
        let leftRect = Coords.rect(for: .left, on: screen)
        let rightRect = Coords.rect(for: .right, on: screen)

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

    /// Returns true if a displacement actually happened.
    @discardableResult
    static func displaceIfHalf(app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let name = appName(app)
        guard let windowRect = getWindowRect(pid: pid) else {
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
            setWindowPosition(pid: pid, rect: snapRect)
        }

        guard let candidate = findDisplacementCandidate(excludingPid: pid, display: displayID, screen: screen),
              let oppositePosition = position.opposite else {
            return true
        }

        let oppositeRect = Coords.rect(for: oppositePosition, on: screen)
        logger.info("External activation: displacing \(appName(candidate)) to \(oppositePosition) for \(name)")
        setWindowPosition(pid: candidate, rect: oppositeRect)
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
        guard let windowRect = getWindowRect(pid: pid) else {
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
            guard let windowRect = getWindowRect(pid: pid) else {
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

    /// Read the current position and size of the frontmost window of the given app.
    static func getWindowRect(pid: pid_t) -> CGRect? {
        let appRef = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        if result != .success {
            var windowsRef: CFTypeRef?
            result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            if result == .success, let windows = windowsRef as? [AXUIElement], let first = windows.first {
                windowRef = first
            } else {
                return nil
            }
        }
        let axWindow = windowRef as! AXUIElement
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    /// Poll briefly and re-tile if the app restores its own window state.
    /// Some apps (especially Electron) process AX changes asynchronously.
    static func guardPosition(pid: pid_t, retile: @escaping () -> Void) {
        let expectedRect = getWindowRect(pid: pid)
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            while Date().timeIntervalSince(start) < 0.5 {
                Thread.sleep(forTimeInterval: 0.05)
                if let current = getWindowRect(pid: pid),
                   current != expectedRect {
                    logger.info("Window drifted after tiling, re-applying")
                    DispatchQueue.main.async { retile() }
                    return
                }
            }
        }
    }

    /// Find which screen the given app's window is on.
    /// Returns nil if the window rect can't be read or no screen contains it.
    private static func screenForApp(_ app: NSRunningApplication) -> NSScreen? {
        guard let windowRect = getWindowRect(pid: app.processIdentifier) else { return nil }
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
        setWindowPosition(pid: pid, rect: cgRect, positionFirst: true)
        return targetScreen
    }

    private static func setWindowPosition(pid: pid_t, rect: CGRect, positionFirst: Bool = false) {
        let appRef = AXUIElementCreateApplication(pid)

        // Some apps (e.g. Spotify/Electron) set AXEnhancedUserInterface=true,
        // which causes animated window transitions. Temporarily disable it so
        // the move is instant, then restore. Same approach as Rectangle.
        let enhancedUIKey = "AXEnhancedUserInterface" as CFString
        var enhancedUIRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appRef, enhancedUIKey, &enhancedUIRef)
        let hadEnhancedUI = (enhancedUIRef as? Bool) == true
        if hadEnhancedUI {
            AXUIElementSetAttributeValue(appRef, enhancedUIKey, kCFBooleanFalse)
        }

        // Try focused window first
        var windowRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)

        if result != .success {
            logger.info("kAXFocusedWindow failed (\(result.rawValue)), trying kAXWindows...")
            // Fall back to first window in the windows list
            var windowsRef: CFTypeRef?
            result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            if result == .success, let windows = windowsRef as? [AXUIElement], let first = windows.first {
                logger.info("Found \(windows.count) window(s) via kAXWindows")
                windowRef = first
            } else {
                logger.info("kAXWindows also failed (\(result.rawValue))")
                var names: CFArray?
                if AXUIElementCopyAttributeNames(appRef, &names) == .success, let names = names as? [String] {
                    logger.info("Available attributes: \(names)")
                }
                return
            }
        }

        let axWindow = windowRef as! AXUIElement

        logger.info("Setting \(appName(pid)) window to \(rect.debugDescription)")

        var position = CGPoint(x: rect.origin.x, y: rect.origin.y)
        var size = CGSize(width: rect.width, height: rect.height)

        if positionFirst {
            // Cross-screen: position → size → position → size (4 ops).
            //
            // macOS clamps each AX attribute against the window's current screen.
            // Neither size-first nor position-first alone works for both directions:
            //   - Small→big screen: size-first clamps the larger size to the small screen.
            //   - Big→small screen: position-first clamps position because the oversized
            //     window overflows the small screen.
            // The 4-op sequence handles both: first pos/size gets us roughly right,
            // second pos/size corrects whatever macOS clamped in the first pass.
            //
            // History: this was added, then removed in e1e1f77 because it broke
            // some other flow. Re-added because without it, windows don't fill the
            // target screen when moving between screens of different sizes. If this
            // causes problems again, fix the other flow — don't remove the 4th op.
            if let posValue = AXValueCreate(.cgPoint, &position) {
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
            }
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
            }
            if let posValue = AXValueCreate(.cgPoint, &position) {
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
            }
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
            }
        } else {
            // Same-screen: size → position → size. Setting size first avoids
            // macOS clamping the position to keep the old frame on screen.
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
            }
            if let posValue = AXValueCreate(.cgPoint, &position) {
                AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
            }
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
            }
        }

        if hadEnhancedUI {
            AXUIElementSetAttributeValue(appRef, enhancedUIKey, kCFBooleanTrue)
        }
    }
}
