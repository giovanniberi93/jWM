import Cocoa
import os

/// Private AX SPI that maps an AXUIElement to a stable CGWindowID. Rectangle,
/// Yabai, and Hammerspoon all rely on the same symbol; it's been present on
/// every macOS release since at least 10.10. We expose it via @_silgen_name
/// so we don't have to wire an Objective-C bridging header through the Xcode
/// project just for one declaration.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    /// Stable CGWindowID for a window AX element, or nil if AX refuses to
    /// produce one (rare — typically non-window elements).
    func getWindowId() -> CGWindowID? {
        var windowId: CGWindowID = 0
        let result = _AXUIElementGetWindow(self, &windowId)
        return result == .success ? windowId : nil
    }
}

/// Accessibility (AX) I/O for app windows. Pure plumbing: reads and writes
/// window position/size for a pid via `AXUIElement*`.
///
/// Bulk enumeration of an app's windows lives in `QuartzWindowList` instead —
/// AX iteration over kAXWindows scales as N synchronous IPCs into the
/// foreground app, which can stall the main thread when that app is slow.
/// AX here is used only for: (a) resolving the focused window's id, and
/// (b) the actual write path that targets a window by id.
enum WindowAX {
    /// Read the current position and size of the frontmost window of the given app.
    static func getRect(pid: pid_t) -> CGRect? {
        guard let axWindow = focusedOrFirstWindow(pid: pid) else { return nil }
        return rect(of: axWindow)
    }

    /// CGWindowID of the AX-focused window of the given app, or nil if no
    /// window is focused (or the focused element refuses to yield an id).
    /// Falls back to the first window in kAXWindows if no focus is set —
    /// same shape as Rectangle's `getFrontWindowElement`.
    static func getFocusedWindowId(pid: pid_t) -> CGWindowID? {
        focusedOrFirstWindow(pid: pid)?.getWindowId()
    }

    /// Find a specific window of an app by its CGWindowID. O(N) over
    /// kAXWindows. Returns nil if the window has closed or its id no longer
    /// resolves. Only called from the write path (`setPosition(pid:windowId:)`),
    /// so the per-window AX walk cost is paid once per displacement — not on
    /// every snapshot.
    static func findWindow(pid: pid_t, windowId: CGWindowID) -> AXUIElement? {
        let appRef = makeApplicationAXElement(pid: pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }
        return windows.first { $0.getWindowId() == windowId }
    }

    /// Resolve the AX-focused window of an app, falling back to the first
    /// entry in kAXWindows. Same fallback shape as Rectangle's
    /// `getFrontWindowElement` — some apps never set kAXFocusedWindow but
    /// still expose their window list.
    private static func focusedOrFirstWindow(pid: pid_t) -> AXUIElement? {
        let appRef = makeApplicationAXElement(pid: pid)
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success {
            return (windowRef as! AXUIElement)
        }
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], let first = windows.first else {
            return nil
        }
        return first
    }

    /// Read position + size off an already-resolved AX window element.
    private static func rect(of axWindow: AXUIElement) -> CGRect? {
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
        guard let axWindow = resolveFocusedAXWindow(pid: pid, appRef: appRef) else { return }
        writeRect(pid: pid, appRef: appRef, axWindow: axWindow, rect: rect, crossScreen: crossScreen)
    }

    /// Write to a *specific* window of an app by CGWindowID, regardless of
    /// which window currently holds focus. Used when displacing a background
    /// window (e.g. the previously-fullscreen sibling of the just-tiled one).
    /// No-op if the window has closed since its id was captured.
    static func setPosition(pid: pid_t, windowId: CGWindowID, rect: CGRect, crossScreen: Bool = false) {
        let appRef = makeApplicationAXElement(pid: pid)
        guard let axWindow = findWindow(pid: pid, windowId: windowId) else {
            logger.info("setPosition(pid=\(pid), windowId=\(windowId)): window no longer resolves")
            return
        }
        writeRect(pid: pid, appRef: appRef, axWindow: axWindow, rect: rect, crossScreen: crossScreen)
    }

    /// Resolve the focused AX window of an app for writes, with the same
    /// "fall back to first kAXWindows entry" defense the read path uses.
    /// Logs verbosely on failure because hung apps that pass the
    /// `AXIsProcessTrusted` gate still sometimes refuse this attribute.
    private static func resolveFocusedAXWindow(pid: pid_t, appRef: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        if result == .success {
            return (windowRef as! AXUIElement)
        }
        logger.info("kAXFocusedWindow failed (\(result.rawValue)), trying kAXWindows...")
        var windowsRef: CFTypeRef?
        result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        if result == .success, let windows = windowsRef as? [AXUIElement], let first = windows.first {
            logger.info("Found \(windows.count) window(s) via kAXWindows")
            return first
        }
        logger.info("kAXWindows also failed (\(result.rawValue))")
        var names: CFArray?
        if AXUIElementCopyAttributeNames(appRef, &names) == .success, let names = names as? [String] {
            logger.info("Available attributes: \(names)")
        }
        return nil
    }

    /// Shared write path: toggle AXEnhancedUserInterface, apply the 3-op
    /// rect, and run the cross-screen retry ladder. Both setPosition entry
    /// points funnel through here once they've resolved an axWindow.
    private static func writeRect(pid: pid_t, appRef: AXUIElement, axWindow: AXUIElement, rect: CGRect, crossScreen: Bool) {
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
