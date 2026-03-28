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

enum WindowTiler {
    /// Tile the frontmost window of the given app to the specified position.
    /// If no app is specified, tiles the frontmost window of the currently active app.
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

        let targetRect: CGRect
        switch position {
        case .left:
            targetRect = CGRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.width / 2,
                height: frame.height
            )
        case .right:
            targetRect = CGRect(
                x: frame.origin.x + frame.width / 2,
                y: frame.origin.y,
                width: frame.width / 2,
                height: frame.height
            )
        case .fullScreen:
            targetRect = frame
        }

        // Convert from NSScreen coordinates (origin at bottom-left) to CGWindow coordinates (origin at top-left)
        let screenFull = NSScreen.main?.frame ?? screen.frame
        let cgRect = CGRect(
            x: targetRect.origin.x,
            y: screenFull.height - targetRect.origin.y - targetRect.height,
            width: targetRect.width,
            height: targetRect.height
        )

        setWindowPosition(pid: targetApp.processIdentifier, rect: cgRect)
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
