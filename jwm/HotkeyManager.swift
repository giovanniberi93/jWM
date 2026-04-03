import Cocoa
import os
import Carbon.HIToolbox

final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onFocus: ((String) -> Void)?
    private var onTile: ((TilePosition) -> Void)?
    private var onFocusTile: ((String, TilePosition) -> Void)?

    // Chord state: after cmd+N, waiting for either cmd release (focus only) or position key (tile)
    private var pendingAppKey: String?

    private let keyCodeToPosition: [Int64: TilePosition] = [
        Int64(kVK_ANSI_H): .left,
        Int64(kVK_ANSI_L): .right,
        Int64(kVK_ANSI_J): .fullScreen,
    ]

    private let keyCodeToAppNumber: [Int64: Int] = [
        Int64(kVK_ANSI_0): 0,
        Int64(kVK_ANSI_1): 1,
        Int64(kVK_ANSI_2): 2,
        Int64(kVK_ANSI_3): 3,
        Int64(kVK_ANSI_4): 4,
        Int64(kVK_ANSI_5): 5,
        Int64(kVK_ANSI_6): 6,
        Int64(kVK_ANSI_7): 7,
        Int64(kVK_ANSI_8): 8,
        Int64(kVK_ANSI_9): 9,
    ]

    /// Start listening for global hotkeys.
    /// - onFocus: called with app key (e.g. "app1" or "shiftApp1") on cmd release (focus only).
    /// - onTile: called with position for ctrl+cmd+h/l/j (tile current window).
    /// - onFocusTile: called with (slotKey, position) when position key pressed while cmd held (focus + tile).
    func start(
        onFocus: @escaping (String) -> Void,
        onTile: @escaping (TilePosition) -> Void,
        onFocusTile: @escaping (String, TilePosition) -> Void
    ) {
        self.onFocus = onFocus
        self.onTile = onTile
        self.onFocusTile = onFocusTile

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
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
            logger.info(" Failed to create event tap. Grant Accessibility permission in System Settings.")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info(" Event tap started successfully")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it gets disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.info(" Event tap was disabled, re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Double-click on title bar → tile full screen
        if type == .leftMouseUp {
            return handleMouseUp(event: event)
        }

        let flags = event.flags

        // cmd released while we have a pending app → focus only
        if type == .flagsChanged, let appKey = pendingAppKey {
            if !flags.contains(.maskCommand) {
                logger.info(" cmd released, focus only: \(appKey)")
                pendingAppKey = nil
                onFocus?(appKey)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasAlt = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)

        // If we have a pending app and cmd is still held, check for position key
        if let appKey = pendingAppKey, hasCmd {
            if let position = keyCodeToPosition[keyCode] {
                logger.info(" Chord complete: \(appKey) -> \(position)")
                pendingAppKey = nil
                onFocusTile?(appKey, position)
                return nil
            }
            // Another cmd+N while holding cmd → switch to new app
            if let appNumber = keyCodeToAppNumber[keyCode] {
                let newAppKey = hasShift ? "shiftApp\(appNumber)" : "app\(appNumber)"
                logger.info(" Switching pending app from \(appKey) to \(newAppKey)")
                pendingAppKey = newAppKey
                return nil
            }
            // Any other key with cmd held → cancel chord, pass through
            logger.info(" Chord cancelled by other key")
            pendingAppKey = nil
        }

        // ctrl+cmd+h/l/j → tile current window
        if hasCmd && hasCtrl && !hasAlt {
            if let position = keyCodeToPosition[keyCode] {
                logger.info(" Tile current window -> \(position)")
                onTile?(position)
                return nil
            }
        }

        // cmd+N or cmd+shift+N → start chord (defer focus until cmd release)
        if hasCmd && !hasCtrl && !hasAlt {
            if let appNumber = keyCodeToAppNumber[keyCode] {
                let appKey = hasShift ? "shiftApp\(appNumber)" : "app\(appNumber)"
                logger.info(" \(appKey) triggered, holding for position key...")
                pendingAppKey = appKey
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Double-click title bar → full screen

    private static let titleBarRoles: Set<String> = [
        kAXWindowRole as String,
        kAXToolbarRole as String,
        kAXStaticTextRole as String,
    ]

    private func handleMouseUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        let clickState = event.getIntegerValueField(.mouseEventClickState)
        guard clickState == 2 else { return Unmanaged.passRetained(event) }

        let point = event.location // CG coordinates (top-left origin)
        guard let (windowElement, pid, hitRole) = getWindowElementAtPoint(point) else {
            logger.info("dblclick: no window element at \(point)")
            return Unmanaged.passRetained(event)
        }

        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid=\(pid)"

        guard Self.titleBarRoles.contains(hitRole) else {
            logger.info("dblclick: rejected role=\(hitRole) app=\(appName) at \(point)")
            return Unmanaged.passRetained(event)
        }

        guard let titleBarFrame = getTitleBarFrame(windowElement: windowElement) else {
            logger.info("dblclick: no title bar frame for app=\(appName)")
            return Unmanaged.passRetained(event)
        }

        guard titleBarFrame.contains(point) else {
            logger.info("dblclick: outside title bar app=\(appName) point=\(point) frame=\(titleBarFrame)")
            return Unmanaged.passRetained(event)
        }

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return Unmanaged.passRetained(event)
        }

        logger.info("dblclick: TILING app=\(app.localizedName ?? "unknown") role=\(hitRole) point=\(point) frame=\(titleBarFrame)")
        WindowTiler.tile(.fullScreen, app: app)
        return nil // suppress the event
    }

    private func getWindowElementAtPoint(_ point: CGPoint) -> (AXUIElement, pid_t, String)? {
        let systemWide = AXUIElementCreateSystemWide()

        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &elementRef) == .success,
              let element = elementRef else { return nil }

        // Grab the role of the element that was actually hit
        var hitRoleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &hitRoleRef)
        let hitRole = (hitRoleRef as? String) ?? ""

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

        return (current, pid, hitRole)
    }

    private func getTitleBarFrame(windowElement: AXUIElement) -> CGRect? {
        // Get window frame
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        var windowOrigin = CGPoint.zero
        var windowSize = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &windowOrigin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &windowSize)

        // Get close button to calculate title bar height
        guard let closeButton = getChildElement(of: windowElement, role: kAXCloseButtonSubrole as String) else {
            return nil
        }
        var btnPosRef: CFTypeRef?
        var btnSizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(closeButton, kAXPositionAttribute as CFString, &btnPosRef) == .success,
              AXUIElementCopyAttributeValue(closeButton, kAXSizeAttribute as CFString, &btnSizeRef) == .success else {
            return nil
        }
        var btnOrigin = CGPoint.zero
        var btnSize = CGSize.zero
        AXValueGetValue(btnPosRef as! AXValue, .cgPoint, &btnOrigin)
        AXValueGetValue(btnSizeRef as! AXValue, .cgSize, &btnSize)

        let gap = btnOrigin.y - windowOrigin.y
        let titleBarHeight = 2 * gap + btnSize.height

        return CGRect(x: windowOrigin.x, y: windowOrigin.y, width: windowSize.width, height: titleBarHeight)
    }

    private func getChildElement(of element: AXUIElement, role: String) -> AXUIElement? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleRef)
            if let subrole = subroleRef as? String, subrole == role {
                return child
            }
        }
        return nil
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
