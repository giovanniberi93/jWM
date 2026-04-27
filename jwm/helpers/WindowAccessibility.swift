import Cocoa
import os

/// Accessibility (AX) I/O for app windows. Pure plumbing: reads and writes
/// window position/size for a pid via `AXUIElement*`.
enum WindowAX {
    /// Read the current position and size of the frontmost window of the given app.
    static func getRect(pid: pid_t) -> CGRect? {
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

    /// Write position and size for the given app's window.
    /// `positionFirst: true` is required for cross-screen moves so macOS evaluates
    /// the resize against the target screen's bounds, not the source screen's.
    static func setPosition(pid: pid_t, rect: CGRect, positionFirst: Bool = false) {
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

        let label = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid=\(pid)"
        logger.info("Setting \(label) window to \(rect.debugDescription)")

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
