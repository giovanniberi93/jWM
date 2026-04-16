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

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}

enum WindowTiler {
    static var slots = SlotState()

    /// Resolve a PID to app name for logging. Falls back to "pid=N" if app is gone.
    private static func appName(_ pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid=\(pid)"
    }

    /// Tile the frontmost window of the given app to the specified position.
    /// If no app is specified, tiles the frontmost window of the currently active app.
    /// Automatically displaces a full-screen app to the opposite half when needed.
    static func tile(_ position: TilePosition, app: NSRunningApplication? = nil, targetScreen: NSScreen? = nil) {
        let targetApp = app ?? NSWorkspace.shared.frontmostApplication
        guard let targetApp = targetApp else {
            logger.info("No frontmost app found")
            return
        }
        logger.info("Tiling \(targetApp.localizedName ?? "unknown") to \(position)")
        slots.purgeDeadPids()

        if position == .nextScreen {
            let pid = targetApp.processIdentifier
            slots.clearFullScreen(pid: pid)
            if let nextScreen = moveToNextScreen(app: targetApp) {
                slots.addFullScreen(pid, forDisplay: nextScreen.displayID)
                logger.info("Set fullScreen slot on display \(nextScreen.displayID) after nextScreen move")
            }
            return
        }

        let screens = NSScreen.screens
        let screen = targetScreen ?? screenForApp(targetApp) ?? NSScreen.main
        guard let screen = screen else {
            logger.info("No screen found")
            return
        }
        let screenIndex = screens.firstIndex(of: screen) ?? -1
        logger.info("\(targetApp.localizedName ?? "unknown") is on screen \(screenIndex) (frame: \(screen.frame))")

        // visibleFrame excludes the menu bar and Dock
        let frame = screen.visibleFrame
        // CG coordinates use the primary screen's top-left as origin, so we always
        // need the primary screen's height for the AppKit→CG y-flip, even when
        // tiling on a secondary screen.
        let primaryHeight = screens[0].frame.height
        let cgRect = rectForPosition(position, frame: frame, primaryHeight: primaryHeight)

        let pid = targetApp.processIdentifier

        // Displace a full-screen app to the opposite half if we're tiling to a half.
        // Validate the candidate is still alive and still actually fullscreen-sized
        // before displacing — it may have been resized, killed, or moved since promotion.
        let displayID = screen.displayID
        if position == .left || position == .right {
            if let candidate = findDisplacementCandidate(excludingPid: pid, display: displayID, screen: screen) {
                let oppositePosition: TilePosition = (position == .left) ? .right : .left
                logger.info("Displacing \(appName(candidate)) to \(oppositePosition) on screen \(screenIndex) (display \(displayID))")
                let oppositeRect = rectForPosition(oppositePosition, frame: frame, primaryHeight: primaryHeight)
                setWindowPosition(pid: candidate, rect: oppositeRect)
                // Clear all fullscreen entries on this display — the displaced app is
                // now a half, and any older entries are buried behind the new layout.
                slots.clearDisplay(displayID)
            }
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

    static func rectForPosition(_ position: TilePosition, frame: NSRect, primaryHeight: CGFloat) -> CGRect {
        let targetRect: CGRect
        switch position {
        case .left:
            targetRect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width / 2, height: frame.height)
        case .right:
            targetRect = CGRect(x: frame.origin.x + frame.width / 2, y: frame.origin.y, width: frame.width / 2, height: frame.height)
        case .fullScreen:
            targetRect = frame
        case .nextScreen:
            targetRect = frame // unreachable; tile() returns early for .nextScreen
        }
        return CGRect(
            x: targetRect.origin.x,
            y: primaryHeight - targetRect.origin.y - targetRect.height,
            width: targetRect.width,
            height: targetRect.height
        )
    }

    /// If the given app's window occupies a left/right half, displace any
    /// full-screen app on the same display to the opposite half.
    /// Called on external activation (Spotlight, Dock, Cmd-Tab) so the
    /// two-slot model stays consistent even when jwm didn't initiate the focus.
    /// Match a window rect against the left/right half positions for a given
    /// screen frame. Returns .left or .right if within tolerance, nil otherwise.
    /// Uses tight tolerance on position (20px) and generous tolerance on size
    /// (15% of expected dimension) to catch apps that restore to roughly-half sizes.
    static func matchHalfPosition(windowRect: CGRect, frame: NSRect, primaryHeight: CGFloat) -> TilePosition? {
        let posTolerance: CGFloat = 20
        let leftRect = rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        let rightRect = rectForPosition(.right, frame: frame, primaryHeight: primaryHeight)

        func matches(_ expected: CGRect) -> Bool {
            abs(windowRect.origin.x - expected.origin.x) < posTolerance
                && abs(windowRect.origin.y - expected.origin.y) < posTolerance
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
        guard let windowRect = getWindowRect(pid: pid) else {
            logger.info("displaceIfHalf: no window rect for \(app.localizedName ?? "pid=\(pid)")")
            return false
        }
        guard let screen = screenForApp(app) else {
            logger.info("displaceIfHalf: no screen for \(app.localizedName ?? "pid=\(pid)")")
            return false
        }
        let primaryHeight = NSScreen.screens[0].frame.height
        let displayID = screen.displayID
        let frame = screen.visibleFrame

        let name = app.localizedName ?? "pid=\(pid)"
        let leftRect = rectForPosition(.left, frame: frame, primaryHeight: primaryHeight)
        let rightRect = rectForPosition(.right, frame: frame, primaryHeight: primaryHeight)
        logger.info("displaceIfHalf(\(name)): windowRect=\(windowRect) leftRect=\(leftRect) rightRect=\(rightRect) displayID=\(displayID)")

        guard let position = matchHalfPosition(windowRect: windowRect, frame: frame, primaryHeight: primaryHeight) else {
            logger.info("displaceIfHalf(\(name)): no half match")
            return false
        }

        // Snap the activated app to the exact half position
        let snapRect = rectForPosition(position, frame: frame, primaryHeight: primaryHeight)
        if windowRect != snapRect {
            logger.info("Snapping \(app.localizedName ?? "pid=\(pid)") to exact \(position)")
            setWindowPosition(pid: pid, rect: snapRect)
        }

        guard let candidate = findDisplacementCandidate(excludingPid: pid, display: displayID, screen: screen) else {
            return true
        }

        let oppositePosition: TilePosition = (position == .left) ? .right : .left
        let oppositeRect = rectForPosition(oppositePosition, frame: frame, primaryHeight: primaryHeight)
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
        guard let windowRect = getWindowRect(pid: pid) else { return false }
        guard let screen = screenForApp(app) else { return false }
        let primaryHeight = NSScreen.screens[0].frame.height
        let fullRect = rectForPosition(.fullScreen, frame: screen.visibleFrame, primaryHeight: primaryHeight)
        let tolerance: CGFloat = 5
        let displayID = screen.displayID
        guard abs(windowRect.origin.x - fullRect.origin.x) < tolerance,
              abs(windowRect.origin.y - fullRect.origin.y) < tolerance,
              abs(windowRect.width - fullRect.width) < tolerance,
              abs(windowRect.height - fullRect.height) < tolerance else {
            return false
        }
        if !slots.allFullScreen(forDisplay: displayID).contains(pid) {
            slots.clearFullScreen(pid: pid) // remove from other displays first
            slots.addFullScreen(pid, forDisplay: displayID)
            logger.info("Promoted \(app.localizedName ?? "pid=\(pid)") to fullScreen slot on display \(displayID)")
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
        let primaryHeight = NSScreen.screens[0].frame.height
        let fullRect = rectForPosition(.fullScreen, frame: screen.visibleFrame, primaryHeight: primaryHeight)
        let tolerance: CGFloat = 5

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
            guard abs(windowRect.origin.x - fullRect.origin.x) < tolerance,
                  abs(windowRect.origin.y - fullRect.origin.y) < tolerance,
                  abs(windowRect.width - fullRect.width) < tolerance,
                  abs(windowRect.height - fullRect.height) < tolerance else {
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
        let primaryHeight = NSScreen.screens[0].frame.height
        // Window rect is in CG coordinates (top-left origin). Convert center to
        // AppKit coordinates (bottom-left origin) to match NSScreen.frame.
        let windowCenter = CGPoint(
            x: windowRect.midX,
            y: primaryHeight - windowRect.midY
        )
        return NSScreen.screens.first { $0.frame.contains(windowCenter) }
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

        let frame = targetScreen.visibleFrame
        let primaryHeight = screens[0].frame.height
        let cgRect = CGRect(
            x: frame.origin.x,
            y: primaryHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )

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
