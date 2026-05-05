import Cocoa
import os
import Carbon.HIToolbox

final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onFocus: ((String) -> Void)?
    private var onTile: ((TilePosition) -> Void)?
    private var onFocusTile: ((String, TilePosition) -> Void)?
    private var onLaunchAll: (() -> Void)?
    /// Invoked immediately before any of the action callbacks above. Lets the
    /// owner snapshot the current frontmost app's state before focus shifts
    /// or tile geometry changes happen.
    private var onBeforeAction: (() -> Void)?

    // Chord state: after cmd+N, waiting for either cmd release (focus only) or position key (tile)
    private var pendingAppKey: String?

    private let keyCodeToPositionLetters: [Int64: TilePosition] = [
        Int64(kVK_ANSI_H): .left,
        Int64(kVK_ANSI_L): .right,
        Int64(kVK_ANSI_J): .fullScreen,
        Int64(kVK_ANSI_K): .nextScreen,
    ]

    private let keyCodeToPositionArrows: [Int64: TilePosition] = [
        Int64(kVK_LeftArrow): .left,
        Int64(kVK_RightArrow): .right,
        Int64(kVK_UpArrow): .fullScreen,
        Int64(kVK_DownArrow): .nextScreen,
    ]

    private var keyCodeToPosition: [Int64: TilePosition] {
        UserDefaults.standard.bool(forKey: "useArrowKeys") ? keyCodeToPositionArrows : keyCodeToPositionLetters
    }

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
    /// - onBeforeAction: called immediately before any of the above. Use to
    ///   capture the current frontmost app's state before focus/tile mutates it.
    func start(
        onFocus: @escaping (String) -> Void,
        onTile: @escaping (TilePosition) -> Void,
        onFocusTile: @escaping (String, TilePosition) -> Void,
        onLaunchAll: @escaping () -> Void = {},
        onBeforeAction: @escaping () -> Void = {}
    ) {
        self.onFocus = onFocus
        self.onTile = onTile
        self.onFocusTile = onFocusTile
        self.onLaunchAll = onLaunchAll
        self.onBeforeAction = onBeforeAction

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
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
            logger.info("Failed to create event tap. Grant Accessibility permission in System Settings.")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Event tap started successfully")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.info("Event tap was disabled by system, re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags

        // cmd released while we have a pending app → focus only
        if type == .flagsChanged, let appKey = pendingAppKey {
            if !flags.contains(.maskCommand) {
                logger.info("cmd released, focus only: \(appKey)")
                pendingAppKey = nil
                onBeforeAction?()
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
                logger.info("Chord complete: \(appKey) -> \(position)")
                pendingAppKey = nil
                onBeforeAction?()
                onFocusTile?(appKey, position)
                return nil
            }
            // Another cmd+N while holding cmd → switch to new app
            if let appNumber = keyCodeToAppNumber[keyCode] {
                let newAppKey = hasShift ? "shiftApp\(appNumber)" : "app\(appNumber)"
                logger.info("Switching pending app from \(appKey) to \(newAppKey)")
                pendingAppKey = newAppKey
                return nil
            }
            // Any other key with cmd held → cancel chord, pass through
            logger.info("Chord cancelled by other key")
            pendingAppKey = nil
        }

        // ctrl+cmd+h/l/j → tile current window
        if hasCmd && hasCtrl && !hasAlt {
            if let position = keyCodeToPosition[keyCode] {
                onBeforeAction?()
                onTile?(position)
                return nil
            }
            // ctrl+cmd+a → launch/focus all configured apps
            if keyCode == Int64(kVK_ANSI_A) {
                logger.info("Launch-all chord triggered")
                onLaunchAll?()
                return nil
            }
            // ctrl+cmd+b → debug marker in logs
            if keyCode == Int64(kVK_ANSI_B) {
                logger.error("━━━━━━━━━━━━━━━━ ERROR MARKER ━━━━━━━━━━━━━━━━")
                return nil
            }
        }

        // cmd+N or cmd+shift+N → start chord (defer focus until cmd release)
        if hasCmd && !hasCtrl && !hasAlt {
            if let appNumber = keyCodeToAppNumber[keyCode] {
                let appKey = hasShift ? "shiftApp\(appNumber)" : "app\(appNumber)"
                logger.info("\(appKey) triggered, holding for position key...")
                pendingAppKey = appKey
                return nil
            }
        }

        return Unmanaged.passRetained(event)
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
