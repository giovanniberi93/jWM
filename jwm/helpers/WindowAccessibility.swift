import Cocoa
import os

/// Accessibility (AX) I/O for app windows. Pure plumbing: reads and writes
/// window position/size for a pid via `AXUIElement*`.
enum WindowAX {
    /// Read the current position and size of the frontmost window of the given app.
    static func getRect(pid: pid_t) -> CGRect? {
        let appRef = makeApplicationAXElement(pid: pid)
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

    /// Write position and size for the given app's window using a 3-op sequence
    /// (size → position → size). Setting size first avoids macOS clamping
    /// position to keep the old frame on-screen; the trailing size write
    /// corrects any clamp that happened on the first size write.
    ///
    /// `crossScreen: true` enables read-back-and-retry: after the first 3-op
    /// the window's actual rect is compared to `rect`; on mismatch the 3-op
    /// is retried immediately, and if still wrong, scheduled once more on the
    /// main queue 25ms later. macOS doesn't always re-evaluate which NSScreen
    /// owns a window between consecutive AX writes, so size on the second
    /// screen can stay clamped to the source screen's bounds; the 25ms gap
    /// gives the system time to update the screen association.
    /// Same approach as Rectangle (AccessibilityElement.setFrame +
    /// WindowManager.executeTask).
    static func setPosition(pid: pid_t, rect: CGRect, crossScreen: Bool = false) {
        let appRef = makeApplicationAXElement(pid: pid)

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
                if hadEnhancedUI {
                    AXUIElementSetAttributeValue(appRef, enhancedUIKey, kCFBooleanTrue)
                }
                return
            }
        }

        let axWindow = windowRef as! AXUIElement

        let label = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid=\(pid)"
        logger.info("Setting \(label) window to \(rect.debugDescription)")

        applySizePositionSize(axWindow: axWindow, rect: rect)

        // Same-screen path: nothing more to do; clamp doesn't apply.
        if !crossScreen || rectMatches(axWindow: axWindow, target: rect) {
            if hadEnhancedUI {
                AXUIElementSetAttributeValue(appRef, enhancedUIKey, kCFBooleanTrue)
            }
            return
        }

        // Immediate retry: sometimes a second 3-op clears the clamp.
        logger.info("Cross-screen: rect mismatch after first apply — retrying immediately")
        applySizePositionSize(axWindow: axWindow, rect: rect)

        if rectMatches(axWindow: axWindow, target: rect) {
            if hadEnhancedUI {
                AXUIElementSetAttributeValue(appRef, enhancedUIKey, kCFBooleanTrue)
            }
            return
        }

        // Delayed retry on main queue. AX writes are safest from main, and the
        // 25ms gap lets macOS update which NSScreen owns the window so the
        // size write isn't clamped to the source screen any more.
        // EnhancedUI restore is deferred to the end of the delayed block so
        // the final write happens with animations still off.
        logger.info("Cross-screen: rect still mismatched — scheduling 25ms retry")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) {
            applySizePositionSize(axWindow: axWindow, rect: rect)
            if !rectMatches(axWindow: axWindow, target: rect) {
                logger.info("Cross-screen: rect still wrong after delayed retry")
            }
            if hadEnhancedUI {
                AXUIElementSetAttributeValue(appRef, enhancedUIKey, kCFBooleanTrue)
            }
        }
    }

    /// 3-op size → position → size. Used by `setPosition` and its retry path.
    private static func applySizePositionSize(axWindow: AXUIElement, rect: CGRect) {
        var size = CGSize(width: rect.width, height: rect.height)
        var position = CGPoint(x: rect.origin.x, y: rect.origin.y)

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

    /// Read window's current rect and compare to `target` within 1px on every
    /// component. Returns true if unreadable (don't loop forever on AX errors).
    private static func rectMatches(axWindow: AXUIElement, target: CGRect, tolerance: CGFloat = 1) -> Bool {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return true
        }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return abs(pos.x - target.origin.x) <= tolerance
            && abs(pos.y - target.origin.y) <= tolerance
            && abs(size.width - target.width) <= tolerance
            && abs(size.height - target.height) <= tolerance
    }

    /// Poll briefly and re-tile if the app restores its own window state.
    /// Some apps (especially Electron) process AX changes asynchronously.
    static func guardPosition(pid: pid_t, retile: @escaping () -> Void) {
        let expectedRect = getRect(pid: pid)
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            while Date().timeIntervalSince(start) < 0.5 {
                Thread.sleep(forTimeInterval: 0.05)
                if let current = getRect(pid: pid),
                   current != expectedRect {
                    logger.info("Window drifted after tiling, re-applying")
                    DispatchQueue.main.async { retile() }
                    return
                }
            }
        }
    }
}
