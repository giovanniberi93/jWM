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

/// Tracks which app occupies the full-screen slot on each display.
struct SlotState {
    private var fullScreen: [CGDirectDisplayID: pid_t] = [:]

    func fullScreen(forDisplay id: CGDirectDisplayID) -> pid_t? {
        fullScreen[id]
    }

    mutating func setFullScreen(_ pid: pid_t?, forDisplay id: CGDirectDisplayID) {
        if let pid = pid {
            fullScreen[id] = pid
        } else {
            fullScreen.removeValue(forKey: id)
        }
    }

    /// Clear the full-screen slot on any display that holds this pid.
    mutating func clearFullScreen(pid: pid_t) {
        for (id, p) in fullScreen where p == pid {
            fullScreen.removeValue(forKey: id)
        }
    }

    /// Clear any slots holding PIDs of apps that are no longer running.
    mutating func purgeDeadPids() {
        for (id, pid) in fullScreen {
            if NSRunningApplication(processIdentifier: pid) == nil {
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

    /// Tile the frontmost window of the given app to the specified position.
    /// If no app is specified, tiles the frontmost window of the currently active app.
    /// Automatically displaces a full-screen app to the opposite half when needed.
    static func tile(_ position: TilePosition, app: NSRunningApplication? = nil) {
        let targetApp = app ?? NSWorkspace.shared.frontmostApplication
        guard let targetApp = targetApp else {
            logger.info("No frontmost app found")
            return
        }
        logger.info("Tiling \(targetApp.localizedName ?? "unknown") to \(position)")
        slots.purgeDeadPids()

        if position == .nextScreen {
            slots.clearFullScreen(pid: targetApp.processIdentifier)
            moveToNextScreen(app: targetApp)
            promoteIfFullScreen(app: targetApp)
            return
        }

        let screens = NSScreen.screens
        let screen = screenForApp(targetApp) ?? NSScreen.main
        guard let screen = screen else {
            logger.info("No screen found")
            return
        }
        let screenIndex = screens.firstIndex(of: screen) ?? -1
        logger.info("Target app is on screen \(screenIndex) (frame: \(screen.frame))")

        // visibleFrame excludes the menu bar and Dock
        let frame = screen.visibleFrame
        // CG coordinates use the primary screen's top-left as origin, so we always
        // need the primary screen's height for the AppKit→CG y-flip, even when
        // tiling on a secondary screen.
        let primaryHeight = screens[0].frame.height
        let cgRect = rectForPosition(position, frame: frame, primaryHeight: primaryHeight)

        let pid = targetApp.processIdentifier

        // Displace full-screen app to the opposite half if we're tiling to a half,
        // but only if both apps are on the same screen.
        let displayID = screen.displayID
        if position == .left || position == .right {
            if let fullPid = slots.fullScreen(forDisplay: displayID), fullPid != pid,
               let displacedApp = NSRunningApplication(processIdentifier: fullPid) {
                let oppositePosition: TilePosition = (position == .left) ? .right : .left
                logger.info("Displacing full-screen app (pid \(fullPid)) to \(oppositePosition) on screen \(screenIndex) (display \(displayID))")
                let oppositeRect = rectForPosition(oppositePosition, frame: frame, primaryHeight: primaryHeight)
                setWindowPosition(pid: fullPid, rect: oppositeRect)
                slots.setFullScreen(nil, forDisplay: displayID)
            }
        }

        setWindowPosition(pid: pid, rect: cgRect)

        // Update slot tracking
        switch position {
        case .left, .right:
            slots.clearFullScreen(pid: pid)
        case .fullScreen:
            slots.clearFullScreen(pid: pid)
            slots.setFullScreen(pid, forDisplay: displayID)
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

    /// If the given app's window is fullscreen-sized, promote it to slots.fullScreen.
    static func promoteIfFullScreen(app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard let windowRect = getWindowRect(pid: pid) else { return }
        guard let screen = screenForApp(app) else { return }
        let primaryHeight = NSScreen.screens[0].frame.height
        let fullRect = rectForPosition(.fullScreen, frame: screen.visibleFrame, primaryHeight: primaryHeight)
        let tolerance: CGFloat = 5
        let displayID = screen.displayID
        if abs(windowRect.origin.x - fullRect.origin.x) < tolerance,
           abs(windowRect.origin.y - fullRect.origin.y) < tolerance,
           abs(windowRect.width - fullRect.width) < tolerance,
           abs(windowRect.height - fullRect.height) < tolerance {
            if slots.fullScreen(forDisplay: displayID) != pid {
                slots.clearFullScreen(pid: pid)
                slots.setFullScreen(pid, forDisplay: displayID)
                logger.info("Promoted \(app.localizedName ?? "pid=\(pid)") to fullScreen slot on display \(displayID)")
            }
        }
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
    private static func moveToNextScreen(app: NSRunningApplication) {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            logger.info("moveToNextScreen: only one screen, ignoring")
            return
        }

        let currentScreen = screenForApp(app)
        let currentIndex = currentScreen.flatMap { s in screens.firstIndex(of: s) } ?? 0
        let nextIndex = (currentIndex + 1) % screens.count
        let targetScreen = screens[nextIndex]
        logger.info("moveToNextScreen: moving \(app.localizedName ?? "unknown") from screen \(currentIndex) to \(nextIndex)")

        let frame = targetScreen.visibleFrame
        let primaryHeight = NSScreen.screens[0].frame.height
        let cgRect = CGRect(
            x: frame.origin.x,
            y: primaryHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )

        let pid = app.processIdentifier
        setWindowPosition(pid: pid, rect: cgRect)
    }

    private static func setWindowPosition(pid: pid_t, rect: CGRect) {
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

        logger.info("Setting window to \(rect.debugDescription)")

        var position = CGPoint(x: rect.origin.x, y: rect.origin.y)
        var size = CGSize(width: rect.width, height: rect.height)

        // size → position → size: setting size first avoids macOS clamping
        // the position to keep the old (larger/smaller) frame on screen.
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        }

        if hadEnhancedUI {
            AXUIElementSetAttributeValue(appRef, enhancedUIKey, kCFBooleanTrue)
        }
    }
}
