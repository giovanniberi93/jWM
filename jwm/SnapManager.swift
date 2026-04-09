import Cocoa

final class SnapManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var draggedWindowPID: pid_t?
    private var initialWindowOrigin: CGPoint?
    private var mouseDownLocation: CGPoint?
    private var windowIsMoving = false
    private var currentEdge: TilePosition?
    private var currentSnapScreen: NSScreen?
    private lazy var overlay = SnapOverlayWindow()

    private let edgeMargin: CGFloat = 5.0
    private let cursorMoveThreshold: CGFloat = 10.0

    private static let ignoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.SystemUIServer",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
    ]

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
        logger.info("SnapManager started")
    }

    private var paused = false

    func pause() {
        paused = true
        logger.info("Snap manager paused")
    }

    func resume() {
        paused = false
        logger.info("Snap manager resumed")
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        guard !paused else { return }
        switch event.type {
        case .leftMouseDown:
            handleMouseDown(event)
        case .leftMouseDragged:
            handleMouseDragged(event)
        case .leftMouseUp:
            handleMouseUp(event)
        default:
            break
        }
    }

    // MARK: - Mouse event handlers

    private func handleMouseDown(_ event: NSEvent) {
        resetState()

        let screenPoint = NSEvent.mouseLocation.screenFlipped
        guard let (pid, origin) = getWindowInfoUnderCursor(at: screenPoint) else { return }

        // Ignore system processes
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              !Self.ignoredBundleIDs.contains(bundleID) else { return }

        draggedWindowPID = pid
        initialWindowOrigin = origin
        mouseDownLocation = screenPoint
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard let pid = draggedWindowPID else { return }

        let cursor = NSEvent.mouseLocation

        // Wait for cursor to move a minimum distance before checking window movement
        if !windowIsMoving {
            let cursorFlipped = cursor.screenFlipped
            guard let mouseDown = mouseDownLocation else { return }
            let dx = abs(cursorFlipped.x - mouseDown.x)
            let dy = abs(cursorFlipped.y - mouseDown.y)
            guard dx > cursorMoveThreshold || dy > cursorMoveThreshold else { return }

            // Verify the window actually moved (not just a focus-triggered origin adjustment)
            guard let currentOrigin = getWindowOrigin(pid: pid),
                  let initialOrigin = initialWindowOrigin else { return }
            let originDx = abs(currentOrigin.x - initialOrigin.x)
            let originDy = abs(currentOrigin.y - initialOrigin.y)
            guard originDx > cursorMoveThreshold || originDy > cursorMoveThreshold else {
                return
            }
            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid=\(pid)"
            logger.info("snap: DRAG STARTED app=\(appName) initialOrigin=\(initialOrigin) currentOrigin=\(currentOrigin) cursor=\(cursorFlipped)")
            windowIsMoving = true
        }

        // Check cursor proximity to screen edges
        let result = edgeForCursor(cursor)
        let newEdge = result?.0
        let snapScreen = result?.1
        if newEdge != currentEdge || snapScreen != currentSnapScreen {
            currentEdge = newEdge
            currentSnapScreen = snapScreen
            if let edge = newEdge, let screen = snapScreen {
                let primaryHeight = NSScreen.screens[0].frame.height
                let rect = WindowTiler.rectForPosition(edge, frame: screen.visibleFrame, primaryHeight: primaryHeight)
                // rectForPosition returns CG coords (top-left origin), convert to AppKit (bottom-left)
                let appKitRect = NSRect(
                    x: rect.origin.x,
                    y: primaryHeight - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                overlay.show(at: appKitRect)
            } else {
                overlay.hide()
            }
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        defer { resetState() }

        overlay.hide()

        guard windowIsMoving,
              let edge = currentEdge,
              let screen = currentSnapScreen,
              let pid = draggedWindowPID,
              let app = NSRunningApplication(processIdentifier: pid) else { return }

        logger.info("snap: TILING app=\(app.localizedName ?? "unknown") edge=\(edge) screen=\(NSScreen.screens.firstIndex(of: screen) ?? -1) cursor=\(NSEvent.mouseLocation.screenFlipped)")
        WindowTiler.tile(edge, app: app, targetScreen: screen)
    }

    // MARK: - Edge detection

    private func edgeForCursor(_ cursor: NSPoint) -> (TilePosition, NSScreen)? {
        // Find which screen the cursor is on
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) else { return nil }
        let frame = screen.frame

        if cursor.x <= frame.minX + edgeMargin { return (.left, screen) }
        if cursor.x >= frame.maxX - edgeMargin { return (.right, screen) }
        return nil
    }

    // MARK: - Accessibility helpers

    private func getWindowInfoUnderCursor(at point: CGPoint) -> (pid_t, CGPoint)? {
        let systemWide = AXUIElementCreateSystemWide()

        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &elementRef) == .success,
              let element = elementRef else { return nil }

        // Walk up to the window element
        var current = element
        while true {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role)
            if let roleStr = role as? String, roleStr == (kAXWindowRole as String) {
                break
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parentElement = parent else { return nil }
            current = (parentElement as! AXUIElement)
        }

        var pid: pid_t = 0
        AXUIElementGetPid(current, &pid)
        guard pid > 0 else { return nil }

        // Read window position
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(current, kAXPositionAttribute as CFString, &positionRef) == .success else {
            return nil
        }
        var origin = CGPoint.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin)

        return (pid, origin)
    }

    private func getWindowOrigin(pid: pid_t) -> CGPoint? {
        let appRef = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success else {
            return nil
        }
        let window = windowRef as! AXUIElement

        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success else {
            return nil
        }
        var point = CGPoint.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
        return point
    }

    private func resetState() {
        draggedWindowPID = nil
        initialWindowOrigin = nil
        mouseDownLocation = nil
        windowIsMoving = false
        currentEdge = nil
        currentSnapScreen = nil
    }
}

// MARK: - Coordinate conversion

extension NSPoint {
    /// Convert from AppKit coordinates (bottom-left origin) to CG/screen coordinates (top-left origin).
    var screenFlipped: CGPoint {
        guard let screenHeight = NSScreen.main?.frame.height else { return self }
        return CGPoint(x: x, y: screenHeight - y)
    }
}
