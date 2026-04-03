import Cocoa
import os

enum TilePosition: CustomStringConvertible {
    case left
    case right
    case fullScreen

    var description: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .fullScreen: return "fullScreen"
        }
    }
}

/// Tracks which app occupies each screen slot.
struct SlotState {
    var left: pid_t?
    var right: pid_t?
    var fullScreen: pid_t?
}

enum WindowTiler {
    static var slots = SlotState()

    /// Tile the frontmost window of the given app to the specified position.
    /// If no app is specified, tiles the frontmost window of the currently active app.
    /// Automatically displaces a full-screen app to the opposite half when needed.
    static func tile(_ position: TilePosition, app: NSRunningApplication? = nil) {
        let targetApp = app ?? NSWorkspace.shared.frontmostApplication
        guard let targetApp = targetApp else {
            logger.info(" No frontmost app found")
            return
        }
        logger.info(" Tiling \(targetApp.localizedName ?? "unknown") to \(position)")

        guard let screen = NSScreen.main else {
            logger.info(" No main screen found")
            return
        }
        // visibleFrame excludes the menu bar and Dock
        let frame = screen.visibleFrame
        let screenFull = screen.frame
        let cgRect = rectForPosition(position, frame: frame, screenFull: screenFull)

        let pid = targetApp.processIdentifier

        // Displace full-screen app to the opposite half if we're tiling to a half
        if position == .left || position == .right {
            if let fullPid = slots.fullScreen, fullPid != pid {
                let oppositePosition: TilePosition = (position == .left) ? .right : .left
                logger.info(" Displacing full-screen app (pid \(fullPid)) to \(oppositePosition)")
                let oppositeRect = rectForPosition(oppositePosition, frame: frame, screenFull: screenFull)
                setWindowPosition(pid: fullPid, rect: oppositeRect)
                // Update slots for the displaced app
                if oppositePosition == .left {
                    slots.left = fullPid
                } else {
                    slots.right = fullPid
                }
                slots.fullScreen = nil
            }
        }

        setWindowPosition(pid: pid, rect: cgRect)

        // Update slot tracking
        switch position {
        case .left:
            slots.left = pid
            if slots.fullScreen == pid { slots.fullScreen = nil }
            if slots.right == pid { slots.right = nil }
        case .right:
            slots.right = pid
            if slots.fullScreen == pid { slots.fullScreen = nil }
            if slots.left == pid { slots.left = nil }
        case .fullScreen:
            slots.fullScreen = pid
            if slots.left == pid { slots.left = nil }
            if slots.right == pid { slots.right = nil }
        }
    }

    static func rectForPosition(_ position: TilePosition, frame: NSRect, screenFull: NSRect) -> CGRect {
        let targetRect: CGRect
        switch position {
        case .left:
            targetRect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width / 2, height: frame.height)
        case .right:
            targetRect = CGRect(x: frame.origin.x + frame.width / 2, y: frame.origin.y, width: frame.width / 2, height: frame.height)
        case .fullScreen:
            targetRect = frame
        }
        return CGRect(
            x: targetRect.origin.x,
            y: screenFull.height - targetRect.origin.y - targetRect.height,
            width: targetRect.width,
            height: targetRect.height
        )
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
            logger.info(" kAXFocusedWindow failed (\(result.rawValue)), trying kAXWindows...")
            // Fall back to first window in the windows list
            var windowsRef: CFTypeRef?
            result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            if result == .success, let windows = windowsRef as? [AXUIElement], let first = windows.first {
                logger.info(" Found \(windows.count) window(s) via kAXWindows")
                windowRef = first
            } else {
                logger.info(" kAXWindows also failed (\(result.rawValue))")
                var names: CFArray?
                if AXUIElementCopyAttributeNames(appRef, &names) == .success, let names = names as? [String] {
                    logger.info(" Available attributes: \(names)")
                }
                return
            }
        }

        let axWindow = windowRef as! AXUIElement

        logger.info(" Setting window to \(rect.debugDescription)")

        // Set size → position → size. Setting size first avoids macOS clamping the
        // position to keep the old (larger/smaller) frame on screen. The second size
        // set corrects any adjustment macOS made after the position change.
        var position = CGPoint(x: rect.origin.x, y: rect.origin.y)
        var size = CGSize(width: rect.width, height: rect.height)

        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
            logger.info(" Final size result -> \(sizeResult.rawValue)")
        }

        if hadEnhancedUI {
            AXUIElementSetAttributeValue(appRef, enhancedUIKey, kCFBooleanTrue)
        }
    }
}
