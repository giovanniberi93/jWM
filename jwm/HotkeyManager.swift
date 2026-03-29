//
//  HotkeyManager.swift
//  jwm
//
//  Created by Giovanni Beri on 2026-03-28.
//

import Cocoa
import os
import Carbon.HIToolbox

final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var slotHandler: ((String) -> Void)?
    private var tileHandler: ((TilePosition) -> Void)?
    private var slotTileHandler: ((String, TilePosition) -> Void)?

    // Chord state: after cmd+N, waiting for either cmd release (focus only) or position key (tile)
    private var pendingSlotKey: String?

    private let keyCodeToPosition: [Int64: TilePosition] = [
        Int64(kVK_ANSI_H): .left,
        Int64(kVK_ANSI_L): .right,
        Int64(kVK_ANSI_J): .fullScreen,
    ]

    private let keyCodeToSlot: [Int64: Int] = [
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
    /// - slotHandler: called with slot key (e.g. "slot1" or "shiftSlot1") on cmd release (focus only).
    /// - tileHandler: called with position for ctrl+cmd+h/l/j (tile current window).
    /// - slotTileHandler: called with (slotKey, position) when position key pressed while cmd held (focus + tile).
    func start(
        slotHandler: @escaping (String) -> Void,
        tileHandler: @escaping (TilePosition) -> Void,
        slotTileHandler: @escaping (String, TilePosition) -> Void
    ) {
        self.slotHandler = slotHandler
        self.tileHandler = tileHandler
        self.slotTileHandler = slotTileHandler

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
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

        let flags = event.flags

        // cmd released while we have a pending slot → focus only
        if type == .flagsChanged, let slotKey = pendingSlotKey {
            if !flags.contains(.maskCommand) {
                logger.info(" cmd released, focus only: \(slotKey)")
                pendingSlotKey = nil
                slotHandler?(slotKey)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hasCmd = flags.contains(.maskCommand)
        let hasCtrl = flags.contains(.maskControl)
        let hasAlt = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)

        // If we have a pending slot and cmd is still held, check for position key
        if let slotKey = pendingSlotKey, hasCmd {
            if let position = keyCodeToPosition[keyCode] {
                logger.info(" Chord complete: \(slotKey) -> \(position)")
                pendingSlotKey = nil
                slotTileHandler?(slotKey, position)
                return nil
            }
            // Another cmd+N while holding cmd → switch to new slot
            if let slot = keyCodeToSlot[keyCode] {
                let newSlotKey = hasShift ? "shiftSlot\(slot)" : "slot\(slot)"
                logger.info(" Switching pending slot from \(slotKey) to \(newSlotKey)")
                pendingSlotKey = newSlotKey
                return nil
            }
            // Any other key with cmd held → cancel chord, pass through
            logger.info(" Chord cancelled by other key")
            pendingSlotKey = nil
        }

        // ctrl+cmd+h/l/j → tile current window
        if hasCmd && hasCtrl && !hasAlt {
            if let position = keyCodeToPosition[keyCode] {
                logger.info(" Tile current window -> \(position)")
                tileHandler?(position)
                return nil
            }
        }

        // cmd+N or cmd+shift+N → start chord (defer focus until cmd release)
        if hasCmd && !hasCtrl && !hasAlt {
            if let slot = keyCodeToSlot[keyCode] {
                let slotKey = hasShift ? "shiftSlot\(slot)" : "slot\(slot)"
                logger.info(" \(slotKey) triggered, holding for position key...")
                pendingSlotKey = slotKey
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
