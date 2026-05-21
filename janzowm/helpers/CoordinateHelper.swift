import Cocoa

/// AppKit and CG use opposite Y axes:
///   - AppKit (NSScreen.frame, NSEvent.mouseLocation): origin at *primary* screen's bottom-left, Y grows up.
///   - CG / Accessibility (window pos, CGEvent.location): origin at *primary* screen's top-left, Y grows down.
///
/// Conversions always reference the primary screen's height, regardless of which
/// screen the rect lives on. Using a secondary screen's height here is a
/// recurring bug source; centralize it.
enum Coords {
    /// Primary screen height. Source of truth for AppKit↔CG y-flips.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func cg(fromAppKit rect: NSRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func appKit(fromCG rect: CGRect) -> NSRect {
        NSRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func cg(fromAppKit point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func appKit(fromCG point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Find the screen containing a CG-coordinate window rect, by its center.
    /// Returns nil if no screen contains the center (window off all displays).
    static func screen(containingCG rect: CGRect) -> NSScreen? {
        let centerAppKit = appKit(fromCG: CGPoint(x: rect.midX, y: rect.midY))
        return NSScreen.screens.first { $0.frame.contains(centerAppKit) }
    }

    /// CG rect for a tile position on the given screen, using its visibleFrame
    /// (excludes menu bar and Dock). `.nextScreen` returns the full screen rect
    /// — callers handling cross-screen moves use this for the destination.
    static func rect(for position: TilePosition, on screen: NSScreen) -> CGRect {
        rect(for: position, frame: screen.visibleFrame, primaryHeight: primaryHeight)
    }

    /// Pure-logic seam for unit tests. Takes the visibleFrame and primary
    /// screen height directly so tests don't need to construct an NSScreen.
    static func rect(for position: TilePosition, frame: NSRect, primaryHeight: CGFloat) -> CGRect {
        let appKitRect: NSRect
        switch position {
        case .left:
            appKitRect = NSRect(x: frame.origin.x, y: frame.origin.y, width: frame.width / 2, height: frame.height)
        case .right:
            appKitRect = NSRect(x: frame.origin.x + frame.width / 2, y: frame.origin.y, width: frame.width / 2, height: frame.height)
        case .fullScreen, .nextScreen:
            appKitRect = frame
        }
        return CGRect(
            x: appKitRect.origin.x,
            y: primaryHeight - appKitRect.origin.y - appKitRect.height,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}

extension NSPoint {
    /// AppKit point → CG point. Convenience for `NSEvent.mouseLocation`.
    var toCG: CGPoint { Coords.cg(fromAppKit: self) }
}

extension CGRect {
    /// Component-wise equality within `tolerance` on origin and size.
    func approxEquals(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) < tolerance
            && abs(origin.y - other.origin.y) < tolerance
            && abs(width - other.width) < tolerance
            && abs(height - other.height) < tolerance
    }
}
