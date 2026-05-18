import Cocoa

final class SnapManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Active event tap that clamps cursor y to >=1 during a tracked window
    /// drag. Without this, holding the cursor at y=0 (or shoving up fast)
    /// triggers macOS Mission Control mid-drag, killing the snap. Same trick
    /// as Rectangle's `ActiveEventMonitor` filter.
    private var mouseTap: CFMachPort?
    private var mouseTapSource: CFRunLoopSource?

    private var draggedWindowPID: pid_t?
    private var initialWindowOrigin: CGPoint?
    private var mouseDownLocation: CGPoint?
    private var windowIsMoving = false
    private var currentEdge: TilePosition?
    private var currentSnapScreen: NSScreen?
    private lazy var overlay = SnapOverlayWindow()

    private let edgeMargin: CGFloat = 30.0
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
        startMouseTap()
        logger.info("SnapManager started")
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
        stopMouseTap()
    }

    // MARK: - Mission Control mitigation

    /// Install a CGEventTap that intercepts `leftMouseDragged` and pins the
    /// cursor to y >= 1 (CG coords) while a window drag we're tracking is in
    /// flight. macOS triggers Mission Control when the cursor sits at y=0 for
    /// a beat or gets shoved upward fast; clamping to y=1 keeps either from
    /// firing without visibly affecting the cursor. Tap is on the main run
    /// loop — the callback's work is O(1) per event, well under tap timeout.
    private func startMouseTap() {
        let mask: CGEventMask = 1 << CGEventType.leftMouseDragged.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<SnapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleMouseTap(type: type, event: event)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            logger.info("SnapManager: failed to create mouse event tap (Mission Control mitigation disabled)")
            return
        }
        mouseTap = tap
        mouseTapSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), mouseTapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopMouseTap() {
        if let tap = mouseTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = mouseTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        mouseTap = nil
        mouseTapSource = nil
    }

    private func handleMouseTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = mouseTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Only clamp while we're actually tracking a window drag. Leaves
        // unrelated drags (text selection, other apps) untouched.
        guard draggedWindowPID != nil else { return Unmanaged.passUnretained(event) }
        let loc = event.location
        if loc.y < 1 {
            event.location = CGPoint(x: loc.x, y: 1)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleEvent(_ event: NSEvent) {
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

        let screenPoint = NSEvent.mouseLocation.toCG
        guard let (pid, origin) = getWindowInfoUnderCursor(at: screenPoint) else {
            // Distinguish: did windowAtPoint return nothing, or did it return
            // a window that getWindowInfoUnderCursor's bundleID filter rejected?
            // If the latter, the stub underneath was shadowed by an unrelated
            // hit and `.first(where:)` short-circuited before reaching it.
            let topHit = QuartzWindowList.windowAtPoint(screenPoint)
            if let hit = topHit {
                logger.info("snap: miss topHit — owner=\(hit.processName ?? "?") pid=\(hit.pid) level=\(hit.level) frame=\(hit.frame)")
            } else {
                logger.info("snap: miss topHit — windowAtPoint returned nil")
            }
            logMouseDownMiss(at: screenPoint)
            return
        }

        draggedWindowPID = pid
        initialWindowOrigin = origin
        mouseDownLocation = screenPoint
    }

    /// Dump the full Quartz on-screen window list (frame, pid, level, owner)
    /// plus the frontmost app's AX rect, so we can tell which side disagrees:
    /// is Quartz missing the window entirely, listing it at a stale frame, or
    /// is the cursor genuinely outside every window? The AX fallback line says
    /// whether `frontmost.AXrect.contains(cursor)` — i.e. whether routing to
    /// the frontmost app's window would have rescued this drag.
    private func logMouseDownMiss(at cursor: CGPoint) {
        let front = NSWorkspace.shared.frontmostApplication
        let frontName = front?.localizedName ?? "?"
        let frontPid = front?.processIdentifier ?? -1
        logger.info("snap: mouseDown missed — frontmost=\(frontName)/pid=\(frontPid) cursor=\(cursor)")

        // What does AX say for the frontmost app's focused window?
        if let pid = front?.processIdentifier, let axRect = WindowAX.getRect(pid: pid) {
            let contains = axRect.contains(cursor)
            logger.info("snap: miss ax — frontmost=\(frontName) rect=\(axRect) contains(cursor)=\(contains)")
        } else {
            logger.info("snap: miss ax — frontmost=\(frontName) rect=<unreadable>")
        }

        // Would the AX system-wide hit test have rescued this lookup?
        if let hit = WindowAX.findWindowAtPosition(cursor) {
            let app = NSRunningApplication(processIdentifier: hit.pid)
            let bid = app?.bundleIdentifier ?? "?"
            let ignored = Self.ignoredBundleIDs.contains(bid)
            logger.info("snap: miss axHitTest — would catch pid=\(hit.pid) bundle=\(bid) origin=\(hit.origin) ignored=\(ignored)")
        } else {
            logger.info("snap: miss axHitTest — system-wide AX hit test returned nil")
        }

        // First: dump every cached window whose frame contains the cursor,
        // in z-order. windowAtPoint returns the FIRST element that passes its
        // filter, so this list reveals (a) what was actually first and (b)
        // whether the stub was shadowed by something higher-z that the filter
        // didn't catch.
        let cached = QuartzWindowList.cachedSnapshot()
        var idxInCache = 0
        var containingCount = 0
        for info in cached {
            if info.frame.contains(cursor) {
                logger.info("snap: miss containing[\(idxInCache)] — owner=\(info.processName ?? "?") pid=\(info.pid) level=\(info.level) frame=\(info.frame)")
                containingCount += 1
            }
            idxInCache += 1
        }
        if containingCount == 0 {
            logger.info("snap: miss containing — no cached entries contain the cursor (cache size=\(cached.count))")
        }

        // Also dump cached entries for the frontmost pid (regardless of whether
        // their frame contains the cursor), so we can spot a duplicate/phantom
        // entry covering the same pid.
        var cachedMatching = 0
        for info in cached where info.pid == frontPid {
            cachedMatching += 1
            let contains = info.frame.contains(cursor)
            logger.info("snap: miss cache — frontmost pid=\(frontPid) owner=\(info.processName ?? "?") level=\(info.level) frame=\(info.frame) contains(cursor)=\(contains)")
        }
        if cachedMatching == 0 {
            logger.info("snap: miss cache — no entries for frontmost pid=\(frontPid) in cached list of \(cached.count) windows")
        }

        // Then: dump what Quartz sees right now (fresh fetch), so we can
        // tell whether the cache was simply stale or CGWindowListCopyWindowInfo
        // flickered.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            logger.info("snap: miss quartz — CGWindowListCopyWindowInfo returned nil")
            return
        }
        var matchingFrontmost = 0
        for dict in raw {
            guard let pidNum = dict[kCGWindowOwnerPID as String] as? NSNumber,
                  pidNum.int32Value == frontPid else { continue }
            matchingFrontmost += 1
            let level = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -999
            let owner = (dict[kCGWindowOwnerName as String] as? String) ?? "?"
            let frameDict = dict[kCGWindowBounds as String] as? NSDictionary
            let frame = frameDict.flatMap { CGRect(dictionaryRepresentation: $0) }
            let frameStr = frame.map { "\($0)" } ?? "<no bounds>"
            let contains = frame?.contains(cursor) ?? false
            logger.info("snap: miss quartz — frontmost pid=\(frontPid) owner=\(owner) level=\(level) frame=\(frameStr) contains(cursor)=\(contains)")
        }
        if matchingFrontmost == 0 {
            logger.info("snap: miss quartz — no entries for frontmost pid=\(frontPid) in list of \(raw.count) windows")
        }
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard let pid = draggedWindowPID else { return }

        let cursor = NSEvent.mouseLocation

        // Wait for cursor to move a minimum distance before checking window movement
        if !windowIsMoving {
            let cursorFlipped = cursor.toCG
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
                let appKitRect = Coords.appKit(fromCG: Coords.rect(for: edge, on: screen))
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

        logger.info("snap: TILING app=\(app.localizedName ?? "unknown") edge=\(edge) screen=\(NSScreen.screens.firstIndex(of: screen) ?? -1) cursor=\(NSEvent.mouseLocation.toCG)")
        UsageStats.record(.mouseSnap)
        WindowTiler.tile(edge, app: app, targetScreen: screen)
    }

    // MARK: - Edge detection

    private func edgeForCursor(_ cursor: NSPoint) -> (TilePosition, NSScreen)? {
        // Find which screen the cursor is on
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) else { return nil }
        let frame = screen.frame

        // Top wins over sides so corners go to fullscreen rather than half —
        // jwm has no quarter-tile concept, and "drag up = maximize" matches
        // Rectangle's default for the top snap area.
        if cursor.y >= frame.maxY - edgeMargin { return (.fullScreen, screen) }
        if cursor.x <= frame.minX + edgeMargin { return (.left, screen) }
        if cursor.x >= frame.maxX - edgeMargin { return (.right, screen) }
        return nil
    }

    // MARK: - Accessibility helpers

    private func getWindowInfoUnderCursor(at point: CGPoint) -> (pid_t, CGPoint)? {
        // Fast path: Quartz reports the owning pid via WindowServer with no
        // AX/Mach IPC into the foreground app. This avoids the systemWide AX
        // hop, which synchronously blocks the main thread when the foreground
        // app is slow or hung (most painful: NSOpenPanel's XPC service).
        if let info = QuartzWindowList.windowAtPoint(point),
           !Self.bundleIsIgnored(pid: info.pid),
           let origin = getWindowOrigin(pid: info.pid) {
            return (info.pid, origin)
        }

        // Fallback: AX system-wide hit test. `QuartzWindowList.windowAtPoint`
        // returns the topmost frame-containing entry that passes its level &
        // Dock/WindowManager filter — but that hit can be Notification Center
        // (level 21, full-screen frame) or another maximized window of a
        // *different* app sitting ahead of the user's drag target in z-order.
        // When the bundleID check then rejects that hit, the whole lookup
        // returns nil and the stub underneath is never considered. Same
        // workaround Rectangle uses in `getWindowElementUnderCursor`. Slower
        // (one IPC into the target app) but only runs on a fast-path miss.
        guard let hit = WindowAX.findWindowAtPosition(point),
              !Self.bundleIsIgnored(pid: hit.pid) else { return nil }
        logger.info("snap: AX fallback caught window pid=\(hit.pid) origin=\(hit.origin)")
        return (hit.pid, hit.origin)
    }

    /// True if the owning app's bundle ID is in `ignoredBundleIDs`, or if the
    /// pid no longer resolves to a running app. Both paths in
    /// `getWindowInfoUnderCursor` need this filter, so factoring it keeps the
    /// ignore list a single source of truth.
    private static func bundleIsIgnored(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier else { return true }
        return ignoredBundleIDs.contains(bundleID)
    }

    private func getWindowOrigin(pid: pid_t) -> CGPoint? {
        let appRef = makeApplicationAXElement(pid: pid)
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

