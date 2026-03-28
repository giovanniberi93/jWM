//
//  WindowTiler.swift
//  jwm
//
//  Created by Giovanni Beri on 2026-03-28.
//

import Cocoa

enum TilePosition {
    case left
    case right
    case fullScreen
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
            print("jwm: No frontmost app found")
            return
        }
        print("jwm: Tiling \(targetApp.localizedName ?? "unknown") to \(position)")

        guard let screen = NSScreen.main else {
            print("jwm: No main screen found")
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
                print("jwm: Displacing full-screen app (pid \(fullPid)) to \(oppositePosition)")
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

    private static func rectForPosition(_ position: TilePosition, frame: NSRect, screenFull: NSRect) -> CGRect {
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

    private static func setWindowPosition(pid: pid_t, rect: CGRect) {
        let appRef = AXUIElementCreateApplication(pid)

        // Try focused window first
        var windowRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)

        if result != .success {
            print("jwm: kAXFocusedWindow failed (\(result.rawValue)), trying kAXWindows...")
            // Fall back to first window in the windows list
            var windowsRef: CFTypeRef?
            result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            if result == .success, let windows = windowsRef as? [AXUIElement], let first = windows.first {
                print("jwm: Found \(windows.count) window(s) via kAXWindows")
                windowRef = first
            } else {
                print("jwm: kAXWindows also failed (\(result.rawValue))")
                // Log available attributes for debugging
                var names: CFArray?
                if AXUIElementCopyAttributeNames(appRef, &names) == .success, let names = names as? [String] {
                    print("jwm: Available attributes: \(names)")
                }
                return
            }
        }

        let axWindow = windowRef as! AXUIElement

        print("jwm: Setting window to \(rect)")

        // Set position first, then size
        var position = CGPoint(x: rect.origin.x, y: rect.origin.y)
        if let posValue = AXValueCreate(.cgPoint, &position) {
            let posResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
            print("jwm: Set position -> \(posResult.rawValue)")
        }

        var size = CGSize(width: rect.width, height: rect.height)
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            let sizeResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
            print("jwm: Set size -> \(sizeResult.rawValue)")
        }
    }
}
